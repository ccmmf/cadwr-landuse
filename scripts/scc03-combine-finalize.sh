#!/usr/bin/env bash

#$ -l h_rt=03:00:00
#$ -N liq3-final
#$ -o _logs/

OUTDIR_ROOT=${1:-"_results/v4.1"}

pixi run python scripts/03a-combine-parcels.py \
  --outdir-root "$OUTDIR_ROOT"

pixi run python scripts/03b-finalize-crops.py \
  --outdir-root "$OUTDIR_ROOT"
