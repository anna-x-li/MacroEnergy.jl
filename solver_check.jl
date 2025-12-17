import Pkg; Pkg.add("JuMP")
import Pkg; Pkg.add("Gurobi")

using JuMP
using Gurobi

function solver_preflight_check()
    println("=== Solver preflight check ===")

    try
        # Force solver initialization
        optimizer = optimizer_with_attributes(
            Gurobi.Optimizer(),
            "Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-3
        )

        # Create a tiny model
        model = Model(optimizer)
        @variable(model, x >= 0)
        @objective(model, Min, x)

        optimize!(model)

        term = termination_status(model)
        println("Solver termination status: ", term)

        if term != MOI.OPTIMAL
            error("Solver ran but did not return OPTIMAL")
        end

        println("Solver preflight check PASSED")

    catch err
        println("Solver preflight check FAILED")
        rethrow(err)
    end
end

solver_preflight_check()