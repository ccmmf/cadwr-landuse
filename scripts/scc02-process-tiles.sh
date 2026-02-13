#!/usr/bin/env bash

#$ -l h_rt=06:00:00
#$ -N liq2-tiles
#$ -o _logs/
#$ -t 1-274

OUTDIR=${1:-"_results"}

pixi run python scripts/02-process-tile.py $SGE_TASK_ID \
  --input-dir "$OUTDIR/tiles-in" \
  --output-dir "$OUTDIR/tiles-out" \
  --crs 'EPSG:26910' \
  --precision 1.0 \
  --morph-close 0.5
