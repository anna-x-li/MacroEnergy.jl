# Run separately (requires a Gurobi license and several minutes):
# julia --project test/test_mga_pricing_threezone.jl
module TestMGAThreezoneNoPricing
using MacroEnergy, JuMP, Gurobi, Random, Test, CSV, DataFrames
const M = MacroEnergy

source = joinpath(@__DIR__, "..", "ExampleSystems", "electricity_3zone")
output_root = mkpath(joinpath(source, "results_mga_debug"))
output = mktempdir(output_root; prefix="verified_", cleanup=false)
println("MGA integration outputs: ", abspath(output))
flush(stdout)

case = M.load_case(source)
for system in M.get_periods(case)
    system.settings = merge(system.settings, (DualExportsEnabled=false,))
end
case = M.Case(case.systems, merge(case.settings,
    (MGA=merge(case.settings.MGA,
        (MGAAlgorithm="RandomVector", Parallel=true, Workers=2, NumIterations=2)),)))
optimizer = M.create_optimizer(Gurobi.Optimizer, nothing,
    ("Method"=>2, "Crossover"=>0, "BarConvTol"=>1e-8, "OutputFlag"=>1,
        "TimeLimit"=>120.0))
_, model = M.solve_case(case, optimizer)
baseline = objective_value(model)
println("Least-cost solve complete: ", termination_status(model))
flush(stdout)

@testset "Three-zone MGA without pricing" begin
    @test termination_status(model) == MOI.OPTIMAL
    parallel = M.run_mga(case, model, joinpath(output, "parallel");
        case_path=source, rng=MersenneTwister(1))
    println("Parallel MGA complete")
    flush(stdout)
    @test objective_value(model) == baseline
    @test !haskey(model, :cMGABudget)

    case = M.Case(case.systems,
        merge(case.settings, (MGA=merge(case.settings.MGA, (Parallel=false,)),)))
    serial = M.run_mga(case, model, joinpath(output, "serial"); rng=MersenneTwister(1))
    @test length(serial) == length(parallel) == 4
    for (s, p) in zip(serial, parallel)
        @test s.mga_objective ≈ p.mga_objective rtol=1e-5
    end
    for (mode, results) in (("serial", serial), ("parallel", parallel)), result in results
        @test result.objective_function <= result.budget_limit + 1e-6 * abs(baseline)
        path = joinpath(output, mode, "MGAResults_$(result.direction)",
            "MGA_$(case.settings.MGA.Epsilon)_$(result.iteration)")
        @test !isfile(joinpath(path, "pricing_summary.csv"))
        @test !isfile(joinpath(path, "results", "balance_duals.csv"))
    end
end
println("MGA integration passed. Outputs: ", abspath(output))
flush(stdout)
end
