using Pkg
Pkg.activate("/Users/al3792/Documents_Local/MacroEnergy.jl")

using Infiltrator
using MacroEnergy
using Gurobi
using JuMP

# ── Case 1: no emissions cap ──────────────────────────────────────────────────
case = MacroEnergy.load_case(@__DIR__)
MacroEnergy.find_node(case.systems[1], :co2_sink).rhs_policy[MacroEnergy.CO2CapConstraint] = 1e15

optim = MacroEnergy.create_optimizer(Gurobi.Optimizer, nothing, ("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-3))
(case, model) = MacroEnergy.solve_case(case, optim)
MacroEnergy.postprocess!(case, model)
MacroEnergy.write_outputs(joinpath(@__DIR__, "results/noemissionscap"), case, model)

# Read actual CO2 emissions from the unconstrained solution to use as baseline
co2_node = MacroEnergy.find_node(case.systems[1], :co2_sink)
baseline_co2 = sum(
    MacroEnergy.subperiod_weight(co2_node, MacroEnergy.current_subperiod(co2_node, t)) *
    JuMP.value(MacroEnergy.get_balance(co2_node, :emissions, t))
    for t in MacroEnergy.time_interval(co2_node)
)
@info "Baseline CO2 emissions (no cap): $baseline_co2"

# ── Cases 2 & 3: reductions from baseline ────────────────────────────────────

# [("results/30pct", 0.70), ("results/60pct", 0.40), ("results/90pct", 0.10)]

for (case_name, fraction) in [("results/30pct", 0.70)]
    case = MacroEnergy.load_case(@__DIR__)
    MacroEnergy.find_node(case.systems[1], :co2_sink).rhs_policy[MacroEnergy.CO2CapConstraint] = baseline_co2 * fraction

    (case, model) = MacroEnergy.solve_case(case, optim)
    MacroEnergy.postprocess!(case, model)
    MacroEnergy.write_outputs(joinpath(@__DIR__, "results_$case_name"), case, model)
end