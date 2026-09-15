import Pkg
Pkg.activate("/Users/al3792/Documents_Local/MacroEnergy.jl")

using Revise
using MacroEnergy
using Gurobi

case = MacroEnergy.load_case(@__DIR__)

(system, model) = run_case(@__DIR__; 
                    optimizer=Gurobi.Optimizer,
                    # MGA pricing fixes investments exactly; use accurate barrier
                    # solutions so fixed builds respect their capacity limits.
                    optimizer_attributes=("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-6));
