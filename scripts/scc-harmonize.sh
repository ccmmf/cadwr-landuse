#!/usr/bin/env bash

#$ -l h_rt=08:00:00
#$ -pe omp 16

pixi run python scripts/01-harmonize-tiles.py || exit 1
pixi run python scripts/02-combine-finalize.py
