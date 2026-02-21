#!/usr/bin/env bash

#$ -l h_rt=06:00:00
#$ -N liq2-tiles
#$ -o _logs/
#$ -t 1-274

OUTDIR_ROOT=${1:-"_results/v4.1"}

pixi run python scripts/02-process-tile.py $SGE_TASK_ID \
  --outdir-root "$OUTDIR_ROOT" \
  --crs 'EPSG:3310' \
  --precision 10.0 \
  --morph-close 5.0
