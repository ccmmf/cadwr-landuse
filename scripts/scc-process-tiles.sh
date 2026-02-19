#!/usr/bin/env bash

#$ -l h_rt=03:00:00
#$ -N liq-tiles
#$ -o _logs/
#$ -t 1-274

pixi run python scripts/02-process-tile.py $SGE_TASK_ID \
  --output-dir _results/tiles-output-sp \
  --crs 'EPSG:3310' \
  --precision 1.0 \
  --morph-close 0.5
