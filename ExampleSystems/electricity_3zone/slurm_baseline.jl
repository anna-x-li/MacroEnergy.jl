using MacroEnergy
using Gurobi
using JuMP

length(ARGS) == 1 || error("Usage: julia slurm_baseline.jl RUN_DIR")
run_dir = abspath(ARGS[1])
case_dir = @__DIR__
attributes = ("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-6)

MacroEnergy.setup_user_additions(case_dir)
MacroEnergy.load_user_additions(case_dir)
MacroEnergy.refresh_user_type_registries!()

case = MacroEnergy.load_case(case_dir)
case.settings.MGA.MGAAlgorithm == "VariableMinMax" ||
    error("These Slurm scripts currently support MGAAlgorithm = VariableMinMax")
optimizer = MacroEnergy.create_optimizer(Gurobi.Optimizer, nothing, attributes)
case, model = MacroEnergy.solve_case(case, optimizer)
termination_status(model) == JuMP.MOI.OPTIMAL ||
    error("Baseline solve failed: $(termination_status(model))")

groups = sort!(collect(keys(model[:vMGA])))
isempty(groups) && error("No MGA groups were added to the baseline model")
least_cost = objective_value(model)

mkpath(run_dir)
mkpath(joinpath(run_dir, "baseline"))
MacroEnergy.postprocess!(case, model)
MacroEnergy.write_outputs(joinpath(run_dir, "baseline"), case, model)

# Write the manifest last, so the shell script submits jobs only after outputs complete.
write(joinpath(run_dir, "least_cost.txt"), string(least_cost, "\n"))
write(joinpath(run_dir, "mga_job_count.txt"), string(2 * length(groups), "\n"))
println("Baseline cost: $least_cost; MGA groups: $(length(groups)); array tasks: $(2 * length(groups))")
