#!/usr/bin/env Rscript

library(sf)
library(purrr)
library(duckdb)
library(dplyr)
library(DBI)

conn <- dbConnect(duckdb())
dbExecute(conn, "INSTALL spatial")
dbExecute(conn, "LOAD spatial")

rootdir <- file.path(
  "/projectnb",
  "dietzelab",
  "ccmmf",
  "LandIQ_data",
  "LandIQ_shapefiles"
)

year_files <- list(
  raw_2023 = file.path(
    rootdir,
    "i15_Crop_Mapping_2023_Provisional_SHP",
    "i15_Crop_Mapping_2023_Provisional.shp"
  ),
  raw_2022 = file.path(
    rootdir,
    "i15_Crop_Mapping_2022_Provisional_SHP",
    "i15_Crop_Mapping_2022_Provisional.shp"
  ),
  raw_2021 = file.path(
    rootdir,
    "i15_Crop_Mapping_2021_SHP",
    "i15_Crop_Mapping_2021.shp"
  )
  # raw_2020 = file.path(
  #   rootdir,
  #   "i15_Crop_Mapping_2020_SHP",
  #   "i15_Crop_Mapping_2020.shp"
  # )
)

load_year <- function(fname, tbl_name) {
  stopifnot(file.exists(fname))
  message("Reading ", fname)
  dbExecute(conn, glue::glue(
    "CREATE TABLE {tbl_name} AS SELECT * FROM st_read('{fname}')"
  ))
}

iwalk(year_files, load_year)

create_spatial_index <- function(tbl_name, column = "geom") {
  dbExecute(conn, glue::glue(
    "CREATE INDEX idx_{tbl_name}_geom ON {tbl_name} USING RTREE ({column})"
  ))
}

fix_geoms <- function(tbl_name) {
  message("Fixing geoms in ", tbl_name)
  dbExecute(conn, glue::glue(
    "UPDATE {tbl_name} SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom)"
  ))
  create_spatial_index(tbl_name, "geom")
}

walk(names(year_files), fix_geoms)

calc_centroid_area <- function(tbl_name) {
  target_table <- gsub("raw_", "ca_", tbl_name)
  message("Calculating centroids and areas for table ", tbl_name)
  dbExecute(conn, glue::glue("
    CREATE OR REPLACE VIEW {target_table} AS
    WITH centroids AS (
      SELECT
      *,
      ST_Centroid(geom) AS centroid
      FROM {tbl_name}
    )
    SELECT
      *,
      ST_X(centroid) AS centroid_x,
      ST_Y(centroid) AS centroid_y,
      ST_Area(geom) AS area
    FROM centroids
    ")
  )
  target_table
}

centroid_tbls <- map_chr(names(year_files), calc_centroid_area)

# First, get near-exact matches
exact_matches_withid <- function(year1, year2) {
  message("Looking for exact matches")
  area_threshold <- 0.05  # Area is within 5%
  centroid_prec <- 3      # Round centroids to this many digits for comparison
  dbExecute(conn, glue::glue("
    CREATE OR REPLACE TABLE all_matches AS
    WITH intersections AS (
      SELECT
        y1.UniqueID AS uniqueid_{year1},
        y2.UniqueID AS uniqueid_{year2},
        'exact_match' AS match_type,
        ST_Intersection(y1.geom, y2.geom) AS intersected_geom,
      FROM ca_{year1} y1
      JOIN ca_{year2} y2
      ON y1.UniqueID = y2.UniqueID
      AND ROUND(y1.centroid_x, {centroid_prec})
        = ROUND(y2.centroid_x, {centroid_prec})
      AND ROUND(y1.centroid_y, {centroid_prec})
        = ROUND(y2.centroid_y, {centroid_prec})
      -- Area within 10%
      AND ABS(y1.area - y2.area)
        / y1.area < {area_threshold}
    )
    SELECT
      uniqueid_{year1},
      uniqueid_{year2},
      match_type,
      intersected_geom AS geom,
      ST_X(ST_Centroid(intersected_geom)) AS centroid_x,
      ST_Y(ST_Centroid(intersected_geom)) AS centroid_y,
      ST_Area(intersected_geom) AS area
    FROM intersections
    "
  ))
  create_spatial_index("all_matches", "geom")
}

get_unmatched <- function(year, from) {
  dbExecute(conn, glue::glue("
    CREATE OR REPLACE VIEW unmatched_{year} AS
    SELECT * FROM ca_{year}
    WHERE UniqueID NOT IN (
      SELECT uniqueid_{year} FROM {from} WHERE uniqueid_{year} IS NOT NULL
    )
    "
  ))
}

exact_matches_withid("2021", "2022")
get_unmatched("2021", "all_matches")
get_unmatched("2022", "all_matches")

# Now, repeat but ignore UniqueIDs
exact_matches_noid <- function(year1, year2) {
  message("Looking for exact matches")
  area_threshold <- 0.05  # Area is within 5%
  centroid_prec <- 3      # Round centroids to this many digits for comparison
  dbExecute(conn, glue::glue("
    INSERT INTO all_matches BY NAME
    WITH intersections AS (
      SELECT
        y1.UniqueID AS uniqueid_{year1},
        y2.UniqueID AS uniqueid_{year2},
        'exact_match' AS match_type,
        ST_Intersection(y1.geom, y2.geom) AS intersected_geom
      FROM unmatched_{year1} y1
      JOIN unmatched_{year2} y2
      ON
        ROUND(y1.centroid_x, {centroid_prec})
        = ROUND(y2.centroid_x, {centroid_prec})
      AND ROUND(y1.centroid_y, {centroid_prec})
        = ROUND(y2.centroid_y, {centroid_prec})
      -- Area within 10%
      AND ABS(y1.area - y2.area)
        / y1.area < {area_threshold}
    )
    SELECT
      uniqueid_{year1},
      uniqueid_{year2},
      match_type,
      intersected_geom AS geom,
      ST_X(ST_Centroid(intersected_geom)) AS centroid_x,
      ST_Y(ST_Centroid(intersected_geom)) AS centroid_y,
      ST_Area(intersected_geom) AS area
    FROM intersections
    "
  ))
}

exact_matches_noid("2021", "2022")
get_unmatched("2021", "all_matches")
get_unmatched("2022", "all_matches")

# For now, skip the edge cases (merges, splits) and just harmonize this.
# Next, we use `all_matches` as the basis to merge in the next year (2023).
year1 <- "2022"
year2 <- "2023"
dbExecute(conn, glue::glue("
  CREATE OR REPLACE TABLE all_matches_2 AS
  WITH intersections AS (
    SELECT
      y1.uniqueid_{year1} AS uniqueid_{year1},
      y2.UniqueID AS uniqueid_{year2},
      'exact_match' AS match_type,
      ST_Intersection(y1.geom, y2.geom) AS intersected_geom,
    FROM all_matches y1
    JOIN ca_{year2} y2
    ON y1.uniqueid_{year1} = y2.UniqueID
    AND ROUND(y1.centroid_x, {centroid_prec})
      = ROUND(y2.centroid_x, {centroid_prec})
    AND ROUND(y1.centroid_y, {centroid_prec})
      = ROUND(y2.centroid_y, {centroid_prec})
    -- Area within 10%
    AND ABS(y1.area - y2.area)
      / y1.area < {area_threshold}
  )
  SELECT
    uniqueid_{year1},
    uniqueid_{year2},
    match_type,
    intersected_geom AS geom,
    ST_X(ST_Centroid(intersected_geom)) AS centroid_x,
    ST_Y(ST_Centroid(intersected_geom)) AS centroid_y,
    ST_Area(intersected_geom) AS area
  FROM intersections
  "
))
create_spatial_index("all_matches_2", "geom")
# get_unmatched("2022", "all_matches_2")
get_unmatched("2023", "all_matches_2")

# ...and repeat again ignoring unique IDs
dbExecute(conn, glue::glue("
  INSERT INTO all_matches_2 BY NAME
  WITH intersections AS (
    SELECT
      y1.uniqueid_{year1} AS uniqueid_{year1},
      y2.UniqueID AS uniqueid_{year2},
      'exact_match' AS match_type,
      ST_Intersection(y1.geom, y2.geom) AS intersected_geom,
    FROM all_matches y1
    JOIN unmatched_{year2} y2
    ON ROUND(y1.centroid_x, {centroid_prec})
      = ROUND(y2.centroid_x, {centroid_prec})
    AND ROUND(y1.centroid_y, {centroid_prec})
      = ROUND(y2.centroid_y, {centroid_prec})
    -- Area within 10%
    AND ABS(y1.area - y2.area)
      / y1.area < {area_threshold}
  )
  SELECT
    uniqueid_{year1},
    uniqueid_{year2},
    match_type,
    intersected_geom AS geom,
    ST_X(ST_Centroid(intersected_geom)) AS centroid_x,
    ST_Y(ST_Centroid(intersected_geom)) AS centroid_y,
    ST_Area(intersected_geom) AS area
  FROM intersections
  "
))
get_unmatched("2023", "all_matches_2")

dbExecute(conn, glue::glue("
  CREATE OR REPLACE TABLE combined AS
  SELECT
    y1.uniqueid_2021 AS uniqueid_2021,
    y23.*
  FROM all_matches y1
  JOIN all_matches_2 y23
  ON y1.uniqueid_2022 = y23.uniqueid_2022
  "))
create_spatial_index("combined", "geom")

# Write to disk.
combined <- duckspatial::ddbs_read_vector(conn, "combined")
sf::st_crs(combined) <- 4269
sfarrow::st_write_parquet(combined, "combined.geoparquet")

################################################################################
stop("Scratch code below here...")

# dbGetQuery(conn, "SELECT ST_SRID(geom) AS srid FROM combined LIMIT 1")
# dbGetQuery(conn, glue::glue("SELECT * FROM st_read_meta('{year_files[[1]]}')"))[["layers"]][[1]]
dbGetQuery(conn, glue::glue("SELECT * FROM st_read_meta('combined.parquet')"))
# dbExecute(conn, "
#   COPY combined TO 'combined.gpkg'
#   WITH (FORMAT GDAL, DRIVER 'GPKG')
#   ")

# TODO: DuckDB query to ensure that this is a 1-to-1 match
# exact_matches <- tibble::tibble(dbGetQuery(conn, "SELECT * FROM exact_matches"))
# exact_matches |>
#   filter(uniqueid_2022 != uniqueid_2023) |>
#   arrange(uniqueid_2022, uniqueid_2023)

# Get all unmatched features in 2022
message("Calculating unmatched features")

get_split_or_merge <- function(year1, year2, kind) {
  result_table <- glue::glue("{kind}_{year1}_{year2}")
  dbExecute(conn, glue::glue("
    CREATE OR REPLACE TABLE {result_table} AS
    SELECT
      unmatched_{year1}.UniqueID AS uniqueid_{year1},
      unmatched_{year2}.UniqueID AS uniqueid_{year2},
      '{kind}' AS match_type
    FROM unmatched_{year1}
    JOIN unmatched_{year2}
      ON ST_Intersects(unmatched_{year1}.geom, unmatched_{year2}.geom)
    WHERE unmatched_{year1}.UniqueID IN (
      SELECT inner_{year1}.UniqueID
      FROM unmatched_{year1} inner_{year1}
      JOIN unmatched_{year2} inner_{year2}
        ON ST_Intersects(inner_{year1}.geom, inner_{year2}.geom)
      GROUP BY inner_{year1}.UniqueID
      HAVING COUNT(DISTINCT inner_{year2}.UniqueID) > 1
    )
    ")) |> print()
  result_table
}

# Splits: 2022 intersects 2023 and ST_Area(2022) > ST_Area(2023)
message("Calculating splits...")
splits_tbl <- get_split_or_merge("2022", "2023", "split")

# Add splits to all_matches
dbExecute(conn, glue::glue("
  INSERT INTO all_matches
  SELECT * FROM {splits_tbl}
  "))
get_unmatched("2022")
get_unmatched("2023")

# splits <- dbGetQuery(conn, glue::glue(
#   "SELECT * FROM {splits_tbl}
#   ORDER BY uniqueid_2022, uniqueid_2023
#   "
# )) |>
#   tibble::tibble()


# Merges: Same as splits, but in the other direction
message("Calculating merges...")
merges_tbl <- get_split_or_merge("2023", "2022", "merge")
dbExecute(conn, glue::glue("
  INSERT INTO all_matches
  SELECT * FROM {merges_tbl}
  "))
get_unmatched("2022")
get_unmatched("2023")

# So...what's left? Unclear.

all_matches <- dbGetQuery(conn, "SELECT * FROM all_matches")
head(all_matches)

readr::write_csv(all_matches, "data/2022-2023.csv")

################################################################################
# Now, given matches, try to construct a time series
# Try just getting the county.

dat <- dbGetQuery(conn, "
  WITH all_matches_uid AS (
    SELECT uuid() AS parcel_uuid, *
    FROM all_matches
  )
  SELECT
    all_matches_uid.parcel_uuid,
    2022 AS year,
    r22.COUNTY AS county,
    r22.SYMB_CLASS AS class
  FROM raw_2022 r22
  JOIN all_matches_uid
    ON r22.UniqueID = all_matches_uid.uniqueid_2022
  UNION ALL
  SELECT
    all_matches_uid.parcel_uuid,
    2023 AS year,
    r23.COUNTY AS county,
    r23.SYMB_CLASS AS class
  FROM raw_2023 r23
  JOIN all_matches_uid
    ON r23.UniqueID = all_matches_uid.uniqueid_2023
  ") |> tibble::tibble()

# TODO: Modify the `all_matches` table to a processed version that:
#   1. Adds a uuid (instead of CTE above).
#   2. Gets the st_intersection of all the geometries.
#
# Consider something like:
# -- If you have geometries in a list column
# WITH geoms AS (
#     SELECT [geom1, geom2, geom3, geom4] AS geom_list
# )
# SELECT list_reduce(
#     geom_list,
#     (x, y) -> ST_Intersection(x, y)
# ) AS intersection
# FROM geoms;

# merges <- dbGetQuery(
#   conn,
#   "SELECT * FROM merge_2023_2022
#   ORDER BY uniqueid_2022, uniqueid_2023
#   "
# ) |>
#   tibble::tibble()

stop("done")

unmatched_2022 <- duckspatial::ddbs_read_vector(conn, "unmatched_2022")

# UniqueID: First 2 digits correspond to the county.
# E.g., All Solano county start with 48; San Bernardino starts with 36.
#
# The remaining 5 digits are the within-county unique identifier.
#
# UniqueIDs are generally preserved across years. When new parcels are added,
# the IDs are appended to the end of the sequence for that county.

# Some examples (2022 -> 2023)
#   - 4801116 => 4801116 : same but shrank slightly
#   - 4800828 => 4800828 : same but grew slightly
#   - 4800301 => 4806383 : merge; grew by 2x
#   - 4800736 => 4806383 : merge; grew by 3-4x
#   - 4800479 => 4800479, 4800514 : __479 shrank slightly; __514 is a superset??
#   - 4806138 => 4806138, 4806519 : split
#   - 4805472 => 4805472, 4806520 : split
#   - 4800425 => 4806384 : merge? grew by 3-4x
#   - 4800694 => 4806384 : grew slightly (merge?)

um <- dbGetQuery(conn, "
  SELECT * FROM unmatched_2022 JOIN unmatched_2023 ON
  unmatched_2022.UniqueID = unmatched_2023.UniqueID
  ")
colnames(um) <- make.unique(colnames(um))

tibble(um) |>
  filter(UniqueID == "6000841") |>
  glimpse()

tibble(um) |>
  mutate(
    acre_diff = (ACRES - ACRES.1),
    acre_ratio = acre_diff / ACRES
  ) |>
  select(UniqueID, acre_diff, acre_diff) |>
  arrange(desc(abs(acre_diff)))

um |>
  select(UniqueID, UniqueID.1, ACRES, ACRES.1, COUNTY, COUNTY.1) |>
  head()

idx <- 3
id <- unmatched_2022[["UniqueID"]][[idx]]
dbExecute(conn, glue::glue("
  CREATE OR REPLACE TABLE test_feature AS
  SELECT raw_2023.*
  FROM raw_2023
  JOIN raw_2022 ON ST_Intersects(raw_2022.geom, raw_2023.geom)
  WHERE raw_2022.UniqueID = {id}
  "
))
test_23 <- duckspatial::ddbs_read_vector(conn, "test_feature")
test_22 <- unmatched_2022 |>
  filter(UniqueID == !!id)
print(as.data.frame(test_22[c("UniqueID", "ACRES", "COUNTY")]))
print(as.data.frame(test_23[c("UniqueID", "ACRES", "COUNTY")]))
print(dbGetQuery(conn, glue::glue("SELECT UniqueID, ACRES, COUNTY FROM raw_2023 WHERE UniqueID")))

stop("again")

################################################################################

dbExecute(conn, glue::glue("
  CREATE OR REPLACE TABLE spatial_overlaps AS
  SELECT
    raw_2022.UniqueID AS uniqueid_2022,
    raw_2023.UniqueID AS uniqueid_2023,
    ST_Area(ST_Intersection(raw_2022.geom, raw_2023.geom)) AS overlap_area,
    ST_Area(ST_Intersection(raw_2022.geom, raw_2023.geom))
      / ST_Area(raw_2022.geom) AS pct_2022,
    ST_Area(ST_Intersection(raw_2022.geom, raw_2023.geom))
      / ST_Area(raw_2023.geom) AS pct_2023
  FROM raw_2022 JOIN raw_2023 ON ST_Intersects(raw_2022.geom, raw_2023.geom)
  -- Exclude exact matches
  WHERE NOT EXISTS (
    SELECT 1 FROM exact_matches em
    WHERE em.uniqueid_2022 = raw_2022.uniqueid
    AND em.uniqueid_2023 = raw_2023.uniqueid
  )
  AND ST_Area(ST_Intersection(raw_2022.geom, raw_2023.geom))
    / ST_Area(raw_2022.geom) > 0.1
  "))

m2023_2022 <- dbGetQuery(conn, "
  SELECT 
    COALESCE(t1.UniqueID, t2.UniqueID) AS UniqueID,
    CASE 
        WHEN t1.UniqueID IS NOT NULL AND t2.UniqueID IS NOT NULL THEN 'Both'
        WHEN t1.UniqueID IS NOT NULL THEN 'Only Table1'
        WHEN t2.UniqueID IS NOT NULL THEN 'Only Table2'
    END AS presence
  FROM ca_2022 t1
  FULL OUTER JOIN ca_2023 t2 ON t1.UniqueID = t2.UniqueID
  ") |>
  tibble::as_tibble()

dbGetQuery(conn, "SELECT COUNT(*) from ca_2022")
dbGetQuery(conn, "SELECT COUNT(*) from ca_2023")

m2023_2022 |>
  count(presence)

dat <- dbGetQuery(conn, "SELECT * FROM u2023")

dbExecute(conn, "
  CREATE TABLE ov_2020_2021 AS
  SELECT
  ST_Intersection(y2020.geom, y2021.geom) AS geom,
  y2020.UniqueID,
  y2021.UniqueID
  FROM raw_2020 y2020, raw_2021 y2021
  WHERE ST_Intersects(y2020.geom, y2021.geom)
  "
)

# ``"
# UNION ALL
#   SELECT
#     ST_Difference(
#       y2020.geom,
#       (
#         SELECT
#         ST_Union_Agg(y2021.geom) FROM raw_2021
#         WHERE ST_Intersects(y2020.geom, y2021.geom)
#       )
#     ) AS geom,
#     y2020.UniqueID
#   FROM raw_2020 y2020, raw_2021 y2021
#   UNION ALL
#   SELECT
#     ST_Difference(
#       y2021.geom,
#       (
#         SELECT
#         ST_Union_Agg(y2020.geom) FROM raw_2020
#         WHERE ST_Intersects(y2021.geom, y2020.geom)
#       )
#     ) AS geom,
#     y2021.UniqueID
#   FROM raw_2020 y2020, raw_2021 y2021
#   "
# )

# All lines
dbExecute(conn, "
  CREATE TABLE all_lines AS
  SELECT uuid() as id, UniqueId, ST_Boundary(geom) as geom FROM raw_2023
  UNION ALL
  SELECT uuid() as id, UniqueID, ST_Boundary(geom) as geom FROM raw_2022
  UNION ALL
  SELECT uuid() as id, UniqueID, ST_Boundary(geom) as geom FROM raw_2021
  UNION ALL
  SELECT uuid() as id, UniqueID, ST_Boundary(geom) as geom FROM raw_2020
  "
)

dbExecute(conn, "
  CREATE TABLE vertices AS
  SELECT
    row_number() OVER () as pt_id,
    id,
    UNNEST(ST_Dump(ST_Points(geom))).geom AS pt
  FROM all_lines
  "
)

dbExecute(conn, "
  CREATE TABLE segments AS
  SELECT
    ST_MakeLine(pt, lead(pt) OVER (PARTITION BY id ORDER BY pt_id)) as geom
  FROM vertices
  QUALIFY lead(pt) OVER (PARTITION BY id ORDER BY pt_id) IS NOT NULL
  "
)

dbExecute(conn, "
  CREATE TABLE unique_segments AS
  SELECT DISTINCT to_binary(geom) as bin_geom FROM segments
  "
)

# Break lines at every intersection
# dbExecute(conn, "
#   CREATE TABLE noded_lines AS
#   SELECT ST_Union_Agg(geom) as geom
#   FROM all_lines
#   "
# )
# Convert all_lines to their constituent points.
dbExecute(conn, "
  CREATE TABLE vertices AS
  SELECT
    id,
    row_number() OVER() as pt_id,
    ST_PointN(geom, CAST(s.i AS INTEGER)) as pt,
    FROM all_lines,
    LATERAL generate_series(1, ST_NPoints(geom)) AS s(i)
  "
)

# Unique segments
dbExecute(conn, "
  CREATE TABLE unique_segments AS
  SELECT DISTINCT geom FROM segments
  "
)

# Polygonize lines (create unique, nonoverlapping features)
dbExecute(conn, "
    CREATE TABLE harmonized AS
    SELECT
      row_number() OVER () AS global_id,
      geom
    FROM (
      SELECT (ST_Dump(ST_Polygonize(geom))).geom as geom
      FROM noded_lines
    )
  "
)

read_landiq <- function(fname) {
  dat <- read_sf(fname)

  # Fix invalid geometries
  dat_is_valid <- st_is_valid(dat)
  dat_invalid <- dat[!dat_is_valid, ]
  dat_fixed <- st_make_valid(dat_invalid)
  dat_valid <- bind_rows(dat[dat_is_valid,], dat_fixed)

  # Example ROI from central CA (point + 5 km buffer)
  # https://www.google.com/maps/@36.4117978,-119.3795406,9075m
  test_point <- st_point(rev(c("lat" = 36.426029, "lon" = -119.380316))) |>
    st_sfc(crs = 4326)
  test_roi <- st_buffer(test_point, dist = 1000 * 5, nQuadSegs = 6)
  roi_trans <- test_roi |>
    st_transform(st_crs(dat)) |>
    st_make_valid()
  dat_sub <- dat_valid |>
    st_filter(roi_trans)
  dat_sub
}

d2023 <- read_landiq(y2023)
d2023 <- read_landiq(y2023)


library(ggplot2)
ggplot(dat_sub) +
  aes(color = 1) +
  geom_sf()

# y2022 <- file.path(
#   rootdir,
#   "i15_Crop_Mapping_2022_Provisional_SHP",
#   "i15_Crop_Mapping_2022_Provisional.shp"
# )
