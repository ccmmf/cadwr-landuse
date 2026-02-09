# CADWR Land Use Data: Harmonized LandIQ Crop Mapping for California

[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE)
[![Code License](https://img.shields.io/badge/Code_License-BSD_3--Clause-blue.svg)](LICENSE)
![Public Domain Data](https://img.shields.io/badge/Data_License-CC0_1.0-lightgrey.svg)](https://creativecommons.org/public-domain/cc0/)
[![Data Version](https://img.shields.io/badge/Data_Version-1.0.0-green.svg)](#versioning)


This repository contains scripts, documentation, and lookup tables for processing California Department of Water Resources (CADWR) Statewide Crop Mapping data (commonly known as "LandIQ" data) for use in the CCMMF carbon modeling workflow.

## Overview

The LandIQ dataset provides annual field-level crop identification for all agricultural land in California, derived from satellite imagery (Landsat, Sentinel-2) and verified through ground surveys. This repository harmonizes data from 2016–2023 into a consistent format suitable for carbon cycle modeling at both field and regional scales.

**Key features of the harmonized dataset:**

- **~600,000 agricultural fields** tracked across 8 years (2016, 2018–2023)
- **Consistent UniqueID** linking fields across years despite boundary changes
- **Multi-season crop tracking** supporting up to 4 crop cycles per year
- **PFT classification** mapping 200+ crop types to Plant Functional Types for ecosystem modeling
- **Phenology indicators** including adjusted day-of-year (ADOY) for peak NDVI

## Data Source

Original data from CADWR Statewide Crop Mapping Program:

| Attribute            | Value                                                                         |
| -------------------- | ----------------------------------------------------------------------------- |
| **Source**           | California Department of Water Resources, Land Use Program                    |
| **Website**          | https://data.cnra.ca.gov/dataset/statewide-crop-mapping                       |
| **Coverage**         | Statewide California agricultural lands                                       |
| **Temporal Extent**  | 2014, 2016, 2018–2023 (harmonized: 2016–2023)                                 |
| **Update Frequency** | Annual (provisional releases typically in fall, finalized the following year) |
| **Native CRS**       | WGS 84 / Pseudo-Mercator for 2014, 2016, and 2018 and NAD83 (EPSG 4269) from 2019 onwards; harmonized to EPSG:3857 (Web Mercator) for centroids |

## Repository Structure

```
cadwr-landuse/
├── LICENSE                         
├── README.md                       
├── docs/
│   ├── harmonization_v0.1.md       # Harmonization workflow documentation (v0.1)
│   └── metadata.qmd                # Generated metadata tables (from `data/`)
├── data/
│   ├── CARB_PFTs_table.csv         # Crop -> PFT mapping for ecosystem modeling
│   ├── CARB_Metadata_ref.csv       # Column presence by year (provenance tracking)
│   ├── crops_all_years_metadata.csv # Data dictionary for harmonized CSV
│   └── landiq_crop_mapping_codes.tsv # Complete LandIQ classification codes (206 entries)
└── scripts/
    ├── CARB_LandIQ_intake_script.R      # Main shapefile processing pipeline
    ├── CARB_LandIQ_harmonizing_script.R # Cross-year harmonization
    ├── LandIQ_new_shapefile_intake_function.R # Functions for new year intake
    ├── 009_update_landiq.R              # Integration with downscaling workflow
    └── ...                              # Additional processing scripts
```

## Data Products

### Primary Output: `crops_all_years.csv`

The harmonized dataset combines all years into a single CSV with consistent column structure.

### Column Reference

<!-- TODO: Render the tables in this section from the source CSV/TSV files in `data/` (see `docs/metadata.qmd`) to avoid maintaining two sources of truth. -->

| Column      | Type      | Description                               | Notes                                         |
| ----------- | --------- | ----------------------------------------- | --------------------------------------------- |
| `UniqueID`  | integer   | Persistent field identifier across years  | 2016 extrapolated from 2018 spatial join      |
| `year`      | integer   | Data collection year (2016, 2018–2023)    | No 2017 data available                        |
| `centx`     | numeric   | Field centroid X coordinate               | EPSG:3857 (Web Mercator)                      |
| `centy`     | numeric   | Field centroid Y coordinate               | EPSG:3857 (Web Mercator)                      |
| `COUNTY`    | character | California county name                    | Based on centroid location                    |
| `HYDRORGN`  | character | DWR hydrologic region                     | 10 regions statewide                          |
| `REGION`    | character | DWR regional office code                  | NRO, NCRO, SCRO, SRO                          |
| `CLASS`     | character | Primary crop class code                   | Single letter (see table below)               |
| `SUBCLASS`  | integer   | Crop subclass for specific identification | Numeric, crop-specific                        |
| `season`    | integer   | Growing season (1–4)                      | Season 2 = main summer crop                   |
| `MULTIUSE`  | character | Cropping intensity code                   | S/D/T/Q/I/M (see below)                       |
| `PCNT`      | integer   | Percentage of field area                  | "00" represents 100%                          |
| `ADOY`      | integer   | Adjusted day-of-year for peak NDVI        | Negative = prior year (e.g., -92 = Oct 1)     |
| `SENCROP`   | character | Senescing crop at start of water year     | Crop code from previous season                |
| `ADOYSEN`   | integer   | ADOY for senescing crop                   | Available 2021+                               |
| `ADOYEMRG`  | integer   | ADOY for emerging crop                    | Available 2021+                               |
| `YRPLANTED` | integer   | Year perennial crops were established     | Available 2020+; 0 = unknown                  |
| `SPECOND`   | character | Special condition designation             | Y = young perennial, etc.                     |
| `IRRTYPPA`  | character | Irrigation status                         | Blank = presumed irrigated, N = non-irrigated |
| `IRRTYPPB`  | character | Irrigation system type                    | Flood, drip, sprinkler, etc.                  |

See [data/crops_all_years_metadata.csv](data/crops_all_years_metadata.csv) for complete column descriptions and notes.

### Cropping Intensity Codes (MULTIUSE)

| Code | Meaning      | Description                         |
| ---- | ------------ | ----------------------------------- |
| S    | Single       | One crop per water year             |
| D    | Double       | Two crops per water year            |
| T    | Triple       | Three crops per water year          |
| Q    | Quadruple    | Four crops per water year           |
| I    | Intercropped | Multiple crops grown simultaneously |
| M    | Mixed        | Combination of cropping patterns    |

### Crop Classification System

LandIQ uses a hierarchical CLASS/SUBCLASS system. Major crop classes:

| CLASS | Category                | Examples                                   | Typical SUBCLASS Range |
| ----- | ----------------------- | ------------------------------------------ | ---------------------- |
| C     | Citrus & Subtropical    | Oranges, lemons, avocados, olives          | 1–11                   |
| D     | Deciduous Fruits & Nuts | Almonds, walnuts, pistachios, stone fruits | 1–21                   |
| F     | Field Crops             | Cotton, corn, beans, safflower             | 1–18                   |
| G     | Grain & Hay             | Wheat, barley, oats                        | 1–7                    |
| P     | Pasture                 | Alfalfa, mixed pasture, turf               | 1–9                    |
| R     | Rice                    | Paddy rice, wild rice                      | 1–2                    |
| T     | Truck, Nursery & Berry  | Tomatoes, lettuce, strawberries            | 1–34                   |
| V     | Vineyards               | Table, wine, and raisin grapes             | 1–4                    |
| I     | Idle                    | Fallow land (1–4+ years)                   | 1–4                    |
| YP    | Young Perennial         | Recently planted orchards/vineyards        | —                      |
| X     | Unclassified            | Unable to determine                        | —                      |

Complete classification codes: [data/landiq_crop_mapping_codes.tsv](data/landiq_crop_mapping_codes.tsv)

### Plant Functional Type (PFT) Mapping

For ecosystem modeling, crops are mapped to PFTs in [data/CARB_PFTs_table.csv](data/CARB_PFTs_table.csv):

| PFT Group | Description           | Example Crops                     | N Crop Types |
| --------- | --------------------- | --------------------------------- | ------------ |
| `woody`   | Perennial woody crops | Almonds, walnuts, citrus, grapes  | 45           |
| `row`     | Annual row crops      | Tomatoes, corn, wheat, vegetables | 89           |
| `hay`     | Hay and forage        | Alfalfa mixtures, mixed hay       | 12           |
| `rice`    | Flooded rice systems  | Paddy rice, wild rice             | 2            |

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

Define the CCMMF directory once for convenience:

```bash
export GEO_CCMMF_DIR=/projectnb/dietzelab/ccmmf
```

Data is pre-staged at:
```bash
# Harmonized CSV (primary product)
$GEO_CCMMF_DIR/data_raw/cadwr_land_use/crops_all_years.csv

# Raw shapefiles by year
$GEO_CCMMF_DIR/data_raw/cadwr_land_use/landiq_shapefiles/

# Spatial join across all years
$GEO_CCMMF_DIR/data_raw/cadwr_land_use/2015-2023_crops_same_uid/
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

| Issue             | Affected Years | Description                             | Workaround                                            |
| ----------------- | -------------- | --------------------------------------- | ----------------------------------------------------- |
| Missing UniqueID  | 2016           | Extrapolated from 2018 spatial join     | Fields with NA UniqueID were not in 2018 data         |
| Provisional data  | 2022–2023      | May be updated in future CADWR releases | Check for updates annually                            |
| No Season 4       | 2016           | Fourth season added starting 2018       | Use seasons 1–3 only for 2016                         |
| Missing YRPLANTED | 2016–2019      | Only available from 2020 onward         | Back-filled where possible; 0 = unknown               |
| Centroid shifts   | All years      | Field boundaries occasionally change    | Same UniqueID may have slightly different coordinates |
| No 2017 data      | 2017           | CADWR did not release 2017 survey       | Gap year in time series                               |

## License

This repository is licensed under the [BSD 3-Clause License](LICENSE).

The underlying LandIQ data is provided by CADWR under their [data license](https://data.cnra.ca.gov/).
