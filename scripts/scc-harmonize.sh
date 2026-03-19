#!/usr/bin/env bash

OUTDIR_ROOT=${1:-"_results/v4.1"}

qsub -N liq1 scripts/scc01-split.sh $OUTDIR_ROOT
qsub -N liq2 -hold_jid liq1 scripts/scc02-process-tiles.sh $OUTDIR_ROOT
qsub -N liq3 -hold_jid liq2 scripts/scc03-combine-finalize.sh $OUTDIR_ROOT
