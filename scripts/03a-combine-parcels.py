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
parser.add_argument(
    "--outdir-root",
    type=Path,
    default=Path("_results/v4.1"),
    help="Root directory for all outputs",
)

args = parser.parse_args()

tile_dir = args.outdir_root / "02-tiles-combined"
tile_files = sorted(tile_dir.glob("*.parq"))

outdir = args.outdir_root / "03-final"
outdir.mkdir(exist_ok=True, parents=True)

logger.info("STEP 1: Create merged parcels file")

# Read all the files and combine into a single table
logger.info("Reading and concatenating processed tiles")
combined_raw = pd.concat(
    [gpd.read_parquet(fname) for fname in tqdm(tile_files)], ignore_index=True
)

# Merge polygons that were split only because of tiling
logger.info("Dissolving polygons with identical attributes")
ucols = [col for col in combined_raw.columns if col.startswith("UniqueID_")]
combined_raw["is_duplicate"] = combined_raw.duplicated(subset=ucols, keep=False)
merged = combined_raw.loc[combined_raw["is_duplicate"]].dissolve(
    by=ucols, as_index=False
)
already_unique = combined_raw.loc[~combined_raw["is_duplicate"]]
combined = (
    pd.concat([already_unique, merged], ignore_index=True)
    .sort_values(by=ucols)
    .drop(columns=["is_duplicate"])
)

logger.info("Defining unique parcel ID")
combined.insert(0, "parcel_id", range(len(combined)))
combined["UniqueID_2016"] = combined["UniqueID_2016"].astype(str)

SQ_METERS_PER_ACRE = 4046.8564224
combined["ACRES"] = combined.geometry.area / SQ_METERS_PER_ACRE

logger.info("Writing out complete parcels file")
combined.to_file(outdir / "parcels-all.gpkg", driver="GPKG")

# Merge small polygons (< 1 acre) into nearest large polygon (>= 1 acre)
# within 200m radius
logger.info("Splitting into small (<1 acre) and large (>=1 acre) polygons")
small = combined[combined.geometry.area < SQ_METERS_PER_ACRE].copy()
large = combined[combined.geometry.area >= SQ_METERS_PER_ACRE].copy()

logger.info("Merging small polygons into closest large polygons")
small_merged = small.sjoin_nearest(
    large,
    how="left",
    max_distance=200,
    lsuffix="small",
    rsuffix="large",
)

small_no_match = small_merged[small_merged["index_large"].isna()].copy()
small_matched = small_merged[small_merged["index_large"].notna()].copy()

small_matched["_merge_key"] = small_matched["index_large"]
logger.info("Dissolving columns post merge")
merged = small_matched.dissolve(by="_merge_key", as_index=False)

large_cols = [c for c in merged.columns if not c.endswith("_small")]
merged = merged[large_cols]

small_no_match_cols = [c for c in small_no_match.columns if not c.endswith("_large")]
small_no_match = small_no_match[small_no_match_cols]

combined = pd.concat([large, merged, small_no_match], ignore_index=True).sort_values(
    by="parcel_id"
)
combined["ACRES"] = combined.geometry.area / SQ_METERS_PER_ACRE

logger.info("Writing out only large parcels")
combined.to_file(outdir / "parcels.gpkg", driver="GPKG")

logger.info("Done with STEP 1!")
