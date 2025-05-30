using MacroEnergy
using Gurobi

(system, model) = run_case(@__DIR__; optimizer=Gurobi.Optimizer);


using Pkg
Pkg.activate(dirname(dirname(@__DIR__)))
using MacroEnergy
using Gurobi
using DataFrames

case_path = @__DIR__
println("###### ###### ######")
println("Running case at $(case_path)")

system = MacroEnergy.load_system(case_path)

model = MacroEnergy.generate_model(system)

MacroEnergy.set_optimizer(model, Gurobi.Optimizer);

MacroEnergy.set_optimizer_attributes(model, "BarConvTol"=>1e-3,"Crossover" => 0, "Method" => 2)

MacroEnergy.optimize!(model)

for i in 1:length(system.assets)
    asset = system.assets[i]
    println(string(i) * string(asset.id))
end