#!/usr/bin/env python
from pathlib import Path

import geopandas as gpd
import pandas as pd
import numpy as np
from tqdm import tqdm
import logging
import argparse
import gc

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

parser = argparse.ArgumentParser(description="Finalize crops data from parcels")
parser.add_argument(
    "--landiq-root-dir",
    type=Path,
    default=Path("/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles"),
)
parser.add_argument("--outdir-root", type=Path, default=Path("_results/v4.1"))
args = parser.parse_args()

landiq_root_dir = args.landiq_root_dir
outdir = args.outdir_root / "03-final"
outdir.mkdir(exist_ok=True, parents=True)
parcels_file = outdir / "parcels.gpkg"

logger.info("STEP 2: Merge with LandIQ attributes and melt")

combined = gpd.read_file(parcels_file, use_arrow=True)

combined["centroids"] = combined.geometry.centroid
combined["centx"] = combined["centroids"].x
combined["centy"] = combined["centroids"].y
combined = combined.drop(columns=["geometry", "centroids"])

rename_uid = {
    col: col.replace("UniqueID_", "")
    for col in combined.columns
    if col.startswith("UniqueID_")
}
combined = combined.rename(columns=rename_uid)

year_cols = [col for col in combined.columns if col.isdigit() and len(col) == 4]
id_vars = ["parcel_id", "centx", "centy", "ACRES"]

# Downcast floats before melt to reduce per-row size
combined["centx"] = combined["centx"].astype("float32")
combined["centy"] = combined["centy"].astype("float32")
combined["ACRES"] = combined["ACRES"].astype("float32")

combined_df_melt = combined[id_vars + year_cols]
del combined
gc.collect()

logger.info("Melting to longer data frame by year")
combined_long = combined_df_melt.melt(
    id_vars=id_vars, var_name="year", value_name="UniqueID"
)
combined_long["year"] = combined_long["year"].astype("int16")
del combined_df_melt
gc.collect()

# --- 2. Process one year at a time instead of concat-then-process ---
metadata_file = Path("data") / "CARB_Metadata_ref.csv"
metadata = pd.read_csv(metadata_file)
keep_cols = metadata.loc[metadata["keep"] == 1]

files = {
    2016: landiq_root_dir / "i15_Crop_Mapping_2016_SHP" / "i15_Crop_Mapping_2016.shp",
    2018: landiq_root_dir / "i15_Crop_Mapping_2018_SHP" / "i15_Crop_Mapping_2018.shp",
    2019: landiq_root_dir / "i15_Crop_Mapping_2019_SHP" / "i15_Crop_Mapping_2019.shp",
    2020: landiq_root_dir / "i15_Crop_Mapping_2020_SHP" / "i15_Crop_Mapping_2020.shp",
    2021: landiq_root_dir / "i15_Crop_Mapping_2021_SHP" / "i15_Crop_Mapping_2021.shp",
    2022: landiq_root_dir
    / "i15_Crop_Mapping_2022_Provisional_SHP"
    / "i15_Crop_Mapping_2022_Provisional.shp",
    2023: landiq_root_dir
    / "i15_Crop_Mapping_2023_Provisional_SHP"
    / "i15_Crop_Mapping_2023_Provisional.shp",
}

COLUMN_TYPES = {
    "SUBCLASS": "Int32",  # Int64 wastes space; 32-bit is plenty
    "PCNT": "Int32",
    "ADOY": "Int16",
    "YR_PLANTED": "Int16",
    "ADOY_SEN": "Int16",
    "ADOY_EMRG": "Int16",
    "ACRES": "float32",
}

numeric_pattern_cols = [
    "SUBCLASS",
    "PCNT",
    "ADOY",
    "YR_PLANTED",
    "ADOY_SEN",
    "ADOY_EMRG",
]

irr_type_rename = {}
for i in range(1, 5):
    irr_type_rename[f"IRR_TYP{i}PA"] = f"IRR_TYP_PA{i}"
    irr_type_rename[f"IRR_TYP{i}PB"] = f"IRR_TYP_PB{i}"

stubnames = ["CLASS", "SUBCLASS", "SPECOND", "IRR_TYP_PA", "IRR_TYP_PB", "PCNT", "ADOY"]


def read_data(fname: Path, year: int):
    read_cols = keep_cols.loc[keep_cols[str(year)] == 1]["name"].tolist()
    # Also drop the ACRES column -- we calculate it later
    read_cols = [col for col in read_cols if col != "ACRES"]
    dat = gpd.read_file(fname, use_arrow=True, ignore_geometry=True, columns=read_cols)
    if year == 2016:
        dat = dat.reset_index(names="UniqueID")
        dat["UniqueID"] = dat["UniqueID"].astype(str)
    dat["year"] = np.int16(year)
    return dat


def clean_numeric_cols(df: pd.DataFrame) -> pd.DataFrame:
    """Clean and downcast numeric columns in-place."""
    numeric_cols = [
        col
        for col in df.columns
        if any(col.startswith(p) for p in numeric_pattern_cols)
    ] + ["ACRES"]
    for col in numeric_cols:
        if col not in df.columns:
            continue
        df[col] = df[col].replace(r"^\*+$", None, regex=True)
        if col == "PCNT":
            df[col] = df[col].replace("00", "100")
        df[col] = pd.to_numeric(df[col], errors="coerce")
        if col in COLUMN_TYPES:
            df[col] = df[col].astype(COLUMN_TYPES[col])
    return df


def melt_seasons(df: pd.DataFrame, id_cols: list) -> pd.DataFrame:
    """
    Replace pd.wide_to_long (very memory intensive) with a manual stack approach.
    wide_to_long internally does multiple pivots; stacking is leaner.
    """
    season_cols = [
        col
        for col in df.columns
        if any(
            col.startswith(stub) and col[len(stub) :].isdigit() for stub in stubnames
        )
    ]
    other_cols = [
        col for col in df.columns if col not in season_cols and col not in id_cols
    ]

    # Find which season numbers exist
    seasons = sorted(
        set(
            col[len(stub) :]
            for stub in stubnames
            for col in df.columns
            if col.startswith(stub) and col[len(stub) :].isdigit()
        ),
        key=int,
    )

    # Build each season slice and concat — avoids wide_to_long's internal copies
    slices = []
    for s in seasons:
        stub_map = {
            f"{stub}{s}": stub for stub in stubnames if f"{stub}{s}" in df.columns
        }
        if not stub_map:
            continue
        slice_df = df[id_cols + other_cols + list(stub_map.keys())].copy()
        slice_df = slice_df.rename(columns=stub_map)
        slice_df["season"] = int(s)
        slices.append(slice_df)

    result = pd.concat(slices, ignore_index=True)
    return result


# --- 3. Process year by year, write partitioned parquet ---
logger.info("Merging with parcels and processing year by year")
output_path = outdir / "crops_all_years.parq"

# Write partitioned parquet by year to avoid holding all years in RAM
for year, fname in tqdm(files.items()):
    logger.info(f"Processing year {year}")

    year_parcels = combined_long[combined_long["year"] == year].copy()
    landiq = read_data(fname, year)

    merged = year_parcels.merge(landiq, on=["UniqueID", "year"], how="left")
    del year_parcels, landiq
    gc.collect()

    merged = clean_numeric_cols(merged)
    merged = merged.rename(columns=irr_type_rename)
    merged["_row_id"] = range(len(merged))
    id_cols = ["parcel_id", "year", "_row_id"]

    final_long = melt_seasons(merged, id_cols)
    del merged
    gc.collect()

    # Write one file per year; combine afterward if needed
    final_long.to_parquet(outdir / f"crops_{year}.parq", index=False)
    del final_long
    gc.collect()

logger.info("Consolidating year files")
pd.concat(
    [pd.read_parquet(outdir / f"crops_{year}.parq") for year in files],
    ignore_index=True,
).to_parquet(output_path, index=False)

logger.info("Done!")
