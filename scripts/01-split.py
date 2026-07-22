#!/usr/bin/env python

import argparse
import logging
import sys
from functools import reduce
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
from shapely import box
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _lib.landiq_years import discover_landiq_shapefiles

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ntiles = 25

parser = argparse.ArgumentParser(description="Split LandIQ data into tiles")
parser.add_argument(
    "--landiq-root-dir",
    type=Path,
    default=Path("/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles"),
    help="Root directory for LandIQ shapefiles (i15_Crop_Mapping_*_SHP folders)",
)
parser.add_argument(
    "--outdir-root",
    type=Path,
    default=Path("_results/v4.1"),
    help="Root directory for all outputs",
)
parser.add_argument(
    "--min-year",
    type=int,
    default=2016,
    help="Ignore shapefile years before this (default: 2016)",
)
parser.add_argument(
    "--max-year",
    type=int,
    default=None,
    help="Optional upper year bound (inclusive)",
)
args = parser.parse_args()
landiq_root_dir = args.landiq_root_dir

result_dir = args.outdir_root / "01-tiles-by-year"
result_dir.mkdir(exist_ok=True, parents=True)

files = discover_landiq_shapefiles(
    landiq_root_dir,
    min_year=args.min_year,
    max_year=args.max_year,
)


def read_shp(fname: Path, suffix: str):
    # For the combined index file, subset to just the uniqueID and geometry.
    # We'll merge everything later.
    idcol = f"UniqueID_{suffix}"
    dat = (
        gpd.read_file(fname, use_arrow=True, columns=["UniqueID", "geometry"])
        .explode(index_parts=False)
        .reset_index(drop=True)
        .rename(columns={"UniqueID": idcol})
    )
    # Year 2016 and earlier don't include a UniqueID column. So we create one
    # from the default pandas index (row number).
    if idcol not in dat.columns:
        dat = dat.reset_index(names=idcol)
    # Keep IDs as strings so merges match DWR character UniqueIDs.
    dat[idcol] = dat[idcol].astype(str)
    return dat


logger.info("Reading all data")
dat_all = {year: read_shp(fname, year) for year, fname in tqdm(files.items())}

# Use the newest year's CRS for everything
newest = max(dat_all.keys(), key=int)
logger.info("Harmonizing CRS to year %s", newest)
common_crs = dat_all[newest].crs
dat_all = {year: data.to_crs(common_crs) for year, data in tqdm(dat_all.items())}

# Get the UniqueIDs for each year. We will test this later.
uids = {year: data[f"UniqueID_{year}"].unique() for year, data in dat_all.items()}

# Get the total bounding box
logger.info("Determining overall bounding box")
combined_bounds = reduce(
    lambda b1, b2: (
        min(b1[0], b2[0]),
        min(b1[1], b2[1]),
        max(b1[2], b2[2]),
        max(b1[3], b2[3]),
    ),
    [dat.total_bounds for dat in dat_all.values()],
)

# Create tiles
logger.info("Creating tiles")
minx, miny, maxx, maxy = combined_bounds
x_edges = np.linspace(minx, maxx, ntiles + 1)
y_edges = np.linspace(miny, maxy, ntiles + 1)
tiles = []
for i in range(ntiles):
    for j in range(ntiles):
        tile_geom = box(x_edges[i], y_edges[j], x_edges[i + 1], y_edges[j + 1])
        tiles.append(
            {
                "tile_id": f"x{i:02d}_y{j:02d}",
                "geometry": tile_geom,
            }
        )


def clip_to_tile(
    dat: gpd.GeoDataFrame, year: str, tile: dict, result_dir: Path = result_dir
):
    tgeom = tile["geometry"]
    tid = tile["tile_id"]
    outdir = result_dir / f"{tid}"
    outfile = outdir / f"{year}.parq"
    minx, miny, maxx, maxy = tgeom.bounds
    dsub = dat.cx[minx:maxx, miny:maxy]
    if dsub.empty:
        return None
    dsub["geometry"] = dsub.geometry.intersection(tgeom)
    dsub = dsub[~dsub.geometry.is_empty]
    if dsub.empty:
        return None
    outdir.mkdir(exist_ok=True, parents=True)
    dsub.to_parquet(outfile)
    return outfile


logger.info("Splitting data into tiles")
for tile in tqdm(tiles, desc="Tiles"):
    for year, dat in tqdm(dat_all.items(), desc="Years", leave=False):
        clip_to_tile(dat, year, tile, result_dir=result_dir)

logger.info("Validating that all unique IDs are in the tiles")

tile_uids = {}
for tile in tqdm(tiles, desc="Reading tiles"):
    tid = tile["tile_id"]
    for year in dat_all.keys():
        tile_file = result_dir / tid / f"{year}.parq"
        if tile_file.exists():
            uid_col = f"UniqueID_{year}"
            tile_dat = pd.read_parquet(tile_file, columns=[uid_col])
            tile_uids.setdefault(year, set()).update(tile_dat[uid_col].tolist())

for year in dat_all:
    expected = set(uids[year])
    actual = tile_uids.get(year, set())
    if actual == expected:
        logger.info(f"Year {year}: OK All {len(expected)} unique IDs accounted for")
    else:
        missing = expected - actual
        extra = actual - expected
        logger.error(
            f"Year {year}: Mismatch! Missing: {len(missing)}, Extra: {len(extra)}"
        )
