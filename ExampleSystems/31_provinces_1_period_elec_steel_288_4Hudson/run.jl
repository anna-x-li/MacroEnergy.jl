using Pkg
Pkg.activate(@__DIR__)

import Pkg; Pkg.add("Gurobi")
import Pkg; Pkg.add("MacroEnergy")
import Pkg; Pkg.add("Infiltrator")

using Infiltrator
using MacroEnergy
using Gurobi

(system, model) = run_case(@__DIR__; 
                    optimizer=Gurobi.Optimizer,
                    optimizer_attributes=("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-3));

case = MacroEnergy.load_case(@__DIR__)


MacroEnergy.compute_conflict!(model)
list_of_conflicting_constraints = MacroEnergy.ConstraintRef[];
for (F, S) in MacroEnergy.list_of_constraint_types(model)
    for con in MacroEnergy.JuMP.all_constraints(model, F, S)
        if MacroEnergy.JuMP.get_attribute(con, MacroEnergy.MOI.ConstraintConflictStatus()) == MacroEnergy.MOI.IN_CONFLICT
            push!(list_of_conflicting_constraints, con)
        end
    end
end
display(list_of_conflicting_constraints)