#!/usr/bin/env bash

pixi run python scripts/01-harmonize-counties.py
pixi run python scripts/02-combine-finalize.py
