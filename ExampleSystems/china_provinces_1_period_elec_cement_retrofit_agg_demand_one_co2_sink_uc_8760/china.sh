#!/bin/bash

#SBATCH --job-name=china_31_provinces_8760
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=1000G
#SBATCH --output=slurm-%j.out
#SBATCH --time=72:00:00
#SBATCH --mail-type=all
#SBATCH --mail-user=al3792@princeton.edu

module purge
module load gurobi/13.0.0
module load julia/1.12.1

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Move to MacroEnergy directory so relative paths work
cd /home/al3792/MacroEnergy.jl

# Run the case
julia --project=. "ExampleSystems/china_provinces_1_period_elec_cement_retrofit_agg_demand_one_co2_sink_uc_8760/run.jl"