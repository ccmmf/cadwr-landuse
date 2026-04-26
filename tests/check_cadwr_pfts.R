#!/usr/bin/env Rscript

# Schema validation for data/cadwr_pfts.csv. Run from repo root via:
#   Rscript tests/check_cadwr_pfts.R
#
# Checks structure, not specific value mappings. Edits to a crop's
# pft_group should not break this check.

dat <- readr::read_csv(
  "data/cadwr_pfts.csv",
  show_col_types = FALSE,
  col_types = readr::cols(.default = readr::col_character())
)

required <- c("class_name", "class", "subclass", "subclass_name", "pft_group", "notes")
missing_cols <- setdiff(required, names(dat))
stopifnot(length(missing_cols) == 0)

stopifnot(nrow(dat) > 0)

# class is mandatory; every row must have one
stopifnot(all(!is.na(dat$class)))

# (class, subclass) is the join key and must be unique
key <- paste(dat$class, dat$subclass, sep = "|")
stopifnot(!any(duplicated(key)))

# pft_group values from a controlled set; NA is allowed for non cropped rows
allowed <- c("row", "woody", "rice", "hay")
unexpected <- setdiff(unique(dat$pft_group[!is.na(dat$pft_group)]), allowed)
stopifnot(length(unexpected) == 0)

cat("schema check passed: ", nrow(dat), " rows, ", ncol(dat), " columns\n", sep = "")
