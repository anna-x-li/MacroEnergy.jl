#!/bin/bash

#SBATCH --job-name=china_31_provinces_8760
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=1000G
#SBATCH --output=slurm-%j.out
#SBATCH --time=5:00:00
#SBATCH --mail-type=all
#SBATCH --mail-user=al3792@princeton.edu

module purge
module load gurobi/13.0.0
module load julia/1.12.1

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Move to MacroEnergy directory so relative paths work reliably
cd /home/al3792/MacroEnergy.jl

# Run the case
julia --project=. "ExampleSystems/china_elec_8760_one_stage/run.jl"