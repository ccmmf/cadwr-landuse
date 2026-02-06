#!/usr/bin/env python

import argparse
from pathlib import Path
from functools import reduce
import logging

import geopandas as gpd

logger = logging.getLogger(__name__)


def _preprocess_dat(dat: gpd.GeoDataFrame, crs, precision, morph_close):
    """Apply preprocessing operations to a GeoDataFrame."""
    if crs is not None:
        # NOTE: For the spatial operations below to have sensical units, pick a
        # CRS based on an equal area projection (e.g., UTM; Albers Equal Area)
        dat = dat.to_crs(crs)
    if precision is not None:
        # `set_precision` rounds the coordinates of the polygons to the nearest
        # `precision`. This effectively "snaps" polygon vertices to a regular grid whose
        # resolution is set by `precision`.
        dat["geometry"] = dat.set_precision(precision)
    if morph_close is not None:
        # Expand a polygon by `morph_close`, then shrink it by `morph_close`.
        # In practice, this smoothes out irregular polygon edges (spikes, etc.).
        dat["geometry"] = dat.buffer(morph_close).buffer(-morph_close)
        dat["geometry"] = dat.make_valid()
    return dat


def process_tile(
    tile_dir: Path,
    output_dir: Path,
    crs: str | None = None,
    precision: float | None = None,
    morph_close: float | None = None,
):
    input_files = sorted(tile_dir.glob("*.parq"))
    output_dir.mkdir(exist_ok=True, parents=True)
    result_file = output_dir / f"{tile_dir.name}.parq"

    if result_file.exists():
        logger.info(f"Skipped tile {tile_dir.name} (exists)")
        return result_file

    dat_dict = {fname.stem: gpd.read_parquet(fname) for fname in input_files}

    processed = [
        _preprocess_dat(dat, crs, precision, morph_close) for dat in dat_dict.values()
    ]

    combined = reduce(lambda d1, d2: gpd.overlay(d1, d2, how="union"), processed)
    combined.to_parquet(result_file)
    return result_file


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description="Process a single tile")
    parser.add_argument("tile_idx", type=int, help="1-based tile index")
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path("_results/tiles-input"),
        help="Input directory containing tile subdirectories",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("_results/tiles-output"),
        help="Output directory for processed tiles",
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
        default=None,
        help="Precision for snapping geometry coordinates",
    )
    parser.add_argument(
        "--morph-close",
        type=float,
        default=None,
        help="Buffer distance for morphological closing operation",
    )
    args = parser.parse_args()

    tidx = args.tile_idx - 1

    all_tiles = sorted(args.input_dir.iterdir())
    if tidx >= len(all_tiles):
        raise IndexError(
            f"Argument {args.tile_idx} (idx {tidx}) >= len(all_tiles)={len(all_tiles)}."
        )
    tile = all_tiles[tidx]
    logger.info(f"Processing tile {tile}")
    process_tile(
        tile,
        args.output_dir,
        crs=args.crs,
        precision=args.precision,
        morph_close=args.morph_close,
    )
