#!/usr/bin/env bash
# Submit the full LandIQ geometry harmonization chain on SGE.
#
# Optional env:
#   LANDIQ_ROOT_DIR  directory of i15_Crop_Mapping_*_SHP folders
#                    (years are auto-discovered; drop a new year and re-run)
#
# Usage:
#   export LANDIQ_ROOT_DIR=$CCMMF_ROOT/data_raw/cadwr_land_use/landiq_shapefiles
#   bash scripts/scc-harmonize.sh _results/v4.1

OUTDIR_ROOT=${1:-"_results/v4.1"}
LANDIQ_ROOT_DIR=${LANDIQ_ROOT_DIR:-"/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles"}

qsub -N liq1 -v "LANDIQ_ROOT_DIR=${LANDIQ_ROOT_DIR}" \
  scripts/scc01-split.sh "$OUTDIR_ROOT"
qsub -N liq2 -hold_jid liq1 \
  scripts/scc02-process-tiles.sh "$OUTDIR_ROOT"
qsub -N liq3 -hold_jid liq2 -v "LANDIQ_ROOT_DIR=${LANDIQ_ROOT_DIR}" \
  scripts/scc03-combine-finalize.sh "$OUTDIR_ROOT"
