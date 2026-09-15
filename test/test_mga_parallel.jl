# Run separately: julia --project test/test_mga_parallel.jl
using MacroEnergy, JuMP, HiGHS, Random, Test, JSON3, Distributed, CSV, DataFrames
const M = MacroEnergy

@testset "MGA parallel settings" begin
    @test M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:Enabled => true))).MGA.MGAAlgorithm == "RandomVector"
    @test !M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:Enabled => true))).MGA.Parallel
    @test M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:Parallel => true, :Workers => 2))).MGA.Workers == 2
    @test_throws AssertionError M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:Workers => 0)))
end

@testset "MGA algorithm jobs" begin
    groups = [(1, (:a,)), (1, (:b,))]
    settings = (NumIterations = 3,)
    random_jobs = M.mga_jobs("RandomVector", groups, settings, MersenneTwister(42))
    @test length(random_jobs) == 6
    @test random_jobs[1].weights == random_jobs[2].weights
    @test [job.direction for job in random_jobs] == repeat(["max", "min"], 3)
    variable_jobs = M.mga_jobs("VariableMinMax", groups, settings, MersenneTwister(42))
    @test length(variable_jobs) == 4
    @test all(job.iteration == 1 for job in variable_jobs)
    @test all(isnothing(job.weights) for job in variable_jobs)
    @test [job.group_index for job in variable_jobs] == [1, 1, 2, 2]
    @test M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:MGAAlgorithm => "VariableMinMax", :NumIterations => 0))).MGA.NumIterations == 0
    @test_throws ArgumentError M.configure_case(Dict{Symbol,Any}(:MGA => Dict{Symbol,Any}(:MGAAlgorithm => "unknown")))
end

mktempdir() do root
    # Copy the small case so changes to the test inputs do not affect the source files
    fixture = joinpath(root, "case")
    cp(joinpath(@__DIR__, "test_small_case"), fixture)

    # Use three iterations on two workers to check model reuse across jobs
    settings_path = joinpath(fixture, "settings", "case_settings.json")
    settings = JSON3.read(read(settings_path, String), Dict{String,Any})
    settings["MGA"] = Dict(
            "Enabled" => true,
            "Parallel" => true,
            "Workers" => 2,
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

    # Give each VRE asset its own group in the input files loaded by every worker
    asset_path = joinpath(fixture, "assets", "vre.json")
    data = JSON3.read(read(asset_path, String), Dict{String,Any})
    for asset in data["VRE"]["instance_data"]
        asset["edges"]["edge"]["mga_group"] = asset["id"]
    end
    write(asset_path, JSON3.write(data))

    # Solve the least-cost problem once, with one solver thread per process
    opt = M.create_optimizer(HiGHS.Optimizer, nothing, ("output_flag" => false, "threads" => 1))
    case = M.load_case(fixture)
    _, model = M.solve_case(case, opt)
    baseline = objective_value(model)
    before_workers = workers()

    # Let the input settings select parallel execution and check that EP stays unchanged
    parallel_path = joinpath(root, "parallel")
    parallel = M.run_mga(case, model, parallel_path;
        case_path = fixture, rng = MersenneTwister(42))
    @testset "Parallel results and ownership" begin
        @test length(parallel) == 6
        @test workers() == before_workers
        @test objective_value(model) == baseline
        @test !haskey(model, :cMGABudget)
    end

    @testset "Variable min/max serial/parallel equivalence" begin
        variable_case = M.load_case(fixture)
        variable_case = M.Case(variable_case.systems,
            merge(variable_case.settings, (MGA = merge(variable_case.settings.MGA,
                (MGAAlgorithm = "VariableMinMax", NumIterations = 0)),)))
        _, variable_model = M.solve_case(variable_case, opt)
        variable_path = joinpath(root, "variable_parallel")
        parallel_variables = M.run_mga(variable_case, variable_model, variable_path; case_path = fixture)
        variable_case = M.Case(variable_case.systems,
            merge(variable_case.settings,
                (MGA = merge(variable_case.settings.MGA, (Parallel = false,)),)))
        serial_variables = M.run_mga(variable_case, variable_model,
            joinpath(root, "variable_serial"))
        @test length(parallel_variables) == length(serial_variables) == 2 * length(variable_model[:vMGA])
        @test all(result.iteration == 1 for result in parallel_variables)
        for (serial_result, parallel_result) in zip(serial_variables, parallel_variables)
            @test serial_result.group == parallel_result.group
            @test serial_result.direction == parallel_result.direction
            @test serial_result.mga_objective ≈ parallel_result.mga_objective rtol=1e-6 atol=1e-7
            @test parallel_result.objective_function <= parallel_result.budget_limit + 1e-6 * abs(baseline)
            output = joinpath(variable_path, "MGAResults_$(parallel_result.direction)",
                "MGA_0.1_1_group_$(parallel_result.group_index)")
            @test isfile(joinpath(output, "mga_summary.csv"))
            @test !isfile(joinpath(output, "pricing_summary.csv"))
            @test !isfile(joinpath(output, "results", "balance_duals.csv"))
        end
        @test workers() == before_workers
    end

    # Repeat the same random objectives serially and compare the summaries and outputs
    serial_path = joinpath(root, "serial")
    case = M.Case(case.systems,
        merge(case.settings, (MGA = merge(case.settings.MGA, (Parallel = false,)),)))
    serial = M.run_mga(case, model, serial_path; rng = MersenneTwister(42))
    @testset "Serial/parallel equivalence" begin
        for (serial_summary, parallel_summary) in zip(serial, parallel)
            @test (serial_summary.iteration, serial_summary.direction) == (parallel_summary.iteration, parallel_summary.direction)
            @test serial_summary.mga_objective ≈ parallel_summary.mga_objective rtol=1e-6 atol=1e-7
            @test parallel_summary.least_cost == baseline
            @test parallel_summary.objective_function <= parallel_summary.budget_limit + 1e-6 * abs(baseline)

            # Check that the worker wrote the existing output layout and its summary
            output = joinpath(parallel_path, "MGAResults_$(parallel_summary.direction)",
                "MGA_0.1_$(parallel_summary.iteration)")
            @test isfile(joinpath(output, "results", "capacity.csv"))
            @test only(CSV.read(joinpath(output, "mga_summary.csv"), DataFrame).direction) == parallel_summary.direction
        end
        @test objective_sense(model) == MOI.MIN_SENSE
        @test haskey(model, :cMGABudget)
    end

end
