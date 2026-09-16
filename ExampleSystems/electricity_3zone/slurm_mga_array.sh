#!/usr/bin/env bash
#SBATCH --job-name=electricity-3zone-mga
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=electricity-3zone-mga-%A_%a.log

set -euo pipefail

julia --project="$PROJECT_DIR" \
    "$CASE_DIR/slurm_mga_job.jl" "$RUN_DIR" "$SLURM_ARRAY_TASK_ID"
