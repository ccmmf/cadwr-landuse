#!/usr/bin/env python

from pathlib import Path
import geopandas as gpd
import pandas as pd
import uuid
from tqdm import tqdm

landiq_root_dir = Path("~/data").expanduser()
county_files = sorted(Path("_results").glob("*.parq"))

outdir = Path("_results") / "final"
outdir.mkdir(exist_ok=True, parents=True)

# Read all the files and combine into a single table
combined = pd.concat(
    [gpd.read_parquet(fname) for fname in county_files], ignore_index=True
)

combined.insert(0, "uuid", [str(uuid.uuid4()) for _ in range(len(combined))])
combined.to_file(outdir / "parcels.gpkg", driver="GPKG")

# Now, build a long table of the metadata
combined_df = combined.drop(columns="geometry")

combined_long = combined_df.melt(
    id_vars=["uuid"], var_name="year_col", value_name="UniqueID"
)

combined_long["year"] = (
    combined_long["year_col"].str.extract(r"UniqueID_(\d{4})").astype(int)
)
combined_long = combined_long[["uuid", "year", "UniqueID"]]

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


def read_data(fname: Path, year: int):
    dat = gpd.read_file(fname, use_arrow=True, ignore_geometry=True)
    # These columns are called different things at different points in time.
    try:
        dat = dat.drop(columns=["Shape_STAr", "Shape_STLe"])
    except KeyError:
        pass
    try:
        dat = dat.drop(columns=["Shape_Leng", "Shape_Area"])
    except KeyError:
        pass
    dat["year"] = year
    return dat


print("Merging in metadata")
final = pd.concat(
    combined_long.merge(read_data(fname, year), on=["UniqueID", "year"])
    for year, fname in tqdm(files.items())
)

# Some sanity checks
county_counts = final.groupby(["uuid"])["COUNTY"].nunique()
if bad_rows := (county_counts[county_counts > 1]).size:
    raise ValueError(f"{bad_rows} parcels moved counties.")

final.to_parquet(outdir / "metadata.parq")
