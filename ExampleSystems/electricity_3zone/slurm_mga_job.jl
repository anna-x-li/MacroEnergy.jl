using MacroEnergy
using Gurobi
using JuMP
using CSV
using DataFrames

length(ARGS) == 2 || error("Usage: julia slurm_mga_job.jl RUN_DIR ARRAY_TASK_ID")
run_dir = abspath(ARGS[1])
job_index = parse(Int, ARGS[2])
case_dir = @__DIR__
attributes = ("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-6)

MacroEnergy.setup_user_additions(case_dir)
MacroEnergy.load_user_additions(case_dir)
MacroEnergy.refresh_user_type_registries!()

case = MacroEnergy.load_case(case_dir)
case.settings.MGA.MGAAlgorithm == "VariableMinMax" ||
    error("These Slurm scripts currently support MGAAlgorithm = VariableMinMax")
optimizer = MacroEnergy.create_optimizer(Gurobi.Optimizer, nothing, attributes)
model = MacroEnergy.generate_model(case, optimizer, MacroEnergy.Monolithic())

groups = sort!(collect(keys(model[:vMGA])))
expected_count = parse(Int, strip(read(joinpath(run_dir, "mga_job_count.txt"), String)))
length(groups) * 2 == expected_count ||
    error("MGA group count changed since baseline: expected $(expected_count ÷ 2), found $(length(groups))")
1 <= job_index <= expected_count || error("Array task ID $job_index is out of range")

group_index = (job_index + 1) ÷ 2
direction = isodd(job_index) ? "max" : "min"
sense = isodd(job_index) ? JuMP.MOI.MAX_SENSE : JuMP.MOI.MIN_SENSE
least_cost = parse(Float64, strip(read(joinpath(run_dir, "least_cost.txt"), String)))
budget_limit = least_cost + case.settings.MGA.Epsilon * abs(least_cost)
system_cost = objective_function(model)
scaling = first(MacroEnergy.get_periods(case)).settings.ConstraintScaling
constraints_before = scaling ?
    Set(JuMP.all_constraints(model; include_variable_in_set_constraints = true)) : nothing
@constraint(model, mga_budget, system_cost <= budget_limit)
if scaling
    set_name(mga_budget, "mga_budget")
    MacroEnergy.scale_constraints!(JuMP.ConstraintRef[mga_budget])
    model[:cMGABudget] = filter(
        constraint -> constraint ∉ constraints_before,
        JuMP.all_constraints(model; include_variable_in_set_constraints = true))
else
    model[:cMGABudget] = JuMP.ConstraintRef[mga_budget]
end

@objective(model, sense, model[:vMGA][groups[group_index]])
optimize!(model)
termination_status(model) == JuMP.MOI.OPTIMAL ||
    error("MGA $direction group $group_index failed: $(termination_status(model))")

outpath = joinpath(run_dir, "MGAResults_$direction",
                   "MGA_$(case.settings.MGA.Epsilon)_1_group_$(group_index)")
MacroEnergy.postprocess!(case, model)
MacroEnergy.write_outputs(outpath, case, model)
summary = (
    iteration = 1,
    direction = direction,
    mga_objective = objective_value(model),
    objective_function = value(system_cost),
    least_cost = least_cost,
    budget_limit = budget_limit,
    group_index = group_index,
    group = string(groups[group_index])
)
CSV.write(joinpath(outpath, "mga_summary.csv"), DataFrame([summary]))
