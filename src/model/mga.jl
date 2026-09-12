"""
    run_mga(case::Case, EP::Model, path::AbstractString; rng=Random.default_rng())

Generate alternatives by maximizing and minimizing random weighted capacity or
annual-flow aggregates, following the GenX MGA algorithm. The budget applies to
the original discounted cost of the entire perfect-foresight model. The model
retains the final MGA objective, budget, and solution.
"""
function run_mga(case::Case, EP::Model, path::AbstractString; rng=Random.default_rng())
    mga_enabled(case) || return NamedTuple[] # what is this
    validate_mga(case)
    termination_status(EP) == MOI.OPTIMAL || error("MGA requires an optimal least-cost solution first.")
    haskey(EP, :vMGA) && !isempty(EP[:vMGA]) || error("No MGA groups were added to the model.")
    println("MGA Module")

    # Get the MGA slack
    mga_settings = first(get_periods(case)).settings.MGA
    slack = mga_settings.Epsilon

    # Get mga_groups that were created in add_mga_variables
    mga_groups = sort!(collect(keys(EP[:vMGA])))

    # Record exisiting contraints, since scaling constraints could create multiple new constraints
    constraints_without_mga_budget = JuMP.all_constraints(EP; include_variable_in_set_constraints=true)

    # Add constraint to set budget for MGA iterations
    least_cost = objective_value(EP)
    system_cost = objective_function(EP)
    budget_limit = least_cost + slack * abs(least_cost)
    @constraint(EP, mga_budget, system_cost <= budget_limit)

    if first(get_periods(case)).settings.ConstraintScaling # Scale budget constraint if ConstraintScaling is enabled
        scale_constraints!(ConstraintRef[mga_budget])
    end

    # Store the newly added constraints for MGA, so they can be removed later for finding the duals
    EP[:cMGABudget] = setdiff(JuMP.all_constraints(EP; include_variable_in_set_constraints=true),
        constraints_without_mga_budget)

    # Create results directories for MGA iterations
    outpath_max = mkpath(joinpath(path, "MGAResults_max"))
    outpath_min = mkpath(joinpath(path, "MGAResults_min"))
    results = NamedTuple[]

    # Begin MGA iterations for maximization and minimization objective ###

    print("Starting the first MGA iteration")

    for i in 1:mga_settings.NumIterations
        # Create random coefficients for the groups of edges that we want to include in the MGA run for the given budget
        pRand = rand(rng, length(mga_groups))

        ### Maximization objective
        @objective(EP,
            Max,
            sum(pRand[k] * EP[:vMGA][group]
            for (k, group) in enumerate(mga_groups)))
        
        # Solve Model Iteration
        optimize!(EP)
        termination_status(EP) == MOI.OPTIMAL || error("MGA max iteration $i failed: $(termination_status(EP))")

        # Create path for saving MGA iterations
        mgaoutpath_max = joinpath(outpath_max, string("MGA", "_", slack, "_", i))

        # Write the MGA results
        write_mga_outputs(mgaoutpath_max, case, EP)
        summary = (iteration = i,
                    direction="max",
                    mga_objective = objective_value(EP),
                    objective_function = value(system_cost),
                    least_cost = least_cost,
                    budget_limit = budget_limit)
        CSV.write(joinpath(mgaoutpath_max, "mga_summary.csv"), DataFrame([summary]))
        push!(results, summary)

        ### Minimization objective, using the same random coefficients
        @objective(EP,
            Min,
            sum(pRand[k] * EP[:vMGA][group]
            for (k, group) in enumerate(mga_groups)))

        # Solve Model Iteration
        optimize!(EP)
        termination_status(EP) == MOI.OPTIMAL || error("MGA min iteration $i failed: $(termination_status(EP))")
        
        # Create path for saving MGA iterations
        mgaoutpath_min = joinpath(outpath_min, string("MGA", "_", slack, "_", i))
        write_mga_outputs(mgaoutpath_min, case, EP)
        summary = (iteration = i,
                    direction="min",
                    mga_objective = objective_value(EP),
                    objective_function = value(system_cost),
                    least_cost = least_cost,
                    budget_limit = budget_limit)
        CSV.write(joinpath(mgaoutpath_min, "mga_summary.csv"), DataFrame([summary]))
        push!(results, summary)

    end

    return results
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
        return Symbol(nameof(typeof(edge_asset_map[id(e)][])))
    elseif grouping == "location"
        if ismissing(e.location)
            @warn "Edge $(id(e)) has no location for MGA grouping; Will be grouped with other edges without a location."
        end
        return coalesce(e.location, :none)
    elseif grouping == "custom"
        if ismissing(mga_group(e))
            @warn "Edge $(id(e)) has no custom group for MGA grouping; Will be grouped with other edges without a custom group."
        end
        return coalesce(mga_group(e), :none)
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

        # Variables
        vMGA = @variable(EP, lower_bound = 0, base_name = "vMGA_$(period)_$(group_name)")
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
    pricing = Model()
    # MOI copying also supports a source constructed in JuMP direct mode.
    index_map = MOI.copy_to(backend(pricing), backend(model))
    references = JuMP.ReferenceMap(pricing, index_map)
    set_optimizer(pricing, model.ext[:mga_optimizer])

    # Copy the case with its JuMP references pointing to the pricing model.
    memo = IdDict{Any,Any}(model => pricing)
    for variable in all_variables(model)
        memo[variable] = references[variable]
    end
    for constraint in JuMP.all_constraints(model; include_variable_in_set_constraints=true)
        memo[constraint] = references[constraint]
    end
    pricing_case = Base.deepcopy_internal(case, memo)

    if haskey(model, :cMGABudget)
        for constraint in model[:cMGABudget]
            delete(pricing, references[constraint])
        end
    end

    # Hold continuous investment decisions fixed too, not only integer builds.
    investment_variables = Set{VariableRef}()
    for system in get_periods(case)
        for component in vcat(get_edges(system), get_storages(system))
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
    for variable in all_variables(model)
        discrete = is_binary(variable) || is_integer(variable)
        if discrete || variable in investment_variables
            copied = references[variable]
            is_binary(copied) && unset_binary(copied)
            is_integer(copied) && unset_integer(copied)
            fix(copied, discrete ? round(value(variable)) : value(variable); force=true)
        end
    end

    @objective(pricing, Min, references[model[:eFixedCost] + model[:eVariableCost]])
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
    # Make output path and postprocess results
    mkpath(path)
    postprocess!(case, model)

    # If dual exports are not enabled for any period, write outputs and return
    if !any(system.settings.DualExportsEnabled for system in get_periods(case))
        write_outputs(path, case, model)
        return nothing
    end

    # Write the original MGA results with dual exports temporarily disabled
    periods = get_periods(case)
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

    # # Calculate cost-based duals with the selected portfolio and discrete decisions fixed
    # pricing_case, pricing = mga_pricing_model(case, model)
    # settings = get_settings(case)
    # scaling = parameter_scaling_factor(settings)

    # # Write pricing duals using the existing output functions
    # for (period_idx, system) in enumerate(get_periods(pricing_case))
    #     if !system.settings.DualExportsEnabled
    #         continue
    #     end

    #     # Clear copied balance duals so the writer reads the new pricing solution
    #     for node in get_nodes(system)
    #         constraint = get_constraint_by_type(node, BalanceConstraint)
    #         if !isnothing(constraint)
    #             constraint.constraint_dual = missing
    #         end
    #     end

    #     results_dir = mkpath_for_period(path, number_of_periods(case), period_idx)
    #     discount = compute_variable_cost_discount_scaling(period_idx, settings)
    #     write_duals(results_dir, system, scaling, discount)

    #     # Write full time series of balance duals if requested and TDR is used
    #     if settings.WriteFullTimeseries && has_tdr(system)
    #         fullts_dir = mkpath(joinpath(results_dir, "full_time_series"))
    #         write_balance_duals_full_timeseries(
    #             joinpath(fullts_dir, "balance_duals.csv"), system, scaling, discount)
    #     end
    # end

    # # Record the pricing solve's discounted system cost in original units
    # CSV.write(joinpath(path, "pricing_summary.csv"), DataFrame(
    #     discounted_objective_function=[objective_value(pricing) * scaling^2]))
    return nothing
end
