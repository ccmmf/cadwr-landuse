#!/usr/bin/env python
from pathlib import Path

import geopandas as gpd
import pandas as pd
from tqdm import tqdm

import argparse

parser = argparse.ArgumentParser(description="Recombine tiles and finalize")
parser.add_argument(
    "--landiq-root-dir",
    type=Path,
    default=Path("/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles"),
    help="Root directory for LandIQ shapefiles",
)
parser.add_argument(
    "--tile-dir", type=Path, default=Path("_results/tiles-output-sp")
)
parser.add_argument(
    "--outdir", type=Path, default=Path("_results/final-tiles-sp")
)

args = parser.parse_args()
# args = parser.parse_args(["--tile-dir", "_results/w2016/tiles-out/", "--outdir", "_results/w2016/final/"])

landiq_root_dir = args.landiq_root_dir
tile_files = sorted(args.tile_dir.glob("*.parq"))

outdir = args.outdir
outdir.mkdir(exist_ok=True, parents=True)

# Read all the files and combine into a single table
combined_raw = pd.concat(
    [gpd.read_parquet(fname) for fname in tqdm(tile_files)], ignore_index=True
)

# Merge polygons that were split only because of tiling
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

combined.insert(0, "parcel_id", range(len(combined)))
combined["UniqueID_2016"] = combined["UniqueID_2016"].astype(str)
combined.to_file(outdir / "parcels.gpkg", driver="GPKG")

# Now, build a long table of the metadata
# First, calculate the centroids.
combined['centroids'] = combined.geometry.centroid
combined['centx'] = combined["centroids"].x
combined['centy'] = combined["centroids"].y
combined_df = combined.drop(columns=["geometry", "centroids"])

# Rename `"UniqueID_2023"` to `2023`
# Do this before melting to avoid allocating a huge string unnecessarily.
rename_uid = {
    col: col.replace("UniqueID_", "")
    for col in combined_df.columns
    if col.startswith("UniqueID_")
}
combined_long = combined_df.rename(columns=rename_uid).melt(
    id_vars=["parcel_id", "centx", "centy"], var_name="year", value_name="UniqueID"
)
combined_long["year"] = combined_long["year"].astype(int)

# Now, we load the original data and merge in the relevant metadata.
files = {
    2016: landiq_root_dir / "i15_Crop_Mapping_2016_SHP" / "i15_Crop_Mapping_2016.shp",
    2018: landiq_root_dir / "i15_Crop_Mapping_2018_SHP" / "i15_Crop_Mapping_2018.shp",
    2019: landiq_root_dir / "i15_Crop_Mapping_2019_SHP" / "i15_Crop_Mapping_2019.shp",
    2020: landiq_root_dir / "i15_Crop_Mapping_2020_SHP" / "i15_Crop_Mapping_2020.shp",
    2021: landiq_root_dir / "i15_Crop_Mapping_2021_SHP" / "i15_Crop_Mapping_2021.shp",
    2022: (
        landiq_root_dir
        / "i15_Crop_Mapping_2022_Provisional_SHP"
        / "i15_Crop_Mapping_2022_Provisional.shp"
    ),
    2023: (
        landiq_root_dir
        / "i15_Crop_Mapping_2023_Provisional_SHP"
        / "i15_Crop_Mapping_2023_Provisional.shp"
    ),
}

# Read metadata columns
metadata_file = Path("data") / "CARB_Metadata_ref.csv"
metadata = pd.read_csv(metadata_file)
keep_cols = metadata.loc[metadata["keep"] == 1]


def read_data(fname: Path, year: int):
    # Figure out which columns to read based on the year
    read_cols = keep_cols.loc[keep_cols[str(year)] == 1]["name"]
    dat = gpd.read_file(fname, use_arrow=True, ignore_geometry=True, columns=read_cols)
    if year == 2016:
        dat = dat.reset_index(names="UniqueID")
        dat["UniqueID"] = dat["UniqueID"].astype(str)
    dat["year"] = year
    return dat


print("Merging in metadata")
final_wide = pd.concat(
    combined_long.merge(read_data(fname, year), on=["UniqueID", "year"])
    for year, fname in tqdm(files.items())
)

# `pd.wide_to_long` expects the number to be at the end of the column name
irr_type_rename = {}
for i in range(1, 5):
    irr_type_rename[f"IRR_TYP{i}PA"] = f"IRR_TYP_PA{i}"
    irr_type_rename[f"IRR_TYP{i}PB"] = f"IRR_TYP_PB{i}"

final_wide = final_wide.rename(columns=irr_type_rename)

stubnames = ['CLASS', 'SUBCLASS', 'SPECOND', 'IRR_TYP_PA', 'IRR_TYP_PB', 'PCNT', 'ADOY']

# Get season columns
season_cols = [col for col in final_wide.columns 
               if any(col.startswith(stub) and col[len(stub):].isdigit() 
                      for stub in stubnames)]

# Split the dataframe
id_cols = ['parcel_id', 'year']
df_to_melt = final_wide[id_cols + season_cols]
df_other = final_wide[id_cols + [col for col in final_wide.columns 
                                 if col not in season_cols and col not in id_cols]]

# Melt with minimal ID columns
final_long = pd.wide_to_long(
    df_to_melt,
    stubnames=stubnames,
    i=id_cols,
    j='season',
    sep=''
).reset_index()

# Join back the other columns
final_long = final_long.merge(df_other, on=id_cols, how='left')

# Some sanity checks
# county_counts = final.groupby(["parcel_id"])["COUNTY"].nunique()
# if bad_rows := (county_counts[county_counts > 1]).size:
#     raise ValueError(f"{bad_rows} parcels moved counties.")

final_long.to_parquet(outdir / "crops_all_years.parq")
