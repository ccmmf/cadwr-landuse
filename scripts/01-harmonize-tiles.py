#!/usr/bin/env python

from pathlib import Path
from functools import reduce
import logging

import geopandas as gpd
import dask
from dask import delayed
from dask.diagnostics import ProgressBar
import numpy as np
from shapely import box

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

landiq_root_dir = Path("/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles")
# landiq_root_dir = Path("~/data").expanduser()

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
dat_all = {year: read_shp(fname, year) for year, fname in files.items()}

# Use the 2023 CRS for everything
common_crs = dat_all["2023"].crs
dat_all = {year: data.to_crs(common_crs) for year, data in dat_all.items()}

# Get the total bounding box
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
minx, miny, maxx, maxy = combined_bounds
ntiles = 10
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

result_dir = Path("_results") / "tiles"
result_dir.mkdir(exist_ok=True, parents=True)


def clip_to_tile(dat: gpd.GeoDataFrame, tile: dict) -> gpd.GeoDataFrame | None:
    tgeom = tile["geometry"]
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
    return dsub


# Process a single tile (wrapped for parallelization)
@delayed
def process_tile(tile, dat_all, result_dir):
    tid = tile['tile_id']
    result_file = result_dir / f"{tid}.parq"

    if result_file.exists():
        return f"Skipped tile {tid} (exists)"

    dat_dict = {
        year: dtile
        for year, dat in dat_all.items()
        if (dtile := clip_to_tile(dat, tile)) is not None
    }

    if not dat_dict:
        return f"Tile {tid} is empty"

    combined = reduce(
        lambda d1, d2: gpd.overlay(d1, d2, how="union"), dat_dict.values()
    )
    combined.to_parquet(result_file)

    return f"Processed tile {tid}"


logger.info("Processing overlays by tile")

# Create delayed tasks for each tile
tasks = [process_tile(tile, dat_all, result_dir) for tile in tiles]

# Execute in parallel with progress bar
with ProgressBar():
    results = dask.compute(*tasks)
