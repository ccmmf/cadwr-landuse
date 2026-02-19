# CADWR Land Use Data: Harmonized LandIQ Crop Mapping for California

[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Data Version](https://img.shields.io/badge/Data_Version-1.0.0-green.svg)](#versioning)

This repository contains scripts, documentation, and lookup tables for processing California Department of Water Resources (CADWR) Statewide Crop Mapping data (commonly known as "LandIQ" data) for use in the CCMMF carbon modeling workflow.

## Overview

The LandIQ dataset provides annual field-level crop identification for all agricultural land in California, derived from satellite imagery (Landsat, Sentinel-2) and verified through ground surveys. This repository harmonizes data from 2018-2023 into a consistent format suitable for carbon cycle modeling at both field and regional scales.

**Key features of the harmonized dataset:**

- **~1.5 million individual parcels of land** tracked across 6 years (2018–2023)
- **Consistent parcel ID** linking fields across years despite boundary changes
- **Multi-season crop tracking** supporting up to 4 crop cycles per year
- **PFT classification** mapping 200+ crop types to Plant Functional Types for ecosystem modeling
- **Phenology indicators** including adjusted day-of-year (ADOY) for peak NDVI

## Data Source

Original data from CADWR Statewide Crop Mapping Program:

| Attribute | Value |
|-----------|-------|
| **Source** | California Department of Water Resources, Land Use Program |
| **Website** | https://data.cnra.ca.gov/dataset/statewide-crop-mapping |
| **Coverage** | Statewide California agricultural lands |
| **Temporal Extent** | 2014, 2016, 2018–2023 (harmonized: 2016–2023) |
| **Update Frequency** | Annual (provisional releases typically in fall, finalized the following year) |
| **Native CRS** | WGS 84 / Pseudo-Mercator for 2014, 2016, and 2018 and NAD83 (EPSG 4269) from 2019 onwards; harmonized to EPSG:3857 (Web Mercator) for centroids |

## Core harmonization workflow

LandIQ harmonization refers to the process of taking the original yearly LandIQ shapefiles and combining them into a single dataset that can be used to track any given parcel of land through time.
The primary challenge is dealing with spatial changes across years:
from one year to the next, some plots will stay the same, some plots will grow or shrink, some groups of plots will be merged into a single plot, and some single plots will be broken up into multiple different plots.

Conceptually, we handle this as an iterative [polygon overlay](https://geopandas.org/en/stable/docs/user_guide/set_operations.html).
The overlay operation takes two sets of polygons as input and returns the set of all unique polygons where the shapes overlap _and_ where they don't overlap (as new separate features).
An iterative overlay means we start in the earliest year of the data (for now, 2018) and advance forward one year at a time accumulating overlays.
R's `sf` package has no `overlay` function, but if it did, the pipeline would effectively look like:

```r
data_2018 |>
    overlay(data_2019) |>
    overlay(data_2020) |>
    # etc...
```

With LandIQ, each year has >400,000 polygons for California.
Since an overlay is inherently a many-to-many operation, that means that in the theoretical worst case, we would have to check roughly 400,000 x 400,000 = 160,000,000,000 intersections
(in practice, GIS software is smarter than this, but it's still a _lot_ of intersections to check).
To make this much more computationally tractable, we instead
divide California into rectangular tiles,
perform the overlay separately (in parallel!) for each tile,
then stack the results together,
and, finally, dissolve the features that have identical attributes. 

For the actual implementation, we use Python's geopandas library, which provides a performant implementation of the `overlay` method out of the box and has mature built-in support for fast reading and writing of large spatial datasets through geoarrow.

> [!NOTE]
> Dependencies for the scripts below are managed using [pixi](https://pixi.prefix.dev/latest/), a conda-based package manager.
> Assuming you have pixi installed (if not, install it! It's a one-line shell command to install, and installs a single binary to your home directory; no admin privileges required), you can run the scripts with, e.g., `pixi run scripts/01-split.py`. Note that you _do not need to install the dependencies manually_ --- on first execution of `pixi run`, pixi will automatically install the exact version of all dependencies used for the original processing (which have been captured in the `pixi.lock` file).
>
> If you prefer to manage dependencies yourself (untested!), you will need Python packages `geopandas`, `pyarrow`, `tqdm`, and `pyogrio`, as well as system libraries `gdal`, `proj`, and `arrow`.

The harmonization pipeline scripts are as follows:

1. `scripts/01-split.py` --- This reads all of the raw LandIQ data, determines the complete bounding box, harmonizes the CRS across the data (we use the CRS of the most recent data), and splits the data into regular tiles, storing each tile in a set of `geoparquet` files --- one for each year (in `_results/tiles-input`; e.g., `_results/tiles-input/x00_y19/{2018.parq, 2019.parq, 2020.parq, ...}`).
    This script should run in less than a minute on a typical modern computer (or single HPC node) and does not require parallelization.
    This produces 274 non-empty tiles.

2. `scripts/02-process-tile.py` --- This script will read in the data for all the years from a single tile (specified by its integer index; e.g., 1, 2, 3...), perform the iterative overlay, and return a single parquet file that contains the resulting polygon geometry and the LandIQ `UniqueID` for each year that corresponds to that specific parcel of land:

    ```
    UniqueID_2018,  UniqueID_2019,  UniqueID_2020,  ...,    geometry
    1234567         1234567         NULL            ...     POLYGON[<...>]      
    1234568         NULL            NULL            ...     POLYGON[<...>]
    ```
    
    These are stored in `results/tiles-output` (e.g., `_results/tiles-output/x00_y19.parq`).
    This script is designed to be run naively in parallel.
    On the BU cluster, we recommend running it as an array job (see the `scripts/scc-process-tiles.sh` script); this will spawn 274 jobs and should finish in 2-2.5 hours (most jobs will be much shorter, but the longest jobs will take this long).

    By default, slight imperfections in the original mapping data cause this approach to identify a lot of tiny new parcels that do not reflect real land cover changes ("slivers").
    To mitigate this we apply two spatial "smoothing" operations to the polygons in each tile before merging:

    (0) Since these operations operate on real distances and areas (rather than units of degrees), we first transform the data to an equal-area projection (California Albers Equal Area; EPSG 3310).
    This is controlled by the `--crs` argument.

    (1) First, we round the individual polygon coordinates to the nearest `X` meters
    This effectively "snaps" polygon vertices to a regular grid with resolution `X m ✗ X m`, which closes some of the artificial gaps.
    The value of `X` here is controlled by the `--precision` argument.

    (2) Second, we smooth the polygon edges by applying a positive buffer of `Y` meters and then immediately applying a negative buffer of `Y` meters ("morphological closing").
    The size of the buffer is controlled by the `--morph-close` argument.

    The current workflow uses `--precision 1.0` and `morph-close 0.5`.
    This reduces the number of polygons in the final result from ~3.7 million to ~1.5 million.

3. `scripts/03-combine-finalize.py` --- This script concatenates all of the tiles from the previous step, merges duplicate rows (and unions the corresponding polygons; this deals with polygons that have been arbitrarily split by our tiling), creates the GeoPackage file with all the individual parcels, and finally merges the parcel UniqueIDs with each of the original LandIQ datasets to create a single, _very_ long but tidy dataset.

At the end of this pipeline, we have two files:

1. `parcels.gpkg` --- The individual parcel map (each row has a unique `parcel_id`, a geometry, and the mapping to each year's `UniqueID`).
2. `crops_all_years.parq` --- The LandIQ complete attribute table for every parcel (there will be up to 6 rows for every `parcel_id` --- one per year).

## Repository Structure

```
cadwr-landuse/
├── LICENSE                         
├── README.md                       
├── metadata.md                     # Detailed column documentation with examples
├── data/
│   ├── CARB_PFTs_table.csv         # Crop -> PFT mapping for ecosystem modeling
│   ├── CARB_Metadata_ref.csv       # Column presence by year (provenance tracking)
│   ├── crops_all_years_metadata.csv # Data dictionary for harmonized CSV
│   └── landiq_crop_mapping_codes.tsv # Complete LandIQ classification codes (206 entries)
└── scripts/
    ├── 01-split.py                     # Harmonization pipeline -- see above
    ├── 02-process-tile.py              # Harmonization pipeline -- see above
    ├── 03-combine-finalize.py          # Harmonization pipeline -- see above
    ├── ...
    ├── scc-process-tiles.sh            # qsub script for running 02-process-tile.py as an array job
    └── ...                             # Additional processing scripts
```

## Data Products

### Primary Output: `crops_all_years.csv`

The harmonized dataset combines all years into a single CSV with consistent column structure.

### Column Reference

| Column | Type | Description | Notes |
|--------|------|-------------|-------|
| `UniqueID` | integer | Persistent field identifier across years | 2016 extrapolated from 2018 spatial join |
| `year` | integer | Data collection year (2016, 2018–2023) | No 2017 data available |
| `centx` | numeric | Field centroid X coordinate | EPSG:3857 (Web Mercator) |
| `centy` | numeric | Field centroid Y coordinate | EPSG:3857 (Web Mercator) |
| `COUNTY` | character | California county name | Based on centroid location |
| `HYDRORGN` | character | DWR hydrologic region | 10 regions statewide |
| `REGION` | character | DWR regional office code | NRO, NCRO, SCRO, SRO |
| `CLASS` | character | Primary crop class code | Single letter (see table below) |
| `SUBCLASS` | integer | Crop subclass for specific identification | Numeric, crop-specific |
| `season` | integer | Growing season (1–4) | Season 2 = main summer crop |
| `MULTIUSE` | character | Cropping intensity code | S/D/T/Q/I/M (see below) |
| `PCNT` | integer | Percentage of field area | "00" represents 100% |
| `ADOY` | integer | Adjusted day-of-year for peak NDVI | Negative = prior year (e.g., -92 = Oct 1) |
| `SENCROP` | character | Senescing crop at start of water year | Crop code from previous season |
| `ADOYSEN` | integer | ADOY for senescing crop | Available 2021+ |
| `ADOYEMRG` | integer | ADOY for emerging crop | Available 2021+ |
| `YRPLANTED` | integer | Year perennial crops were established | Available 2020+; 0 = unknown |
| `SPECOND` | character | Special condition designation | Y = young perennial, etc. |
| `IRRTYPPA` | character | Irrigation status | Blank = presumed irrigated, N = non-irrigated |
| `IRRTYPPB` | character | Irrigation system type | Flood, drip, sprinkler, etc. |

See [metadata.md](metadata.md) for complete column descriptions with example values.

### Cropping Intensity Codes (MULTIUSE)

| Code | Meaning | Description |
|------|---------|-------------|
| S | Single | One crop per water year |
| D | Double | Two crops per water year |
| T | Triple | Three crops per water year |
| Q | Quadruple | Four crops per water year |
| I | Intercropped | Multiple crops grown simultaneously |
| M | Mixed | Combination of cropping patterns |

### Crop Classification System

LandIQ uses a hierarchical CLASS/SUBCLASS system. Major crop classes:

| CLASS | Category | Examples | Typical SUBCLASS Range |
|-------|----------|----------|------------------------|
| C | Citrus & Subtropical | Oranges, lemons, avocados, olives | 1–11 |
| D | Deciduous Fruits & Nuts | Almonds, walnuts, pistachios, stone fruits | 1–21 |
| F | Field Crops | Cotton, corn, beans, safflower | 1–18 |
| G | Grain & Hay | Wheat, barley, oats | 1–7 |
| P | Pasture | Alfalfa, mixed pasture, turf | 1–9 |
| R | Rice | Paddy rice, wild rice | 1–2 |
| T | Truck, Nursery & Berry | Tomatoes, lettuce, strawberries | 1–34 |
| V | Vineyards | Table, wine, and raisin grapes | 1–4 |
| I | Idle | Fallow land (1–4+ years) | 1–4 |
| YP | Young Perennial | Recently planted orchards/vineyards | — |
| X | Unclassified | Unable to determine | — |

Complete classification codes: [data/landiq_crop_mapping_codes.tsv](data/landiq_crop_mapping_codes.tsv)

### Plant Functional Type (PFT) Mapping

For ecosystem modeling, crops are mapped to PFTs in [data/CARB_PFTs_table.csv](data/CARB_PFTs_table.csv):

| PFT Group | Description | Example Crops | N Crop Types |
|-----------|-------------|---------------|--------------|
| `woody` | Perennial woody crops | Almonds, walnuts, citrus, grapes | 45 |
| `row` | Annual row crops | Tomatoes, corn, wheat, vegetables | 89 |
| `hay` | Hay and forage | Alfalfa mixtures, mixed hay | 12 |
| `rice` | Flooded rice systems | Paddy rice, wild rice | 2 |

## Data Access

### Download Complete Data Package

The full harmonized dataset is available from CCMMF's S3 storage:

**Using AWS CLI:**
```bash
aws s3 cp \
    s3://carb/data/ccmmf_landiq_data.tar.gz \
    ccmmf_landiq_data.tar.gz \
    --endpoint-url https://s3.garage.ccmmf.ncsa.cloud
```

**Using rclone:**
```bash
# First, add to ~/.config/rclone/rclone.conf:
# [ccmmf]
# type = s3
# provider = Other
# env_auth = false
# access_key_id = [your key ID]
# secret_access_key = [your secret key]
# region = garage
# endpoint = https://s3.garage.ccmmf.ncsa.cloud
# force_path_style = true
# acl = private
# bucket_acl = private

rclone copy ccmmf:carb/data/ccmmf_landiq_data.tar.gz ./
```

**Extract:**
```bash
tar -xzvf ccmmf_landiq_data.tar.gz
```

### For geo.bu.edu Users

Data is pre-staged at:
```bash
# Harmonized CSV (primary product)
/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/crops_all_years.csv

# Raw shapefiles by year
/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/landiq_shapefiles/

# Spatial join across all years
/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/2015-2023_crops_same_uid/
```

## Usage Examples

### Basic data loading in R

```r
library(tidyverse)

# Load harmonized data (use data.table for speed with large file)
crops <- data.table::fread(
 "/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/crops_all_years.csv"
)

# Load PFT mapping
pft_map <- read_csv("data/CARB_PFTs_table.csv")

# Join to get PFT for each field
crops_with_pft <- crops |>
 filter(!is.na(CLASS)) |>
 left_join(
   pft_map,
   by = c("CLASS" = "crop_type", "SUBCLASS" = "crop_code")
 )

# Summarize woody crops by county (2023, main growing season)
crops_with_pft |>
 filter(season == 2, year == 2023, pft_group == "woody") |>
 group_by(COUNTY) |>
 summarize(
   n_fields = n_distinct(UniqueID),
   .groups = "drop"
 ) |>
 arrange(desc(n_fields))
```

### Working with shapefiles

```r
library(sf)
library(terra)

# Load 2023 shapefile
crops_2023 <- st_read(
 "/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/landiq_shapefiles/i15_Crop_Mapping_2023_Provisional_SHP/i15_Crop_Mapping_2023_Provisional.shp"
)

# Or load the spatial join with all years (large file!)
crops_all_sf <- st_read(
 "/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/2015-2023_crops_same_uid/all_crops_2016-2023_join.shp"
)
```

### Filter by PFT and export subset

```r
# Extract only woody crops for modeling
woody_crops <- crops_with_pft |>
 filter(pft_group == "woody", season == 2) |>
 select(UniqueID, year, centx, centy, COUNTY, CLASS, SUBCLASS, pft_group)

write_csv(woody_crops, "woody_crops_subset.csv")
```

## Processing Pipeline

The harmonization workflow consists of three main steps:

1. **Intake** ([`CARB_LandIQ_intake_script.R`](scripts/CARB_LandIQ_intake_script.R))
  - Load annual shapefiles from CADWR
  - Standardize CRS to EPSG:3857
  - Extract field centroids
  - Select and rename columns consistently

2. **Harmonize** ([`CARB_LandIQ_harmonizing_script.R`](scripts/CARB_LandIQ_harmonizing_script.R))
  - Align columns across years (handle missing columns in earlier years)
  - Pivot from wide to long format (one row per field × year × season)
  - Fill missing values (e.g. back-fill YRPLANTED using group-by operations)

3. **Export**
  - Write to CSV for efficient querying without spatial overhead
  - Preserve geometry in separate shapefiles for spatial operations

## Known Data Issues

| Issue | Affected Years | Description | Workaround |
|-------|----------------|-------------|------------|
| Missing UniqueID | 2016 | Extrapolated from 2018 spatial join | Fields with NA UniqueID were not in 2018 data |
| Provisional data | 2022–2023 | May be updated in future CADWR releases | Check for updates annually |
| No Season 4 | 2016 | Fourth season added starting 2018 | Use seasons 1–3 only for 2016 |
| Missing YRPLANTED | 2016–2019 | Only available from 2020 onward | Back-filled where possible; 0 = unknown |
| Centroid shifts | All years | Field boundaries occasionally change | Same UniqueID may have slightly different coordinates |
| No 2017 data | 2017 | CADWR did not release 2017 survey | Gap year in time series |

## License

This repository is licensed under the [BSD 3-Clause License](LICENSE).

The underlying LandIQ data is provided by CADWR under their [data license](https://data.cnra.ca.gov/).
