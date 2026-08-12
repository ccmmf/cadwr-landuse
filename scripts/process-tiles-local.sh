#!/bin/bash
#SBATCH --job-name=landiq-process-tiles
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=landiq-process-tiles-%j.out
#SBATCH --error=landiq-process-tiles-%j.err
#
# Slurm wrapper for scripts/process-tiles-local.py (Dask local workers).
# Companion to the SCC/SGE array path in scripts/scc02-process-tiles.sh.
#
# Before sbatch, activate an environment with this repo's Python deps
# (pixi or conda) so `python` is on PATH, and set the work directory:
#
#   export OUTDIR_ROOT=/path/to/work     # e.g. _results/v4.1
#   sbatch scripts/process-tiles-local.sh
#
# Knobs (submitting shell; Slurm inherits them):
#   OUTDIR_ROOT              -- required (or CADWR_WORK_DIR as an alias)
#   NTASKS                   -- optional Dask workers (default: SLURM_CPUS_PER_TASK or 8)
#   LANDIQ_TILE_CRS          -- optional (default: EPSG:3310)
#   LANDIQ_TILE_PRECISION    -- optional (default: 10.0)
#
# Repo root: prefer SLURM_SUBMIT_DIR (cwd when you ran sbatch; use after
# cd to this clone), else directory containing this scripts/ folder.
# Account/partition omitted so Slurm uses site defaults; add -A / -p if needed.
# Example Slurm docs: https://docs.urcf.drexel.edu/learning/slurm/writing-job-scripts/

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-}"
if [[ -z "$REPO_ROOT" || ! -f "$REPO_ROOT/scripts/process-tiles-local.py" ]]; then
  # Fallback when not under Slurm, or submit cwd was not the repo root
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ -z "${OUTDIR_ROOT:-}" && -z "${CADWR_WORK_DIR:-}" ]]; then
  echo "ERROR: export OUTDIR_ROOT=/path/to/work before sbatch" >&2
  echo "       (CADWR_WORK_DIR is accepted as an alias if already set)" >&2
  exit 1
fi
OUTDIR_ROOT="${OUTDIR_ROOT:-$CADWR_WORK_DIR}"

NTASKS="${NTASKS:-${SLURM_CPUS_PER_TASK:-8}}"
CRS="${LANDIQ_TILE_CRS:-EPSG:3310}"
PRECISION="${LANDIQ_TILE_PRECISION:-10.0}"

cd "$REPO_ROOT"

echo "process-tiles-local: repo=$REPO_ROOT outdir=$OUTDIR_ROOT ntasks=$NTASKS job=${SLURM_JOB_ID:-local}"
python scripts/process-tiles-local.py \
  --outdir-root "$OUTDIR_ROOT" \
  --ntasks "$NTASKS" \
  --crs "$CRS" \
  --precision "$PRECISION"
