#!/usr/bin/env python
from pathlib import Path
import geopandas as gpd
import pandas as pd
from tqdm import tqdm

landiq_root_dir = Path("/projectnb/dietzelab/ccmmf/LandIQ_data/LandIQ_shapefiles")
# landiq_root_dir = Path("~/data").expanduser()
tile_files = sorted(Path("_results/tiles").glob("*.parq"))

outdir = Path("_results") / "final-tiles"
outdir.mkdir(exist_ok=True, parents=True)

# Read all the files and combine into a single table
combined_raw = pd.concat(
    [gpd.read_parquet(fname) for fname in tile_files], ignore_index=True
)

# Merge polygons that were split only because of tiling
ucols = [col for col in combined_raw.columns if col.startswith("UniqueID_")]
combined_raw["is_duplicate"] = combined_raw.duplicated(subset=ucols, keep=False)
merged = combined_raw.loc[combined_raw["is_duplicate"]].dissolve(
    by=ucols, as_index=False
)
already_unique = combined_raw.loc[~combined_raw["is_duplicate"]].drop(
    columns=["is_duplicate"]
)
combined = pd.concat([already_unique, merged], ignore_index=True).sort_values(by=ucols)

combined.insert(0, "parcel_id", range(len(combined)))
combined.to_file(outdir / "parcels.gpkg", driver="GPKG")

# Now, build a long table of the metadata
combined_df = combined.drop(columns="geometry")

# Rename `"UniqueID_2023"` to `2023` with `int` type.
# Do this before melting to avoid allocating a huge string unnecessarily.
rename_uid = {
    col: col.replace("UniqueID_", "")
    for col in combined_df.columns
    if col.startswith("UniqueID_")
}
combined_long = combined_df.rename(columns=rename_uid).melt(
    id_vars=["parcel_id"], var_name="year", value_name="UniqueID"
)
combined_long["year"] = combined_long["year"].astype(int)

# Now, we load the original data and merge in the relevant metadata.
files = {
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
    dat["year"] = year
    return dat


print("Merging in metadata")
final = pd.concat(
    combined_long.merge(read_data(fname, year), on=["UniqueID", "year"])
    for year, fname in tqdm(files.items())
)

# Some sanity checks
county_counts = final.groupby(["parcel_id"])["COUNTY"].nunique()
if bad_rows := (county_counts[county_counts > 1]).size:
    raise ValueError(f"{bad_rows} parcels moved counties.")

final.to_parquet(outdir / "metadata.parq")
