#!/usr/bin/env python
from pathlib import Path

import geopandas as gpd
import pandas as pd
from tqdm import tqdm
import logging
import argparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser(description="Combine processed tiles into parcels")
parser.add_argument("--outdir-root", type=Path, default=Path("_results/v4.1"))
args = parser.parse_args()

tile_dir = args.outdir_root / "02-tiles-combined"
tile_files = sorted(tile_dir.glob("*.parq"))
outdir = args.outdir_root / "03-final"
outdir.mkdir(exist_ok=True, parents=True)

SQ_METERS_PER_ACRE = 4046.8564224

logger.info("STEP 1: Create merged parcels file")

logger.info("Reading and concatenating processed tiles")
combined_raw = pd.concat(
    [gpd.read_parquet(fname) for fname in tqdm(tile_files)], ignore_index=True
)

logger.info("Dissolving polygons with identical attributes")
ucols = [col for col in combined_raw.columns if col.startswith("UniqueID_")]
combined = combined_raw.dissolve(by=ucols, as_index=False, aggfunc="first")
del combined_raw

logger.info("Defining unique parcel ID")
combined = combined.reset_index(drop=True)
combined.insert(0, "parcel_id", range(len(combined)))
combined["UniqueID_2016"] = combined["UniqueID_2016"].astype(str)
combined["ACRES"] = combined.geometry.area / SQ_METERS_PER_ACRE

logger.info("Writing out complete parcels file")
combined.to_file(outdir / "parcels.gpkg", driver="GPKG")

logger.info("Splitting into small (<1 acre) and large (>=1 acre) polygons")
small = combined[combined["ACRES"] < 1].copy()
large = combined[combined["ACRES"] >= 1].copy()
logger.info(f"Small polygons: {len(small):,}, Large: {len(large):,}")

logger.info("Merging every small polygon into the closest large polygon")

# This returns a data frame with a column called `index_large` that indicates 
# what polygons were matched (`na` if not matched).
small_merged = small.sjoin_nearest(
    large,
    how="left",
    max_distance=200,
    lsuffix="small",
    rsuffix="large",
)

small_no_match = small_merged[small_merged["index_large"].isna()].copy()
small_matched = small_merged[small_merged["index_large"].notna()].copy()
logger.info(f"Small matched: {len(small_matched):,}, unmatched: {len(small_no_match):,}")

# For every parcel ID, combine all the small geometries that matched with that 
# parcel ID.
small_geom_by_target = (
    small_matched.groupby("index_large")["geometry"]
    .agg(lambda geoms: geoms.union_all())
)
# Above produces a simple pd.Series. Need to make it a GeoSeries again with a 
# CRS.
small_geom_by_target = gpd.GeoSeries(small_geom_by_target, crs=small.crs)

# Now, take the unioned small geometries from the previous step and combine 
# them with the original large geometry.
large.loc[small_geom_by_target.index, "geometry"] = (
    large.loc[small_geom_by_target.index, "geometry"]
    .union(small_geom_by_target)
)

# Keep unmatched small polygons, restoring original column names
small_cols = [c for c in small_no_match.columns if not c.endswith("_large")]
small_no_match = small_no_match[small_cols].rename(
    columns={c: c[: -len("_small")] for c in small_cols if c.endswith("_small")}
)

# Verify columns align before concat
assert set(large.columns) == set(small_no_match.columns), (
    f"Column mismatch before concat:\n"
    f"  large only: {set(large.columns) - set(small_no_match.columns)}\n"
    f"  small_no_match only: {set(small_no_match.columns) - set(large.columns)}"
)

# Combine the small unmatched and large (merged) polygons into one data frame 
combined = (
    pd.concat([large, small_no_match])
    .sort_values(by="parcel_id")
    .reset_index(drop=True)
)

# Recalculate area, since we now should have (slightly) larger polygons post combination
combined["ACRES"] = combined.geometry.area / SQ_METERS_PER_ACRE

assert combined["parcel_id"].is_unique, "Duplicate parcel_ids after merge!"

logger.info("Writing out consolidated parcels file")
combined.to_file(outdir / "parcels-consolidated.gpkg", driver="GPKG")

logger.info("Done with STEP 1!")
