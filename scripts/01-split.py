#!/usr/bin/env python

import argparse
from pathlib import Path
import logging
from functools import reduce

import geopandas as gpd
import numpy as np
from shapely import box
from tqdm import tqdm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ntiles = 25

parser = argparse.ArgumentParser(description="Split LandIQ data into tiles")
parser.add_argument(
    "--landiq-root-dir",
    type=Path,
    default=Path("/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles"),
    help="Root directory for LandIQ shapefiles",
)
args = parser.parse_args()
landiq_root_dir = args.landiq_root_dir

result_dir = Path("_results") / "tiles-input"
result_dir.mkdir(exist_ok=True, parents=True)

f2018 = landiq_root_dir / "i15_Crop_Mapping_2018_SHP" / "i15_Crop_Mapping_2018.shp"
f2019 = landiq_root_dir / "i15_Crop_Mapping_2019_SHP" / "i15_Crop_Mapping_2019.shp"
f2020 = landiq_root_dir / "i15_Crop_Mapping_2020_SHP" / "i15_Crop_Mapping_2020.shp"
f2021 = landiq_root_dir / "i15_Crop_Mapping_2021_SHP" / "i15_Crop_Mapping_2021.shp"
f2022 = (
    landiq_root_dir
    / "i15_Crop_Mapping_2022_Provisional_SHP"
    / "i15_Crop_Mapping_2022_Provisional.shp"
)
f2023 = (
    landiq_root_dir
    / "i15_Crop_Mapping_2023_Provisional_SHP"
    / "i15_Crop_Mapping_2023_Provisional.shp"
)

files = {
    "2018": f2018,
    "2019": f2019,
    "2020": f2020,
    "2021": f2021,
    "2022": f2022,
    "2023": f2023,
}


def read_shp(fname: Path, suffix: str):
    # For the combined index file, subset to just the uniqueID and geometry.
    # We'll merge everything later.
    return (
        gpd.read_file(fname, use_arrow=True, columns=["UniqueID", "geometry"])
        .explode(index_parts=False)
        .reset_index(drop=True)
        .rename(columns={"UniqueID": f"UniqueID_{suffix}"})
    )


logger.info("Reading all data")
dat_all = {year: read_shp(fname, year) for year, fname in tqdm(files.items())}

# Use the 2023 CRS for everything
logger.info("Harmonizing CRS")
common_crs = dat_all["2023"].crs
dat_all = {year: data.to_crs(common_crs) for year, data in tqdm(dat_all.items())}

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
) -> Path | None:
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

# Loop over folders and delete empty ones
# for tdir in (Path("_results") / "tiles-input").iterdir():
#     if not any(tdir.iterdir()):
#         tdir.rmdir()
