#!/usr/bin/env bash

#$ -l h_rt=03:00:00
#$ -N liq3-final
#$ -o _logs/

OUTDIR=${1:-"_results"}

pixi run python scripts/03-combine-finalize.py \
  --tile-dir "$OUTDIR/tiles-out" \
  --outdir "$OUTDIR/final"
