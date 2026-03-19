#!/usr/bin/env python

import argparse
from pathlib import Path
import logging

import geopandas as gpd

# Fraction of area difference allowed before warning
CHECK_AREA_FRACTION = 0.03

logger = logging.getLogger(__name__)


def _preprocess_dat(dat: gpd.GeoDataFrame, precision, morph_close):
    """Apply preprocessing operations to a GeoDataFrame."""
    if precision is None and morph_close is None:
        return dat
    if morph_close is not None:
        dat["geometry"] = dat.buffer(morph_close).buffer(-morph_close)
    dat["geometry"] = dat.make_valid()
    if precision is not None:
        dat["geometry"] = dat.set_precision(precision)
    dat["geometry"] = dat.buffer(0)
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

    if crs is not None:
        dat_dict = {year: df.to_crs(crs) for year, df in dat_dict.items()}

    input_areas = {year: df.geometry.area.sum() for year, df in dat_dict.items()}

    # Preprocess and check for valid geometries
    processed = []
    for year, dat in dat_dict.items():
        processed_year = _preprocess_dat(dat, precision, morph_close)
        invalid = (
            ~processed_year.is_valid
            | processed_year.geometry.isna()
            | processed_year.geometry.is_empty
        )
        if invalid.any():
            logger.warning(
                f"Tile {tile_dir.name}: Removing {invalid.sum()} invalid geometries in year {year}"
            )
            processed_year = processed_year[~invalid]
        processed.append(processed_year)

    # Apply overlay iteratively to the data frames.
    def reduce_overlay(dfs):
        dfs = [df for df in dfs if len(df) > 0]
        if not dfs:
            raise ValueError(
                f"Tile {tile_dir.name}: No valid geometries after preprocessing"
            )
        if len(dfs) == 1:
            return dfs[0]
        result = dfs[0]
        for df in dfs[1:]:
            result = gpd.overlay(result, df, how="union")
        return result

    combined = reduce_overlay(processed)

    # Check output area is within CHECK_AREA_FRACTION of each year's input area
    total_output_area = combined.geometry.area.sum()
    for year, input_area in input_areas.items():
        area_diff_frac = abs(total_output_area - input_area) / input_area
        if area_diff_frac > CHECK_AREA_FRACTION:
            logger.warning(
                f"Tile {tile_dir.name}: Year {year}: Output area differs by {area_diff_frac:.2%} "
                f"(input: {input_area:.2f}, output: {total_output_area:.2f})"
            )
        else:
            logger.info(
                f"Tile {tile_dir.name}: Year {year}: Area check passed ({area_diff_frac:.2%} diff)"
            )

    combined.to_parquet(result_file)
    return result_file


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description="Process a single tile")
    parser.add_argument("tile_idx", type=int, help="1-based tile index")
    parser.add_argument(
        "--outdir-root",
        type=Path,
        default=Path("_results/v4.1"),
        help="Root directory for all outputs",
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

    input_dir = args.outdir_root / "01-tiles-by-year"
    output_dir = (
        args.tile_output_dir
        if args.tile_output_dir is not None
        else args.outdir_root / "02-tiles-combined"
    )

    tidx = args.tile_idx - 1

    all_tiles = sorted(input_dir.iterdir())
    if tidx >= len(all_tiles):
        raise IndexError(
            f"Argument {args.tile_idx} (idx {tidx}) >= len(all_tiles)={len(all_tiles)}."
        )
    tile = all_tiles[tidx]
    logger.info(f"Processing tile {tile}")
    process_tile(
        tile,
        output_dir,
        crs=args.crs,
        precision=args.precision,
        morph_close=args.morph_close,
    )
