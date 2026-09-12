module TestMGA
using MacroEnergy, JuMP, Test, HiGHS, Random
const M = MacroEnergy
struct MGAExampleAsset <: M.AbstractAsset
    edge::M.AbstractEdge
end
@testset "MGA aggregation" begin
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    for (period, annual) in [(1, false), (2, true)]
        td = M.TimeData{M.Electricity}(time_interval=1:1:2, period_index=period,
            subperiods=[1:1:2], subperiod_indices=[1], subperiod_weights=Dict(1=>3.0))
        node = M.Node{M.Electricity}(id=:node, timedata=td)
        assets = M.AbstractAsset[]
        for (i, group, loc, cap) in [(1,:solar,:north,2.0), (2,:solar,:north,5.0), (3,:solar,:south,11.0), (4,missing,:north,100.0)]
            edge = M.UnidirectionalEdge{M.Electricity}(id=Symbol("e$i"), timedata=td,
                start_vertex=node, end_vertex=node, location=loc, mga_group=group, capacity=cap)
            edge.flow = @variable(model, [1:2])
            fix(edge.flow[1], cap)
            fix(edge.flow[2], 2cap)
            push!(assets, MGAExampleAsset(edge))
        end
        system = M.System("", (MGA=(Enabled=true, AnnualGeneration=annual),),
            Dict{Symbol,DataType}(:Electricity=>M.Electricity), Dict{Symbol,M.TimeData}(:Electricity=>td),
            assets, Union{M.Node,M.Location}[], Dict{Symbol,Any}[])
        M.add_mga_variables(system, model)
    end
    @test length(model[:vMGA]) == 2
    optimize!(model)
    @test is_solved_and_feasible(model)
    @test value(model[:vMGA][(1,:solar)]) ≈ 18
    @test value(model[:vMGA][(2,:solar)]) ≈ 162
end

@testset "Cost-based MGA pricing" begin
    for direct in (false, true)
        model = direct ? direct_model(HiGHS.Optimizer()) : Model(HiGHS.Optimizer)
        set_silent(model)
        model.ext[:mga_optimizer] = M.create_optimizer(HiGHS.Optimizer, nothing, ("output_flag"=>false,))
        @variable(model, 0 <= installed <= 2)
        @variable(model, cheap >= 0)
        @variable(model, expensive >= 0)
        @variable(model, discrete_choice, Bin)
        @constraint(model, cheap <= installed)
        @constraint(model, demand_balance, cheap + expensive == 5)
        model[:eFixedCost] = AffExpr(0.0)
        model[:eVariableCost] = @expression(model, 15cheap + 30expensive)
        model[:cMGABudget] = [@constraint(model, model[:eVariableCost] <= 120)]
        @objective(model, Max, 1.0 * cheap)
        optimize!(model)

        td = M.TimeData{M.Electricity}(time_interval=1:1:1)
        node = M.Node{M.Electricity}(id=:node, timedata=td)
        edge = M.UnidirectionalEdge{M.Electricity}(id=:cheap, timedata=td,
            start_vertex=node, end_vertex=node, capacity=installed, has_capacity=true)
        system = M.System("", M.default_settings(), Dict{Symbol,DataType}(),
            Dict{Symbol,M.TimeData}(:Electricity=>td), M.AbstractAsset[MGAExampleAsset(edge)],
            Union{M.Node,M.Location}[node], Dict{Symbol,Any}[])
        pricing_case, pricing = M.mga_pricing_model(M.Case([system], nothing), model)
        @test objective_value(pricing) ≈ 120
        @test dual(constraint_by_name(pricing, "demand_balance")) ≈ 30
        @test is_fixed(M.capacity(only(M.get_edges(only(pricing_case.systems)))))
        @test objective_sense(model) == MOI.MAX_SENSE
        @test objective_value(model) ≈ 2
        @test is_binary(discrete_choice) && !is_fixed(discrete_choice)
    end
end

root = joinpath(@__DIR__, "test_small_case")
data = copy(M.read_file(joinpath(root, "system_data.json")))
data[:case] = [deepcopy(data[:case][1]), deepcopy(data[:case][1])]
data[:settings] = Dict{Symbol,Any}(:SolutionAlgorithm=>"Monolithic", :ExpansionHorizon=>"PerfectForesight", :PeriodLengths=>[1,1])
case = M.generate_case(joinpath(root,"system_data.json"), data)
for system in case.systems
    system.settings = merge(system.settings, (MGA=(Enabled=true, Epsilon=0.1, NumIterations=1, AnnualGeneration=false),))
    for edge in M.get_edges(system)
        M.has_capacity(edge) && (edge.mga_group=:capacity)
    end
end
opt = M.create_optimizer(HiGHS.Optimizer, nothing, ("output_flag"=>false,))
@testset "Perfect foresight MGA" begin
    _, model = M.solve_case(case,opt)
    integer_choice = @variable(model, binary=true)
    optimize!(model)
    original_cost = objective_function(model)
    constraint_count = num_constraints(model; count_variable_in_set_constraints=true)
    @test length(model[:vMGA]) == 2
    output = mktempdir()
    M.write_mga_outputs(output, case, model)
    result = run_mga(case, model, output; rng=MersenneTwister(1))
    @test length(result) == 2
    @test is_binary(integer_choice) && !is_fixed(integer_choice)
    @test all(r.system_cost <= r.budget_limit + 1e-5 * abs(r.budget_limit) for r in result)
    @test is_solved_and_feasible(model)
    @test objective_value(model) ≈ last(result).mga_objective
    @test value(original_cost) ≈ last(result).system_cost
    # Scaling the retained budget can introduce additional proxy constraints.
    @test num_constraints(model; count_variable_in_set_constraints=true) >= constraint_count + 1
    @test isfile(joinpath(output,"MGAResults_max","MGA_0.1_1","mga_summary.csv"))
    @test all(s.settings.DualExportsEnabled for s in case.systems)
    @test isfile(joinpath(output, "MGAResults_max", "MGA_0.1_1", "pricing_summary.csv"))
    @test isfile(joinpath(output, "MGAResults_min", "MGA_0.1_1", "results_period_2", "balance_duals.csv"))
    for system in case.systems
        system.settings = merge(system.settings, (DualExportsEnabled=false,))
    end
    without_duals = mktempdir()
    M.write_mga_outputs(without_duals, case, model)
    @test !isfile(joinpath(without_duals, "pricing_summary.csv"))
    @test !isfile(joinpath(without_duals, "results_period_1", "balance_duals.csv"))
    @test is_solved_and_feasible(model)
    myopic = M.Case(case.systems, merge(case.settings,(ExpansionHorizon=M.Myopic(),)))
    @test_throws ErrorException M.validate_mga(myopic)
    benders = M.Case(case.systems, merge(case.settings,(SolutionAlgorithm=M.Benders(),)))
    @test_throws ErrorException M.validate_mga(benders)
end

end
