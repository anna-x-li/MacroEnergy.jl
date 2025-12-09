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
module load gurobi/12.0.0
module load julia/1.12.1

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Move to MacroEnergy directory so relative paths work reliably
cd /home/al3792/MacroEnergy.jl

# Always re-activate, instantiate, and link the package
# julia -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'
# julia -e 'using Pkg; Pkg.develop(path=".")'
# julia -e 'using Pkg; Pkg.add("Gurobi")'

# Run the case
julia --project=. "ExampleSystems/Ver12_China_elec_multistage_288_7_v1107CO2cap-CO2cap1_CCS - Copy/run.jl"