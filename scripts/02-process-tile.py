#!/usr/bin/env python

from pathlib import Path
from functools import reduce
import logging
import sys

import geopandas as gpd

logger = logging.getLogger(__name__)


# Process a single tile
def process_tile(tile_dir: Path):
    # tile_dir = Path("_results/tiles-input/x00_y19")
    input_files = sorted(tile_dir.glob("*.parq"))
    result_dir = Path("_results") / "tiles-output"
    result_dir.mkdir(exist_ok=True, parents=True)
    result_file = result_dir / f"{tile_dir.name}.parq"

    if result_file.exists():
        logger.info(f"Skipped tile {tile_dir.name} (exists)")
        return result_file

    dat_dict = {
        fname.stem: gpd.read_parquet(fname)
        for fname in input_files
    }

    combined = reduce(
        lambda d1, d2: gpd.overlay(d1, d2, how="union"), dat_dict.values()
    )
    combined.to_parquet(result_file)
    return result_file

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    if narg := len(sys.argv) != 2:
        raise ValueError(f"Expected exactly one argument. Got {narg-1}")
    tidx = int(sys.argv[1]) - 1
    # tidx = 1

    all_tiles = sorted(Path("_results/tiles-input").iterdir())
    if tidx > len(all_tiles):
        raise IndexError(
            f"Argument {sys.argv[1]} (idx {tidx}) > len(all_tiles)."
        )
    tile = all_tiles[tidx]
    logger.info(f"Processing tile {tile}")
    process_tile(all_tiles[tidx])

