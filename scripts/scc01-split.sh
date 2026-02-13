#!/usr/bin/env bash

#$ -l h_rt=03:00:00
#$ -N liq1-split
#$ -o _logs/

OUTDIR=${1:-"_results"}

pixi run python scripts/01-split.py \
  --result-dir "$OUTDIR/tiles-in"
