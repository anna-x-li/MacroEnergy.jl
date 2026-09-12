using MacroEnergy, JuMP, Gurobi, Random, Test, CSV, DataFrames, JSON3
const M = MacroEnergy
# Run separately: julia --project test/test_mga_threezone.jl
# Solar/Wind are planned types; use the existing VRE implementation in a copy.
source = joinpath(@__DIR__, "..", "ExampleSystems/electricity_3zone")
fixture = joinpath(mktempdir(), "electricity_3zone")
cp(source, fixture)
for (file, planned_type) in (("solar.json", "Solar"), ("wind.json", "Wind"))
    path = joinpath(fixture, "assets", file)
    write(path, replace(read(path, String), "\"type\": \"$planned_type\"" => "\"type\": \"VRE\""))
end
# Use the approved MA solar profile for the missing ME solar time series.
solar_path = joinpath(fixture, "assets", "solar.json")
write(solar_path, replace(read(solar_path, String), "\"header\": \"ME_solar_pv\"" => "\"header\": \"MA_solar_pv\""))
# Source and emissions nodes must not inherit an electricity demand balance.
nodes_path = joinpath(fixture, "system", "nodes.json")
nodes_data = JSON3.read(read(nodes_path, String), Dict{String,Any})
for group in nodes_data["nodes"]
    if group["type"] in ("CO2", "NaturalGas", "Uranium")
        get!(group["global_data"], "constraints", Dict{String,Any}())["BalanceConstraint"] = false
    end
end
write(nodes_path, JSON3.write(nodes_data))
case = M.load_case(fixture)
for system in M.get_periods(case)
    system.settings = merge(system.settings, (DualExportsEnabled=false,))
end
opt = M.create_optimizer(Gurobi.Optimizer, nothing, ("Method"=>2, "Crossover"=>1, "BarConvTol"=>1e-4))
case, model = M.solve_case(case, opt)
@test termination_status(model) == MOI.OPTIMAL
baseline = objective_value(model)
println("BASELINE_COST=", baseline, " GROUPS=", sort(collect(keys(model[:vMGA]))))
output = mktempdir(;prefix="threezone_mga_", cleanup=false)
println("OUTPUT_DIRECTORY=", output)
flush(stdout)
M.write_mga_outputs(output, case, model)
results = M.run_mga(case, model, output; rng=MersenneTwister(42))
@testset "Three-zone MGA integration" begin
    @test length(results) == 20
    @test all(r.objective_function <= r.budget_limit + 1e-6 * abs(baseline) for r in results)
    @test all(r.objective_function >= baseline - 1e-6 * abs(baseline) for r in results)
    for i in 1:10
        hi, lo = results[2i-1], results[2i]
        @test hi.direction == "max" && lo.direction == "min"
        @test hi.mga_objective >= lo.mga_objective - 1e-6
        for r in (hi,lo)
            dir = joinpath(output,"MGAResults_" * r.direction,"MGA_0.01_" * string(i))
            summary = CSV.read(joinpath(dir,"mga_summary.csv"), DataFrame)
            @test only(summary.direction) == r.direction
            @test isfile(joinpath(dir,"capacity.csv"))
            @test !isfile(joinpath(dir,"balance_duals.csv"))
        end
    end
    @test any(results[2i-1].mga_objective > results[2i].mga_objective + 1e-3 for i in 1:10)
    @test all(!s.settings.DualExportsEnabled for s in M.get_periods(case))
end
CSV.write(joinpath(output,"all_mga_summaries.csv"),DataFrame(results))
println("SUCCESS OUTPUT_DIRECTORY=", output)
