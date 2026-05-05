using Pkg
Pkg.activate("/Users/al3792/Documents_Local/MacroEnergy.jl")

using Infiltrator
using MacroEnergy
using Gurobi
using JuMP

output_base = joinpath(@__DIR__, "results")

# ── Case 1: no emissions cap ──────────────────────────────────────────────────
case = MacroEnergy.load_case(@__DIR__)
MacroEnergy.find_node(case.systems[1], :co2_sink).rhs_policy[MacroEnergy.CO2CapConstraint] = 1e15

optim = MacroEnergy.create_optimizer(Gurobi.Optimizer, nothing, ("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-3))
(case, model) = MacroEnergy.solve_case(case, optim)
MacroEnergy.postprocess!(case, model)
MacroEnergy.write_outputs(joinpath(output_base, "noemissionscap"), case, model)

# Read actual CO2 emissions from the unconstrained solution to use as baseline
co2_node = MacroEnergy.find_node(case.systems[1], :co2_sink)
baseline_co2 = sum(
    MacroEnergy.subperiod_weight(co2_node, MacroEnergy.current_subperiod(co2_node, t)) *
    JuMP.value(MacroEnergy.get_balance(co2_node, :emissions, t))
    for t in MacroEnergy.time_interval(co2_node)
)
@info "Baseline CO2 emissions (no cap): $baseline_co2"

# ── Cases 2 & 3: reductions from baseline ────────────────────────────────────

cases = [("30pct", 0.70), ("60pct", 0.40), ("90pct", 0.10)]

# Define the base directory where you want everything to live

for (case_name, fraction) in cases
    case = MacroEnergy.load_case(@__DIR__)

    node = MacroEnergy.find_node(case.systems[1], :co2_sink)
    node.rhs_policy[MacroEnergy.CO2CapConstraint] = baseline_co2 * fraction

    (case, model) = MacroEnergy.solve_case(case, optim)
    MacroEnergy.postprocess!(case, model)

    target_dir = joinpath(output_base, case_name)
    mkpath(target_dir)

    MacroEnergy.write_outputs(target_dir, case, model)
end
