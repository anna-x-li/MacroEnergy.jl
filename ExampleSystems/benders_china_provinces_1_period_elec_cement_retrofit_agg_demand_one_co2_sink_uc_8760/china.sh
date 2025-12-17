#!/bin/bash

#SBATCH --job-name=china_31_provinces_cement_elec_8760
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=1000G
#SBATCH --output=slurm-%j.out
#SBATCH --time=72:00:00
#SBATCH --constraint=amd
#SBATCH --mail-type=all
#SBATCH --mail-user=al3792@princeton.edu

module purge
module load gurobi/13.0.0
module load julia/1.12.1

# Move to MacroEnergy directory
cd /home/al3792/MacroEnergy.jl

# Run the case
julia --project=. "ExampleSystems/china_provinces_1_period_elec_cement_retrofit_agg_demand_one_co2_sink_uc_8760/run.jl"