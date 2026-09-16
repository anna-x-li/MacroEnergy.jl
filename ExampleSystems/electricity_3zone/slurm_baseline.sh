#!/usr/bin/env bash
#SBATCH --job-name=electricity-3zone-baseline
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=electricity-3zone-baseline-%j.log

set -euo pipefail

case_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$case_dir/../.." && pwd)"
run_dir="$case_dir/slurm_${SLURM_JOB_ID}"
mkdir -p "$run_dir"

julia --project="$project_dir" "$case_dir/slurm_baseline.jl" "$run_dir"

job_count="$(cat "$run_dir/mga_job_count.txt")"
[[ "$job_count" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid MGA job count: $job_count" >&2; exit 1; }

# Limit simultaneous MGA solves to two; change this for your cluster/license.
cd "$case_dir"
sbatch --array="1-${job_count}%2" \
    --export="ALL,RUN_DIR=$run_dir,CASE_DIR=$case_dir,PROJECT_DIR=$project_dir" \
    "$case_dir/slurm_mga_array.sh"
