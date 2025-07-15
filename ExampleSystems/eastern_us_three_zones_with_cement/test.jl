using MacroEnergy
using Gurobi
using JuMP

case = MacroEnergy.load_case(@__DIR__)
model = MacroEnergy.generate_model(case)

MacroEnergy.set_optimizer(model, Gurobi.Optimizer)
MacroEnergy.set_optimizer_attributes(model, "BarConvTol"=>1e-3,"Crossover" => 1, "Method" => 2, "DualReductions" => 0)
MacroEnergy.optimize!(model)


MacroEnergy.compute_conflict!(model)
list_of_conflicting_constraints = MacroEnergy.ConstraintRef[];
for (F, S) in MacroEnergy.list_of_constraint_types(model)
    for con in MacroEnergy.JuMP.all_constraints(model, F, S)
        if MacroEnergy.JuMP.get_attribute(con, MacroEnergy.MOI.ConstraintConflictStatus()) == MacroEnergy.MOI.IN_CONFLICT
            push!(list_of_conflicting_constraints, con)
        end
    end
end




using MacroEnergy
using Gurobi
using JuMP
using MathOptInterface
const MOI = MathOptInterface

case = MacroEnergy.load_case(@__DIR__)
model = MacroEnergy.generate_model(case)

JuMP.set_optimizer_attribute(model, "ComputeIIS", 1)
JuMP.set_optimizer_attribute(model, "DualReductions", 0)

JuMP.set_optimizer_attribute(model, "IISAbortTime", 60.0)   # Optional: limit time spent on conflict search
JuMP.set_optimizer_attribute(model, "IISMethod", 1)         # Optional: faster conflict method
JuMP.set_optimizer_attribute(model, "Method", 2)
JuMP.set_optimizer_attribute(model, "Crossover", 1)
JuMP.set_optimizer_attribute(model, "BarConvTol", 1e-3)