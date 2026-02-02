#!/usr/bin/env bash

#$ -l h_rt=03:00:00
#$ -N liq-tiles
#$ -o _logs/
#$ -t 1-274

pixi run python scripts/02-process-tile.py $SGE_TASK_ID
