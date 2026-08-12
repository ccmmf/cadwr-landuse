#!/usr/bin/env bash

#$ -l h_rt=03:00:00
#$ -N liq1-split
#$ -o _logs/

OUTDIR_ROOT=${1:-"_results/v4.1"}
LANDIQ_ROOT_DIR=${LANDIQ_ROOT_DIR:-"/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles"}

pixi run python scripts/01-split.py \
  --outdir-root "$OUTDIR_ROOT" \
  --landiq-root-dir "$LANDIQ_ROOT_DIR"
