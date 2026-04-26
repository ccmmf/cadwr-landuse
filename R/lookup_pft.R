#' Look up PFT for crops in cadwr_pfts.csv
#'
#' @param crop Either a character vector of crop names matched
#'   case insensitively against `subclass_name`, or a data frame with
#'   `class` and `subclass` columns for exact LandIQ code matching
#' @param pecan If TRUE, attach a derived `pecan_pft` column using a
#'   simple default rule: `woody` -> `temperate.deciduous`,
#'   `row`/`rice`/`hay` -> `grass`, non-crop -> `soil`. Off by default.
#'   Projects with their own PFT registry should derive their own column
#'   instead of relying on this default.
#' @param table_path Path to cadwr_pfts.csv. Defaults to
#'   `data/cadwr_pfts.csv` relative to the working directory.
#'
#' @return A tibble. Character input returns one row per match; the same
#'   subclass_name can appear under multiple class/subclass pairs in the
#'   table (e.g. `beans`, `tomatoes`), so multi-row results are normal.
#'   Data frame input returns one row per input row, preserving order.
#' @export
lookup_pft <- function(crop, pecan = FALSE, table_path = "data/cadwr_pfts.csv") {
  pft_map <- readr::read_csv(
    table_path,
    show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )

  required <- c("class", "subclass", "subclass_name", "pft_group")
  missing_cols <- setdiff(required, names(pft_map))
  if (length(missing_cols) > 0) {
    stop("table missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  if (isTRUE(pecan)) {
    pft_map$pecan_pft <- dplyr::case_when(
      pft_map$pft_group == "woody" ~ "temperate.deciduous",
      pft_map$pft_group %in% c("row", "rice", "hay") ~ "grass",
      is.na(pft_map$pft_group) ~ "soil",
      TRUE ~ NA_character_
    )
  }

  if (is.character(crop)) {
    if (length(crop) == 0) {
      return(pft_map[0, , drop = FALSE])
    }
    crop_clean <- tolower(trimws(crop))
    crop_clean <- crop_clean[!is.na(crop_clean)]
    if (length(crop_clean) == 0) {
      return(pft_map[0, , drop = FALSE])
    }
    map_clean <- tolower(pft_map$subclass_name)

    result <- pft_map[map_clean %in% crop_clean, , drop = FALSE]

    missed <- setdiff(crop_clean, map_clean)
    missed <- missed[!is.na(missed)]
    if (length(missed) > 0) {
      warning("no match for: ", paste(missed, collapse = ", "))
    }

    matched_counts <- table(map_clean[map_clean %in% crop_clean])
    multi <- names(matched_counts[matched_counts > 1])
    if (length(multi) > 0) {
      warning("multiple class/subclass matches for: ", paste(multi, collapse = ", "))
    }

    return(result)
  }

  if (is.data.frame(crop)) {
    if (!all(c("class", "subclass") %in% names(crop))) {
      stop("data frame input must have `class` and `subclass` columns")
    }
    return(dplyr::left_join(crop, pft_map, by = c("class", "subclass")))
  }

  stop("`crop` must be a character vector or a data frame with class and subclass columns")
}
