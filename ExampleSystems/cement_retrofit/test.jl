using MacroEnergy
using Gurobi
using JuMP

case = MacroEnergy.load_case(@__DIR__)
model = MacroEnergy.generate_model(case)

for cref in values(model[:cRetrofitCapacity])
    delete(model, cref)
end

MacroEnergy.set_optimizer(model, Gurobi.Optimizer)
MacroEnergy.set_optimizer_attributes(model, "BarConvTol"=>1e-3,"Crossover" => 0, "Method" => 2, "DualReductions" => 0)
MacroEnergy.optimize!(model)

MacroEnergy.write_outputs(joinpath(@__DIR__, "results", "debugging_2"), case, model)