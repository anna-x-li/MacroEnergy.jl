#!/bin/bash
#SBATCH --job-name=solver_check
#SBATCH --time=00:01:00
#SBATCH --mem=1G
#SBATCH --cpus-per-task=1
#SBATCH --output=solver_check.out
#SBATCH --error=solver_check.err

module load gurobi/13.0.0
module load julia/1.12.1

julia --startup-file=no solver_check.jl