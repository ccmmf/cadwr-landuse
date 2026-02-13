#!/usr/bin/env bash

OUTDIR="_results/w2016"

qsub -N liq1 scripts/scc01-split.sh $OUTDIR
qsub -N liq2 -hold_jid liq1 scripts/scc02-process-tiles.sh $OUTDIR
qsub -N liq3 -hold_jid liq2 scripts/scc03-combine-finalize.sh $OUTDIR
