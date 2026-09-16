# Run separately: julia --project test/test_mga_serial.jl
using MacroEnergy, JuMP, HiGHS, Random, Test, JSON3, Distributed, CSV, DataFrames
const M = MacroEnergy

@testset "MGA settings and objectives" begin
    configured = M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:Enabled => true)))
    @test configured.MGA.MGAAlgorithm == "RandomVector"
    @test !haskey(configured.MGA, :Parallel)
    @test !haskey(configured.MGA, :Workers)

    @test_throws ArgumentError M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:MGAAlgorithm => "unknown")))
end

mktempdir() do root
    fixture = joinpath(root, "case")
    cp(joinpath(@__DIR__, "test_small_case"), fixture)

    settings_path = joinpath(fixture, "settings", "case_settings.json")
    settings = JSON3.read(read(settings_path, String), Dict{String,Any})
    settings["MGA"] = Dict(
        "Enabled" => true,
        "NumIterations" => 3,
        "Epsilon" => 0.1,
        "Groupings" => ["custom"],
        "Quantity" => "capacity"
    )
    write(settings_path, JSON3.write(settings))
    macro_path = joinpath(fixture, "settings", "macro_settings.json")
    macro_settings = JSON3.read(read(macro_path, String), Dict{String,Any})
    macro_settings["DualExportsEnabled"] = false
    write(macro_path, JSON3.write(macro_settings))

    asset_path = joinpath(fixture, "assets", "vre.json")
    data = JSON3.read(read(asset_path, String), Dict{String,Any})
    for asset in data["VRE"]["instance_data"]
        asset["edges"]["edge"]["mga_group"] = asset["id"]
    end
    write(asset_path, JSON3.write(data))

    opt = M.create_optimizer(HiGHS.Optimizer, nothing, ("output_flag" => false, "threads" => 1))
    case = M.load_case(fixture)
    _, model = M.solve_case(case, opt)
    baseline = objective_value(model)
    before_workers = workers()
    path = joinpath(root, "random")
    results = M.run_mga(case, model, path; rng = MersenneTwister(42))

    @testset "Sequential random-vector solves" begin
        @test length(results) == 6
        @test [result.direction for result in results] == repeat(["max", "min"], 3)
        @test workers() == before_workers
        @test haskey(model, :cMGABudget)
        @test objective_sense(model) == JuMP.MOI.MIN_SENSE
        for result in results
            @test result.least_cost == baseline
            @test result.objective_function <= result.budget_limit + 1e-6 * abs(baseline)
            output = joinpath(path, "MGAResults_$(result.direction)", "MGA_0.1_$(result.iteration)")
            @test isfile(joinpath(output, "results", "capacity.csv"))
            @test only(CSV.read(joinpath(output, "mga_summary.csv"), DataFrame).direction) == result.direction
        end
    end

    settings["MGA"]["MGAAlgorithm"] = "VariableMinMax"
    settings["MGA"]["NumIterations"] = 0
    write(settings_path, JSON3.write(settings))
    variable_case = M.load_case(fixture)
    _, variable_model = M.solve_case(variable_case, opt)
    variable_path = joinpath(root, "variable")
    variable_results = M.run_mga(variable_case, variable_model, variable_path)

    @testset "Sequential variable min/max solves" begin
        @test length(variable_results) == 2 * length(variable_model[:vMGA])
        @test [result.direction for result in variable_results] == repeat(["max", "min"], length(variable_model[:vMGA]))
        @test workers() == before_workers
        for result in variable_results
            @test result.iteration == 1
            @test result.objective_function <= result.budget_limit + 1e-6 * abs(result.least_cost)
            output = joinpath(variable_path, "MGAResults_$(result.direction)",
                "MGA_0.1_1_group_$(result.group_index)")
            @test isfile(joinpath(output, "mga_summary.csv"))
            @test !isfile(joinpath(output, "pricing_summary.csv"))
        end
    end
end
