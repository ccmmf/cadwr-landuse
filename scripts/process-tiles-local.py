#!/usr/bin/env python
"""
Process all tiles in parallel using Dask.

This script loads the process_tile function from 02-process-tile.py and
uses Dask's delayed computation to process all tiles in parallel on the
local machine.

Usage:
    pixi run python scripts/process-tiles-local.py [OPTIONS]

Examples:
    # Process with default settings (15 workers)
    pixi run python scripts/process-tiles-local.py

    # Process with 8 workers
    pixi run python scripts/process-tiles-local.py --ntasks 8

    # Process with custom output directory and CRS
    pixi run python scripts/process-tiles-local.py --outdir-root _results/v5 --crs EPSG:4326

    # Disable preprocessing
    pixi run python scripts/process-tiles-local.py --precision 0 --morph-close 0

Arguments:
    --ntasks NTASKS       Number of parallel workers (default: 15)
    --outdir-root PATH    Root directory for all outputs (default: _results/v4.1)
    --crs EPSG           CRS to reproject data to before processing
    --precision FLOAT    Precision for snapping geometry coordinates (default: 10.0)
    --morph-close FLOAT  Buffer distance for morphological closing (default: 5.0)

How it works:
    1. Discovers all tile directories in OUTDIR_ROOT/01-tiles-by-year/
    2. Creates a Dask delayed object for each tile calling process_tile()
    3. Computes all delayed tasks using the synchronous scheduler
    4. Each tile is processed independently in parallel
    5. Output files are written to OUTDIR_ROOT/02-tiles-combined/
    6. Existing output files are skipped (idempotent)

Environment:
    This script uses pure Python with Dask. No environment variables are required;
    all configuration is done via command-line arguments.
"""

import argparse
import importlib.util
import logging
import time
from pathlib import Path

import dask
from dask import delayed

# Hack to import the (improperly named) process-tile script.
SCRIPT_DIR = Path(__file__).parent
PROCESS_TILE_PATH = SCRIPT_DIR / "02-process-tile.py"
spec = importlib.util.spec_from_file_location(
    "scripts_02_process_tile", PROCESS_TILE_PATH
)
if spec is None or spec.loader is None:
    raise ImportError(f"Could not load {PROCESS_TILE_PATH}")
process_tile_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(process_tile_module)
process_tile = process_tile_module.process_tile

logger = logging.getLogger(__name__)


def main():
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(
        description="Process all tiles in parallel using Dask"
    )
    parser.add_argument(
        "--ntasks",
        type=int,
        default=15,
        help="Number of parallel workers (default: 15)",
    )
    parser.add_argument(
        "--outdir-root",
        type=Path,
        default=Path("_results/v4.1"),
        help="Root directory for all outputs (default: _results/v4.1)",
    )
    parser.add_argument(
        "--tile-output-dir",
        type=Path,
        default=None,
        help="Override output directory for combined tiles (default: {outdir-root}/02-tiles-combined)",
    )
    parser.add_argument(
        "--crs",
        type=str,
        default=None,
        help="CRS to reproject data to before processing",
    )
    parser.add_argument(
        "--precision",
        type=float,
        default=10.0,
        help="Precision for snapping geometry coordinates (default: 10.0)",
    )
    parser.add_argument(
        "--morph-close",
        type=float,
        default=None,
        help="Buffer distance for morphological closing operation",
    )
    args = parser.parse_args()

    input_dir = args.outdir_root / "01-tiles-by-year"
    output_dir = (
        args.tile_output_dir
        if args.tile_output_dir is not None
        else args.outdir_root / "02-tiles-combined"
    )

    tiles = sorted(input_dir.iterdir())
    num_tiles = len(tiles)
    logger.info(f"Found {num_tiles} tiles to process")

    output_dir.mkdir(exist_ok=True, parents=True)

    start_time = time.time()

    delayed_results = [
        delayed(process_tile)(
            tile,
            output_dir,
            crs=args.crs,
            precision=args.precision,
            morph_close=args.morph_close,
        )
        for tile in tiles
    ]

    dask.compute(*delayed_results, scheduler="synchronous")

    end_time = time.time()
    duration = end_time - start_time
    logger.info(f"Done processing {num_tiles} tiles in {duration:.1f}s")


if __name__ == "__main__":
    main()
