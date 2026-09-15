mga_enabled(case::Case) = case.settings.MGA.Enabled

function run_mga(
    case::Case,
    EP::Model,
    path::AbstractString;
    rng = Random.default_rng(),
    case_path = nothing
)
    # Make sure the least-cost model is ready before starting MGA
    termination_status(EP) == MOI.OPTIMAL || error("MGA requires an optimal least-cost solution first.")
    haskey(EP, :vMGA) && !isempty(EP[:vMGA]) || error("No MGA groups were added to the model.")
    println("MGA Module")

    mga_settings = case.settings.MGA
    slack = mga_settings.Epsilon

    # Sort the (period, group) keys so random weights and output group indices
    # do not depend on dictionary insertion order
    mga_groups = sort!(collect(keys(EP[:vMGA])))

    # Set one full-horizon budget for every solve. Using abs keeps positive
    # slack a relaxation even when the least-cost objective is negative
    least_cost = objective_value(EP)
    budget_limit = least_cost + slack * abs(least_cost)

    # Generate all jobs once, before choosing serial or parallel execution.
    jobs = mga_jobs(mga_settings.MGAAlgorithm, mga_groups, mga_settings, rng)
    isempty(jobs) && error("No MGA jobs were created")

    # In parallel mode, leave EP unchanged and prepare worker-local models
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

const MGA_VALID_GROUPINGS = ("technology", "location", "custom")

"""
    mga_group_component(e::AbstractEdge, grouping::AbstractString, edge_asset_map)

Return the Symbol identifying which sub-group `e` belongs to for one grouping
dimension ("technology", "location", or "custom").
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
    add_mga_variables(system::System, EP::Model, settings::NamedTuple)

Add capacity or weighted annual-flow aggregates for each MGA group in this
period. Edges participate if `mga_enabled` is true or `mga_group` is set.
Groups are formed by combining the dimensions in `settings.Groupings`
(any subset of "technology", "location", "custom").
"""
function add_mga_variables(system::System, EP::Model, settings::NamedTuple)
    groupings = settings.Groupings
    quantity = settings.Quantity
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

        # Define MGA groups. Only capacity aggregates get a lower bound of zero, since annual flow can be negative for bidirectional edges.
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
    mga_jobs(algorithm::AbstractString, groups, settings, rng)

Build independently schedulable objectives. Each job supplies an iteration,
group index (zero for a vector), weights (nothing for a single-group objective),
direction, and objective sense.
"""
function mga_jobs(algorithm::AbstractString, groups, settings, rng)
    jobs = NamedTuple[]
    if algorithm == "RandomVector"
        for iteration in 1:settings.NumIterations
            weights = rand(rng, length(groups))
            for (direction, sense) in (("max", MOI.MAX_SENSE), ("min", MOI.MIN_SENSE))
                push!(jobs, (; iteration, group_index = 0, weights, direction, sense))
            end
        end
    elseif algorithm == "VariableMinMax"
        for group_index in eachindex(groups)
            weights = nothing
            for (direction, sense) in (("max", MOI.MAX_SENSE), ("min", MOI.MIN_SENSE))
                push!(jobs, (; iteration = 1, group_index, weights, direction, sense))
            end
        end
    else
        throw(ArgumentError("Unknown MGAAlgorithm: $algorithm. Expected RandomVector or VariableMinMax."))
    end
    return jobs
end

"""
    solve_mga_job!(case, model, path, groups, job, system_cost, least_cost, budget_limit)

Solve and write one objective, shared by serial execution and worker processes.
Variable min/max outputs use a group-index suffix and record the group key.
"""
function solve_mga_job!(case, model, path, groups, job,
    system_cost, least_cost, budget_limit)
    (; iteration, group_index, weights, direction, sense) = job
    slack = case.settings.MGA.Epsilon
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
    postprocess!(case, model)
    write_outputs(outpath, case, model)
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
    initialize_mga_worker!(case_model, case_path, direct, solver, attributes,
                           groups, budget_limit)

Reload and rebuild direct models, or deep-copy the existing case and model.
"""
function initialize_mga_worker!(case_model, case_path, direct, solver, attributes,
                                groups, budget_limit)
    optimizer = create_optimizer(solver, opt_env(solver), attributes)
    if direct
        case = load_case(case_path)
        model = generate_model(case, optimizer, Monolithic())
    else
        case, model = deepcopy(case_model)
        set_optimizer(model, optimizer)
        model.ext[:mga_optimizer] = optimizer
    end

    system_cost = add_mga_budget!(case, model, budget_limit)
    MGA_WORKER_STATE[] = (case, model, system_cost, groups)
    return nothing
end

function solve_mga_worker_job!(job, output_path, least_cost, budget_limit)
    case, model, system_cost, groups = MGA_WORKER_STATE[]
    return solve_mga_job!(case, model, output_path, groups, job,
        system_cost, least_cost, budget_limit)
end

function clear_mga_worker_state!()
    MGA_WORKER_STATE[] = nothing
    return nothing
end

"""
    run_mga_parallel(case, model, path, case_path, groups,
        least_cost, budget_limit, jobs)

Initialize worker models independently and start assigning individual max or min
solves to each worker as soon as it is ready.
Return summaries in iteration order.
"""
function run_mga_parallel(case, model, path, case_path, groups, least_cost, budget_limit, jobs)
    mga_settings = case.settings.MGA
    worker_count = mga_settings.Workers
    worker_count > 0 || throw(ArgumentError("MGA.Workers must be positive."))
    haskey(model.ext, :mga_optimizer) || error("Parallel MGA requires generate_model's optimizer configuration.")
    opt = model.ext[:mga_optimizer]

    direct = first(get_periods(case)).settings.EnableJuMPDirectModel
    case_model = direct ? nothing : (case, model)

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
                        remotecall_fetch(initialize_mga_worker!, pid, case_model,
                            case_path, direct, opt.optimizer, opt.attributes,
                            groups, budget_limit)
                    end
                    for index in pending_jobs
                        failed[] && break
                        # Group keys stay on the worker instead of being resent for every solve.
                        results[index] = remotecall_fetch(solve_mga_worker_job!, pid,
                            jobs[index], path, least_cost, budget_limit)
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
                    remotecall_fetch(clear_mga_worker_state!, pid)
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