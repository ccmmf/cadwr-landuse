# LandIQ harmonization process

This document summarizes the harmonization workflow as it exists as of v0.1.0. It is a process description, not a reproducible pipeline.

The following scripts and files are described in more detail below:

- `scripts/LandIQ_new_shapefile_intake_function.R`
- `scripts/CARB_LandIQ_intake_script.R`
- `scripts/CARB_LandIQ_harmonizing_script.R`
- `scripts/CARB_LandIQ_Script.R`
- `scripts/2025_01_23_dealing_with_unions.R`
- `scripts/009_update_landiq.R`
- `scripts/playground.R`
- `scripts/read_mapped_planting_year.R`
- `data/CARB_PFTs_table.csv`
- `data/CARB_Metadata_ref.csv`
- `data/crops_all_years_metadata.csv`
- `data/landiq_crop_mapping_codes.tsv`
- `docs/metadata.qmd`
- geo.bu.edu paths under `/projectnb/dietzelab/...` as referenced in the scripts

## Inputs and provenance

Primary inputs are LandIQ crop-mapping shapefiles and previously generated harmonized tables staged on geo.bu.edu.

Define the geo.bu.edu CCMMF directory once:

`GEO_CCMMF_DIR=/projectnb/dietzelab/ccmmf`

Canonical staging location on geo.bu.edu:

- `$GEO_CCMMF_DIR/data_raw/cadwr_land_use/`

In this repo, the local mirror of per-year shapefiles (when present) is:

- `data_raw/landiq_shapefiles/`

Reference tables used for interpretation and QA live in this repo:

- `data/CARB_Metadata_ref.csv` (raw LandIQ field definitions and per-year presence)
- `data/crops_all_years_metadata.csv` (harmonized long-table schema)
- `data/landiq_crop_mapping_codes.tsv` (class/subclass codes)
- `data/CARB_PFTs_table.csv` (crop-to-PFT mapping; `scripts/009_update_landiq.R` expects a copy under `raw_data_dir/cadwr_land_use/`)

## Harmonization process (automated vs manual)

The steps below follow the sequence encoded in the scripts. Each step is tagged as "Automated" (scripted) or "Manual/Interactive".

1. Stage external data (Manual/Interactive)
   - External data are staged from geo.bu.edu into the local working layout. The tracked scripts themselves assume geo.bu.edu paths and local relative folders (e.g. `LandIQ_shps/`) rather than a single standardized staging layout.
   - Rsync examples live in comments in `scripts/009_update_landiq.R` (and the canonical geo.bu.edu locations are documented in `README.md`).
   - Source: hard-coded `setwd()` and relative path usage in `scripts/CARB_LandIQ_intake_script.R`, `scripts/CARB_LandIQ_harmonizing_script.R`, `scripts/CARB_LandIQ_Script.R`.

2. Load a LandIQ shapefile for a given year (Automated)
   - `shapefile_grab()` selects a year-specific folder under a caller-provided base directory (typically `LandIQ_shps/` in the legacy scripts) and reads the first `.shp`.
   - Source: `scripts/LandIQ_new_shapefile_intake_function.R`, `scripts/CARB_LandIQ_intake_script.R`, `scripts/CARB_LandIQ_Script.R`.

3. Standardize geometry and add centroids (Automated)
   - Reproject, make valid, compute centroids, add `centx`, `centy`, and `year`, then drop Z/M dimensions.
   - Source: `scripts/LandIQ_new_shapefile_intake_function.R`, `scripts/CARB_LandIQ_intake_script.R`, `scripts/CARB_LandIQ_Script.R`.

4. Select and normalize attribute columns (Automated)
   - Column selection is done via regex matching (e.g., `CLASS`, `SUBCLASS`, `PCNT`, `ADOY`, `YRPLANTED`, `HYDRORGN`, `REGION`, `COUNTY`).
   - Attribute cleaning replaces `*` and `**` with `NA`, normalizes `PCNT` values like `00 -> 100`, and casts to character before reshaping.
   - Source: `scripts/LandIQ_new_shapefile_intake_function.R`, `scripts/CARB_LandIQ_intake_script.R`.

5. Reshape seasonal columns into a long format (Automated)
   - Column names are normalized to combine season numbers with field codes, then reshaped with `pivot_longer()` and `pivot_wider()` into a long table with `season` and `type` columns.
   - Numeric columns are cast to numeric post-pivot.
   - Source: `scripts/LandIQ_new_shapefile_intake_function.R`, `scripts/CARB_LandIQ_intake_script.R`.

6. Harmonize columns across years (Automated + Manual)
   - Older years are padded with missing columns to match newer schemas, then row-bound across years.
   - The process is partly automated but depends on in-memory objects (`crop_df_18` ... `crop_df_23`) defined interactively.
   - Source: `scripts/CARB_LandIQ_intake_script.R`.

7. Reconcile 2016 UniqueID values (Manual/Interactive, with scripted helpers)
   - 2016 polygons are assigned temporary sequential `UniqueID` values and then reconciled with 2018 by spatial intersections.
   - Multiple attempts are encoded in the script; this step appears to require interactive tuning and manual inspection.
   - Source: `scripts/CARB_LandIQ_intake_script.R`, `scripts/CARB_LandIQ_harmonizing_script.R`, `data/crops_all_years_metadata.csv` (notes: "2016 extrapolated from 2018 sites").

8. Fill missing fields across years (Automated)
   - `YRPLANTED` and `HYDRORGN` are filled within `UniqueID` groups using `fill()` operations.
   - Source: `scripts/CARB_LandIQ_harmonizing_script.R`.

9. Write harmonized table (Automated)
   - The long-format table is written to a hard-coded geo.bu.edu path: `/projectnb/dietzelab/ccmmf/LandIQ_data/crops_all_years.csv`.
   - Note: `README.md` documents `/projectnb/dietzelab/ccmmf/data_raw/cadwr_land_use/crops_all_years.csv` as the canonical staged location; the script does not currently write there.
   - Source: `scripts/CARB_LandIQ_harmonizing_script.R`.

10. Optional derived shapefiles and multi-year comparison layers (Manual/Interactive + Automated)
   - `scripts/CARB_LandIQ_Script.R` is an exploratory script for subsetting crops and writing shapefiles; it contains hard-coded output names (e.g. `LandIQ_shps/allcrops/crops2023.shp`) and assumes objects created earlier in an interactive session.
   - `scripts/2025_01_23_dealing_with_unions.R` is primarily a “same-`UniqueID` across years” *comparison* workflow: it filters to IDs present in all years and binds per-year attributes into one wide layer with a single geometry column (it does not perform `st_union()` geometry unions in R). Comments indicate some union products may have been created in QGIS.
   - Source: `scripts/CARB_LandIQ_Script.R`, `scripts/2025_01_23_dealing_with_unions.R`.

## Checks and visualizations

Tracked scripts emphasize tabular QA and spatial overlap checks; explicit plotting is not present in the tracked code.

Tabular checks (Automated):

- Record counts by `CLASS` and year (e.g., pivoted count tables).
- Join failures between `CLASS`/`SUBCLASS` and `CARB_PFTs_table.csv` (missing key diagnostics).
- Frequency of `MULTIUSE` categories and counts of multi-PFT fields.
- Summary of fields with both woody and herbaceous PFTs by year/season.
- Source: `scripts/009_update_landiq.R`.

Spatial checks (Automated + Manual):

- Spatial intersections between 2016 and 2018 polygons to reconcile `UniqueID`.
- Same-`UniqueID` multi-year comparison layers for GIS inspection (attributes from multiple years bound into one layer).
- Source: `scripts/CARB_LandIQ_intake_script.R`, `scripts/2025_01_23_dealing_with_unions.R`.

Exploratory sampling (Manual/Interactive):

- Sampling `UniqueID` subsets and inspecting seasonal `PCNT` totals.
- Source: `scripts/playground.R`.

## Known manual steps and assumptions

- Working directories are hard-coded in the legacy scripts and need refactoring to use a consistent staging layout (in this repo: `data_raw/landiq_shapefiles/`; on geo.bu.edu: `$GEO_CCMMF_DIR/data_raw/cadwr_land_use/`).
- Multiple steps rely on in-memory objects (e.g., `df_piv`, `crop_df_18`...`crop_df_23`), implying interactive sessions rather than scripted runs.
- 2016 `UniqueID` reconciliation requires spatial matching against 2018 polygons and appears to be iterative.
- The union/shapefile workflows are experimental, rely on pre-loaded objects (e.g. `crop2018`–`crop2023`), and include a stray `test` expression in `scripts/2025_01_23_dealing_with_unions.R` that will error if run as-is.
- `scripts/009_update_landiq.R` expects an external `000-config.R` (not tracked) and a particular `data_dir`/`raw_data_dir` layout.
- `scripts/read_mapped_planting_year.R` expects external inputs (`site_info.csv` and `data_raw/dwr_map/*.gdb`) that are not tracked in this repo.

