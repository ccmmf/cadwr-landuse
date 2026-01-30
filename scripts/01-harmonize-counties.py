#!/usr/bin/env python

from pathlib import Path
from functools import reduce

import geopandas as gpd
from tqdm import tqdm

landiq_root_dir = Path("~/data").expanduser()

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
        gpd.read_file(fname, use_arrow=True, columns=["UniqueID", "COUNTY", "geometry"])
        .explode(index_parts=False)
        .reset_index(drop=True)
        .rename(columns={"UniqueID": f"UniqueID_{suffix}"})
    )


print("Reading all data")
dat_all = {year: read_shp(fname, year) for year, fname in tqdm(files.items())}

# Get all counties to loop over
all_counties = dat_all["2023"]["COUNTY"].unique().tolist()

# Use the 2023 CRS for everything
common_crs = dat_all["2023"].crs
dat_all = {year: data.to_crs(common_crs) for year, data in dat_all.items()}

result_dir = Path("_results")
result_dir.mkdir(exist_ok=True, parents=True)

print("Processing overlays by county")
for county in tqdm(all_counties):
    result_file = result_dir / f"{county}.parq"
    if result_file.exists():
        print(f"Skipping existing county {county}")
        continue

    if county == "****":
        print("Skipping '****' --- not sure what this is...")
        continue

    dat_dict = {
        year: dat[dat["COUNTY"] == county].drop(columns=["COUNTY"])
        for year, dat in dat_all.items()
    }

    combined = reduce(
        lambda d1, d2: gpd.overlay(d1, d2, how="union"), dat_dict.values()
    )
    combined.to_parquet(result_file)
