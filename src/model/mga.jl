# Dispatch on the algorithm so job creation stays separate from solving and writing results.
abstract type MGASolutionAlgorithm end
struct RandomVector <: MGASolutionAlgorithm end
struct VariableMinMax <: MGASolutionAlgorithm end

mga_solution_algorithm(algorithm::MGASolutionAlgorithm) = algorithm
function mga_solution_algorithm(name::AbstractString)
    name == "RandomVector" && return RandomVector()
    name == "VariableMinMax" && return VariableMinMax()
    throw(ArgumentError("Unknown MGAAlgorithm: $name. Expected RandomVector or VariableMinMax."))
end

"""
    mga_jobs(algorithm::MGASolutionAlgorithm, groups, settings, rng)

Build independently schedulable objectives. Extend this function for new MGA
algorithms. Each job supplies an iteration, group index (zero for a vector),
weights (nothing for a single-group objective), direction, and objective sense.
Job order determines summary order, even when parallel solves finish out of order.
"""
function mga_jobs(::RandomVector, groups, settings, rng)
    jobs = NamedTuple[]
    for iteration in 1:settings.NumIterations
        # Use the same random direction for the max/min pair. Draw on the main
        # process so the seed gives the same objectives in serial and parallel runs.
        weights = rand(rng, length(groups))
        for (direction, sense) in (("max", MOI.MAX_SENSE), ("min", MOI.MIN_SENSE))
            push!(jobs, (; iteration, group_index = 0, weights, direction, sense))
        end
    end
    return jobs
end

function mga_jobs(::VariableMinMax, groups, settings, rng)
    jobs = NamedTuple[]
    for group_index in eachindex(groups)
        # The group index identifies the entire objective; avoid storing an
        # N-element one-hot vector for each of the N groups.
        weights = nothing
        for (direction, sense) in (("max", MOI.MAX_SENSE), ("min", MOI.MIN_SENSE))
            push!(jobs, (; iteration = 1, group_index, weights, direction, sense))
        end
    end
    return jobs
end

"""
    run_mga(case::Case, EP::Model, path::AbstractString; rng=Random.default_rng(),
            case_path=nothing)

Generate alternatives using `MGA.MGAAlgorithm`: `RandomVector` optimizes random
weighted aggregates for `NumIterations`; `VariableMinMax` optimizes each group
once in each direction, ignoring `NumIterations`. The budget applies to
the original discounted cost of the entire perfect-foresight model. The model
retains the final MGA objective, budget, and solution in serial mode.
With `MGA.Parallel=true`, the caller's model retains its least-cost solution.
Parallel mode transfers a solver-free copy of the existing case and model to
each worker, preserving in-memory model changes. `case_path` is used only to
load user additions during worker startup. `MGA.Workers` limits active workers.
The project, user additions, and outputs must be accessible on all nodes.
Solver environments are created on workers using `opt_env`; custom
caller environments are not transferred. Execution mode and worker count are
read from the case's `MGA.Parallel` and `MGA.Workers` settings.
"""
function run_mga(
    case::Case,
    EP::Model,
    path::AbstractString;
    rng = Random.default_rng(),
    case_path = nothing
)
    # Make sure the least-cost model is ready before starting MGA
    mga_enabled(case) || return NamedTuple[]
    validate_mga(case)
    termination_status(EP) == MOI.OPTIMAL || error("MGA requires an optimal least-cost solution first.")
    haskey(EP, :vMGA) && !isempty(EP[:vMGA]) || error("No MGA groups were added to the model.")
    println("MGA Module")

    # All periods share these settings (checked by validate_mga)
    mga_settings = first(get_periods(case)).settings.MGA
    slack = mga_settings.Epsilon

    # Sort the (period, group) keys so random weights and output group indices
    # do not depend on dictionary insertion order
    mga_groups = sort!(collect(keys(EP[:vMGA])))

    # Set one full-horizon budget for every solve. Using abs keeps positive
    # slack a relaxation even when the least-cost objective is negative
    least_cost = objective_value(EP)
    budget_limit = least_cost + slack * abs(least_cost)

    # Generate all jobs once, before choosing serial or parallel execution.
    jobs = mga_jobs(mga_solution_algorithm(mga_settings.MGAAlgorithm), mga_groups, mga_settings, rng)
    isempty(jobs) && error("No MGA jobs were created")

    # In parallel mode, leave EP unchanged and transfer copies to the workers
    if mga_settings.Parallel
        isnothing(case_path) && error("Parallel MGA requires case_path to load user additions on workers.")
        return run_mga_parallel(case, EP, path, case_path, mga_groups,
            least_cost, budget_limit, jobs)
    end

    # If not in parallel mode, solve sequentially
    system_cost = add_mga_budget!(case, EP, budget_limit)
    results = NamedTuple[]
    for job in jobs
        push!(results, solve_mga_job!(case, EP, path, mga_groups, job,
            system_cost, least_cost, budget_limit))
    end
    return results
end

"""
    add_mga_budget!(case::Case, model::Model, budget_limit)

Add the MGA cost budget and return the original cost expression. Record all
constraints introduced by the budget, including any created during scaling.
"""
function add_mga_budget!(case::Case, model::Model, budget_limit)
    # Save the original cost objective before replacing it with an MGA objective
    system_cost = objective_function(model)

    # Only scaling needs a model-wide snapshot: it can replace the budget and
    # add proxy constraints, all of which must be removed for cost-based pricing.
    scaling = first(get_periods(case)).settings.ConstraintScaling
    constraints_before = scaling ?
        Set(JuMP.all_constraints(model; include_variable_in_set_constraints = true)) : nothing

    # Add the budget using the same scaling function used during model generation
    @constraint(model, mga_budget, system_cost <= budget_limit)
    if scaling
        # The scaler uses the constraint name to replace its registered entry.
        # Keep this name even when general JuMP string naming is disabled.
        set_name(mga_budget, "mga_budget")
        scale_constraints!(ConstraintRef[mga_budget])
        model[:cMGABudget] = filter(
            constraint -> constraint ∉ constraints_before,
            JuMP.all_constraints(model; include_variable_in_set_constraints = true))
    else
        model[:cMGABudget] = ConstraintRef[mga_budget]
    end
    return system_cost
end

"""
    solve_mga_job!(case, model, path, groups, job, system_cost, least_cost, budget_limit)

Solve and write one objective, shared by serial execution and worker processes.
Variable min/max outputs use a group-index suffix and record the group key.
"""
function solve_mga_job!(case, model, path, groups, job,
    system_cost, least_cost, budget_limit)
    (; iteration, group_index, weights, direction, sense) = job
    slack = first(get_periods(case)).settings.MGA.Epsilon
    # Random-vector jobs use every group; min/max jobs need just one variable.
    # Replace only the objective so the solver can reuse the existing model.
    variables = model[:vMGA]
    if group_index == 0
        @objective(model, sense,
            sum(weights[k] * variables[group] for (k, group) in enumerate(groups)))
    else
        @objective(model, sense, variables[groups[group_index]])
    end
    optimize!(model)
    termination_status(model) == MOI.OPTIMAL ||
        error("MGA $direction iteration $iteration group $group_index failed: $(termination_status(model))")

    # Give each job its own directory so parallel writers never share files.
    suffix = group_index == 0 ? "" : "_group_$(group_index)"
    outpath = joinpath(path, "MGAResults_$direction", "MGA_$(slack)_$(iteration)$(suffix)")
    write_mga_outputs(outpath, case, model)
    # Report both the MGA objective and the original discounted system cost.
    summary = (
        iteration = iteration,
        direction = direction,
        mga_objective = objective_value(model),
        objective_function = value(system_cost),
        least_cost = least_cost,
        budget_limit = budget_limit
    )
    if group_index != 0
        summary = merge(summary, (group_index = group_index, group = string(groups[group_index])))
    end
    CSV.write(joinpath(outpath, "mga_summary.csv"), DataFrame([summary]))
    return summary
end

# Each process has its own copy of this reference. Store its case, model, cost
# expression, and group keys here so subsequent jobs reuse the model without sending it between processes.
const MGA_WORKER_STATE = Ref{Any}(nothing)

"""
    copy_case_model(case::Case, model::Model)

Copy the mathematical model into a solver-free JuMP model and remap the case
and registered model objects to its references. Build this copy once on the
main process and transfer the case and model together so serialization preserves
their shared references. No input loading or MACRO model generation is needed.

Return the copied case, copied model, and JuMP reference map. MOI copying
accepts direct-mode source models. Solver state, environments, optimize hooks,
and model extension data are not copied.
"""
function copy_case_model(case::Case, model::Model)
    # Copy mathematical objects without carrying native solver state across processes.
    model_copy = Model()
    index_map = MOI.copy_to(backend(model_copy), backend(model))
    references = JuMP.ReferenceMap(model_copy, index_map)
    set_string_names_on_creation(model_copy, JuMP.set_string_names_on_creation(model))

    # JuMP references are immutable. Base.deepcopy_internal does not consult
    # its memo for immutable objects on every supported Julia version, so it
    # can copy the old index even when MOI.copy_to has renumbered that index.
    # Remap references explicitly while copying containers and case objects.
    memo = IdDict{Any,Any}(model => model_copy)
    deepcopy_memo = IdDict{Any,Any}(model => model_copy)
    function copy_object(@nospecialize(object))
        if object isa Union{VariableRef,ConstraintRef}
            return references[object]
        elseif isbits(object) || object isa Union{Symbol,AbstractString,Type,Function,Module}
            return object
        elseif object isa AbstractArray &&
                (isbitstype(eltype(object)) || eltype(object) <: AbstractString)
            # Copy numeric time series in bulk; their elements need no remapping.
            return Base.deepcopy_internal(object, deepcopy_memo)
        elseif object isa Union{JSON3.Array,JSON3.Object}
            # Parsed input data cannot contain JuMP references and is read-only.
            return Base.deepcopy_internal(object, deepcopy_memo)
        elseif haskey(memo, object)
            return memo[object]
        elseif object isa Tuple || object isa NamedTuple
            return map(copy_object, object)
        end

        # Seed the memo before descending so shared objects and cycles in the
        # network still point to the same copied nodes, edges, and expressions.
        copied = Base.deepcopy_internal(object, deepcopy_memo)
        memo[object] = copied
        if object isa AbstractDict
            empty!(copied)
            for (key, value) in object
                copied[copy_object(key)] = copy_object(value)
            end
        elseif object isa AbstractSet
            # Sets store their elements in an internal Dict, so reconstructing
            # via the type's fields (as the generic branch below does) would
            # call Set{T}(dict) and iterate it as Pairs. Mutate in place instead.
            empty!(copied)
            for element in object
                push!(copied, copy_object(element))
            end
        elseif object isa AbstractArray
            for index in eachindex(object)
                isassigned(object, index) || continue
                copied[index] = copy_object(object[index])
            end
        elseif ismutabletype(typeof(object))
            for field in Base.fieldnames(typeof(object))
                isdefined(object, field) || continue
                setfield!(copied, field, copy_object(getfield(object, field)))
            end
        else
            # Assets may be immutable structs containing mutable edges.
            copied = typeof(object)((copy_object(getfield(object, field))
                for field in Base.fieldnames(typeof(object)))...)
            memo[object] = copied
        end
        return copied
    end
    case_copy = copy_object(case)
    for (name, object) in JuMP.object_dictionary(model)
        model_copy[name] = copy_object(object)
    end
    return case_copy, model_copy, references
end

"""
    initialize_mga_worker!(case_model_copy, solver, attributes, groups, budget_limit)

Receive an independent case/model copy and attach a
worker-local solver. Reuse this model for all jobs assigned to the worker.
The main process supplies the budget; workers do not repeat the least-cost solve.
"""
function initialize_mga_worker!(case_model_copy, solver, attributes, groups, budget_limit)
    case, model = case_model_copy

    # Native solver environments cannot be transferred between processes.
    optimizer = create_optimizer(solver, opt_env(solver), attributes)
    set_optimizer(model, optimizer)
    model.ext[:mga_optimizer] = optimizer

    # Check that the copied variables use the same ordering as the job definitions.
    worker_groups = sort!(collect(keys(model[:vMGA])))
    worker_groups == groups || error("Worker MGA groups differ from the supplied MGA jobs.")

    system_cost = add_mga_budget!(case, model, budget_limit)
    MGA_WORKER_STATE[] = (case, model, system_cost, groups)
    return nothing
end

"""
    run_mga_parallel(case, model, path, case_path, groups,
        least_cost, budget_limit, jobs)

Initialize worker models independently and start assigning individual max or min
solves to each worker as soon as it is ready.
Return summaries in iteration order and remove only workers started by this run.
"""
function run_mga_parallel(case, model, path, case_path, groups, least_cost, budget_limit, jobs)
    mga_settings = first(get_periods(case)).settings.MGA
    worker_count = mga_settings.Workers
    worker_count > 0 || throw(ArgumentError("MGA.Workers must be positive."))
    isempty(jobs) && return NamedTuple[]
    haskey(model.ext, :mga_optimizer) || error("Parallel MGA requires generate_model's optimizer configuration.")
    opt = model.ext[:mga_optimizer]

    case_copy, model_copy, _ = copy_case_model(case, model)
    case_model_copy = (case_copy, model_copy)

    # Workers may have different working directories, so pass absolute paths
    case_path = abspath(case_path)
    path = abspath(path)

    # Julia returns process 1 from workers() when no other processes exist; exclude it
    existing_workers = filter(pid -> pid != 1, workers())
    mga_workers = Int[]
    try
        if isempty(existing_workers)
            # Reuse the Benders local/SLURM/LSF startup and user-addition loading.
            start_distributed_processes!(case_path, min(worker_count, length(jobs)); prepare_workers = false)
        end

        # Limit active workers to the requested count, available processes, and number of solves
        available_workers = filter(pid -> pid != 1, workers())
        number_of_workers = min(worker_count, length(jobs), length(available_workers))
        mga_workers = first(available_workers, number_of_workers)
        isempty(mga_workers) && error("No MGA workers available.")

        # Main-process tasks share a queue of job indices. Closing a filled channel
        # lets every task finish when the queue is drained, without stop messages.
        pending_jobs = Channel{Int}(length(jobs))
        for index in eachindex(jobs)
            put!(pending_jobs, index)
        end
        close(pending_jobs)
        results = Vector{NamedTuple}(undef, length(jobs))
        failed = Ref(false)

        # Each task prepares one worker, then dispatches jobs to it immediately.
        # This sync waits for the entire run, not for all workers to initialize.
        @sync for pid in mga_workers
            @async begin
                try
                    create_worker_process(pid, Pkg.project().path, case_path)
                    if !failed[]
                        remotecall_fetch(initialize_mga_worker!, pid, case_model_copy,
                            opt.optimizer, opt.attributes, groups, budget_limit)
                    end
                    for index in pending_jobs
                        failed[] && break
                        # Group keys stay on the worker instead of being resent for every solve.
                        results[index] = remotecall_fetch(pid, jobs[index], path,
                            least_cost, budget_limit) do job, output_path, cost, budget
                            worker_case, worker_model, system_cost, worker_groups = MGA_WORKER_STATE[]
                            solve_mga_job!(worker_case, worker_model, output_path,
                                worker_groups, job, system_cost, cost, budget)
                        end
                    end
                catch
                    # Stop assigning new jobs; let in-flight calls finish before cleanup.
                    failed[] = true
                    rethrow()
                end
            end
        end
        return results
    finally
        # Release models on reused workers, but leave those processes available to the caller
        for pid in mga_workers
            if pid in existing_workers
                try
                    remotecall_fetch(pid) do
                        MGA_WORKER_STATE[] = nothing
                        nothing
                    end
                catch err
                    @warn "Could not clear MGA state on worker $pid" exception = (err, catch_backtrace())
                end
            end
        end

        # case_cleanup() removes every worker, so remove only processes started here
        new_workers = setdiff(filter(pid -> pid != 1, workers()), existing_workers)
        if !isempty(new_workers)
            rmprocs(new_workers)
        end
    end
end

const MGA_VALID_GROUPINGS = ("technology", "location", "custom")

"""
    mga_group_component(e::AbstractEdge, grouping::AbstractString, edge_asset_map)

Return the Symbol identifying which sub-group `e` belongs to for one grouping
dimension ("technology", "location", or "custom"). Edges without a value for a
given dimension (e.g. no `mga_group` set) fall into a shared `:none` bucket
rather than being dropped from the grouping, with a warning identifying the edge.
`edge_asset_map` maps edge ids to
their owning asset (from `get_edges(system; return_ids_map=true)`), which is
where the "technology" grouping comes from, since edges have no technology
field of their own.
"""
function mga_group_component(e::AbstractEdge, grouping::AbstractString, edge_asset_map)
    if grouping == "technology"
        return nameof(typeof(edge_asset_map[id(e)][]))
    elseif grouping == "location"
        if ismissing(e.location)
            @warn "Edge $(id(e)) has no location for MGA grouping; will be grouped with other edges without a location."
        end
        return coalesce(e.location, :none)
    elseif grouping == "custom"
        group = mga_group(e)
        if ismissing(group)
            @warn "Edge $(id(e)) has no custom group for MGA grouping; will be grouped with other edges without a custom group."
        end
        return coalesce(group, :none)
    else
        error("Unknown MGA grouping: \"$grouping\". Allowed values are $MGA_VALID_GROUPINGS.")
    end
end

"""
    add_mga_variables(system::System, EP::Model)

Add capacity or weighted annual-flow aggregates for each MGA group in this
period. Edges participate if `mga_enabled` is true or `mga_group` is set.
Groups are formed by combining the dimensions in `system.settings.MGA.Groupings`
(any subset of "technology", "location", "custom"). Call after capacity
expressions and operational variables have been created.
"""
function add_mga_variables(system::System, EP::Model)
    groupings = system.settings.MGA.Groupings
    quantity = system.settings.MGA.Quantity
    period = period_index(system)

    # Make sure MGA groupngs are valid
    unknown = setdiff(groupings, MGA_VALID_GROUPINGS)
    isempty(unknown) || error("Unknown MGA grouping(s): $unknown. Allowed values are $MGA_VALID_GROUPINGS.")

   # Get aray of edges and the map of edges to assets (so you can find the technology type of an edge if needed)
    edges, edge_asset_map = get_edges(system; return_ids_map=true)

    # Find edges to be included in mga, which are any edges that have mga_enabled = true or a non-missing mga_group
    edges_included_in_mga = filter(e -> (mga_enabled(e) == true) || (mga_group(e) !== missing), edges)

    # Define a function that makes a tuple of the grouping components for an edge
    # Eg: mga_group_key(e) -> (:SolarPV, :Zone1)
    mga_group_key(e) = Tuple(mga_group_component(e, g, edge_asset_map) for g in groupings)

    # Sort edges into groups based on their mga_group_key
    edge_groups = Dict{NTuple{length(groupings), Symbol}, Vector{AbstractEdge}}()
    for e in edges_included_in_mga
        key = mga_group_key(e)

        # If this key doesn't exist in the dictionary yet, create a new entry with an empty vector
        if !haskey(edge_groups, key)
            edge_groups[key] = Vector{AbstractEdge}()
        end

        push!(edge_groups[key], e)
    end

    # Store each period's variables and constraints
    if !haskey(EP, :vMGA)
        EP[:vMGA] = Dict{Tuple{Int,NTuple{length(groupings),Symbol}},VariableRef}()
        EP[:cMGA] = Dict{Tuple{Int,NTuple{length(groupings),Symbol}},ConstraintRef}()
    end

    # Add MGA variables and constraints for each group in this period, based on the selected quantity (capacity or annual flow)
    for (group, mga_edges) in edge_groups
        key = (period, group)
        group_name = join(group, "_")

        # Annual flow can be negative for bidirectional edges, so only capacity
        # aggregates get a zero lower bound. The equality below defines the value.
        vMGA = @variable(EP, base_name = "vMGA_$(period)_$(group_name)")
        if quantity == "capacity"
            set_lower_bound(vMGA, 0)
        end
        EP[:vMGA][key] = vMGA

        # Constraint to compute total annual flow or capacity for this group
        if quantity == "annual_flow"
            EP[:cMGA][key] = @constraint(EP,
                vMGA == sum(flow(e, t) * subperiod_weight(e, current_subperiod(e, t))
                    for e in mga_edges for t in time_interval(e))) 
        elseif quantity == "capacity"
            EP[:cMGA][key] = @constraint(EP,
                vMGA == sum(capacity(e) for e in mga_edges))
        else
            error("Unknown MGA quantity: \"$quantity\". Allowed values are \"annual_flow\", \"capacity\".")
        end
    end

    return nothing
end

mga_enabled(case::Case) = any(system.settings.MGA.Enabled for system in get_periods(case))

function validate_mga(case::Case)
    mga_enabled(case) || return nothing
    expansion_horizon(case) isa PerfectForesight || error("MGA requires PerfectForesight; myopic runs are not supported.")
    solution_algorithm(case) isa Monolithic || error("MGA currently requires the Monolithic solution algorithm.")
    # Mixing quantities or groupings across periods would give inconsistent
    # objectives; a single budget also requires one common slack setting.
    settings = first(get_periods(case)).settings.MGA
    all(system.settings.MGA == settings for system in get_periods(case)) ||
        error("MGA settings must be identical in every planning period.")
    return nothing
end

"""
    mga_pricing_model(case::Case, model::Model)

Copy the solved model for cost-based pricing. Fix all edge/storage investment
variables and all discrete decisions to the selected solution, remove the MGA
budget, and minimize full-horizon discounted cost. The source model is unchanged.
"""
function mga_pricing_model(case::Case, model::Model)
    assert_is_solved_and_feasible(model)
    haskey(model.ext, :mga_optimizer) || error("MGA pricing requires a model created by generate_model(case, optimizer, Monolithic()).")
    pricing_case, pricing, references = copy_case_model(case, model)
    set_optimizer(pricing, model.ext[:mga_optimizer])

    # Pricing measures marginal operating cost for the chosen portfolio, so
    # remove the near-optimal cost restriction and any budget scaling constraints.
    if haskey(pricing, :cMGABudget)
        for constraint in pricing[:cMGABudget]
            delete(pricing, constraint)
        end
    end

    # Hold continuous investment decisions fixed too, not only integer builds.
    investment_variables = Set{VariableRef}()
    for system in get_periods(case)
        for component in Iterators.flatten((get_edges(system), get_storages(system)))
            has_capacity(component) || continue
            decisions = (capacity(component), new_units(component), retired_units(component))
            if component isa AbstractEdge
                decisions = (decisions..., retrofitted_units(component))
            end
            for decision in decisions
                if decision isa VariableRef
                    push!(investment_variables, decision)
                elseif decision isa AffExpr
                    union!(investment_variables, (variable for (_, variable) in linear_terms(decision)))
                end
            end
        end
    end
    
    # Relax integrality before fixing discrete choices to their solved values.
    # Continuous investment variables are constrained within a small numerical
    # tolerance of their solved values to avoid pricing infeasibility from
    # solver feasibility residuals.
    fix_tolerance = 1e-4

    for variable in all_variables(model)
        discrete = is_binary(variable) || is_integer(variable)

        if discrete || variable in investment_variables
            copied = references[variable]

            is_binary(copied) && unset_binary(copied)
            is_integer(copied) && unset_integer(copied)

            if discrete
                # Discrete investment decisions should remain exact.
                fix(copied, round(value(variable)); force=true)
            else
                # Allow only a tiny numerical deviation from the MGA solution.
                solved_value = value(variable)
                @constraint(
                    pricing,
                    solved_value - fix_tolerance <= copied <= solved_value + fix_tolerance
                )
            end
        end
    end

    # Restore full-horizon cost; duals of the MGA objective are not cost prices.
    @objective(pricing, Min, pricing[:eFixedCost] + pricing[:eVariableCost])
    optimize!(pricing)
    assert_is_solved_and_feasible(pricing)
    has_duals(pricing) || error("The MGA pricing solve did not return duals.")
    return pricing_case, pricing
end

"""
    write_mga_outputs(path::AbstractString, case::Case, model::Model)

Write the selected MGA solution. If `DualExportsEnabled` is true for any period,
perform one separate cost-minimizing pricing solve with the selected portfolio
and discrete decisions fixed, and export its duals for enabled periods. The
original model and solution remain available for subsequent MGA iterations.
"""
function write_mga_outputs(path::AbstractString, case::Case, model::Model)
    # Postprocess the selected solution before copying it for pricing. The copy
    # is made only when dual exports are requested, once for the entire horizon.
    mkpath(path)
    postprocess!(case, model)

    # If dual exports are not enabled for any period, write outputs and return
    periods = get_periods(case)
    if !any(system.settings.DualExportsEnabled for system in periods)
        write_outputs(path, case, model)
        return nothing
    end

    # Write the original MGA results with dual exports temporarily disabled
    original_settings = [system.settings for system in periods]
    try
        for system in periods
            system.settings = merge(system.settings, (DualExportsEnabled=false,))
        end
        write_outputs(path, case, model)
    finally
        # Restore the original settings even if writing outputs fails
        for (system, settings) in zip(periods, original_settings)
            system.settings = settings
        end
    end

    # Save the user's settings instead of the temporary dual export override
    write_settings(case, joinpath(path, "settings.json"))

    # Calculate cost-based duals with the selected portfolio and discrete decisions fixed
    pricing_case, pricing = mga_pricing_model(case, model)
    settings = get_settings(case)
    scaling = parameter_scaling_factor(settings)

    # Write pricing duals using the existing output functions
    for (period_idx, system) in enumerate(get_periods(pricing_case))
        if !system.settings.DualExportsEnabled
            continue
        end

        # Clear copied balance duals so the writer reads the new pricing solution
        for node in get_nodes(system)
            constraint = get_constraint_by_type(node, BalanceConstraint)
            if !isnothing(constraint)
                constraint.constraint_dual = missing
            end
        end

        results_dir = mkpath_for_period(path, number_of_periods(case), period_idx)
        discount = compute_variable_cost_discount_scaling(period_idx, settings)
        write_duals(results_dir, system, scaling, discount)

        # Write full time series of balance duals if requested and TDR is used
        if settings.WriteFullTimeseries && has_tdr(system)
            fullts_dir = mkpath(joinpath(results_dir, "full_time_series"))
            write_balance_duals_full_timeseries(
                joinpath(fullts_dir, "balance_duals.csv"), system, scaling, discount)
        end
    end

    # Record the pricing solve's discounted system cost in original units
    CSV.write(joinpath(path, "pricing_summary.csv"), DataFrame(
        discounted_objective_function=[objective_value(pricing) * scaling^2]))
    return nothing
end
