# Script for joining new years' data to existing shapefiles:

####---- Libraries ----####
#install.packages("librarian")
#remotes::install_github("rspatial/terra")
librarian::shelf(terra, sf, tidyverse, stringr)

####---- Load Data ----####
dir <- "/projectnb/dietzelab/malmborg/CARB/" # where shapefiles load from
setwd(dir)  # set working directory to CARB
getwd()  # check working directory


####---- Adjust new shapefile from LandIQ ----####
# Function for loading shapefiles in: -----
#' @param base_dir = folder where data are located (character)
#' @param year = year data were collected (numeric)
#' @param sf = TRUE -> open as simple feature or FALSE -> open as spatvector (TRUE/FALSE)
shapefile_grab <- function(base_dir, year, sf) {
  filelist <- list.files(base_dir, pattern = as.character(year))  # open files for specified year
  shpfile <- list.files(paste0(base_dir, "/", filelist), pattern = ".shp")  # shapefiles
  file <- paste0(base_dir, "/", filelist, "/", shpfile[1])  # make full filepath
  if (sf == TRUE){
    st_read(file)  # if TRUE - read in as sf (using sf lib)
  } else {
    vect(file)  # if FALSE - read in as spatvector (using terra lib)
  }
}

### Wrapper for CARB shapefile dataframe maker functions:
#' @param crops = crop sf object (sf object, shapefile)
#' @param crs = desired crs (numeric, I have been using 3857)
#' @param year = year of data (numeric; YYYY)
get_CARB_data <- function(crops, crs, year){
  # transform crs, make valid, and find centroids:
  centr <- function(shp, crs, year){
    crops <- st_transform(shp, crs) # change crs
    crops <- st_make_valid(crops) # make valid
    cents <- st_centroid(crops)  # find centroid
    cents <- st_transform(cents, crs)  # make same projection
    centpts <- st_coordinates(cents)  # get coordinates from centroids
    crops$centx <- centpts[,'X']  # add columns for coordinates to shapefile
    crops$centy <- centpts[,'Y']
    crops$year <- year  # add a column for data year
    crops <- st_zm(crops, drop = T, what = "ZM") # correct the extra Z dimension in geometry
    return(crops)
  }
  crop_new <- centr(crops, crs, year)
  
  # grab columns for data frame conversion:
  col_grab <- function(shp){
    id <- grep("^Unique", names(shp))    # UniqueID from LandIQ
    year <- grep("year", names(shp))     # year of data
    lon <- grep("^centx", names(shp))    # centroid lon
    lat <- grep("^centy", names(shp))    # centroid lat
    mult <- grep("^MULT", names(shp))    # multiuse code
    class <- grep("^CLASS", names(shp))  # class code
    sub <- grep("^SUB", names(shp))      # subclass number
    spec <- grep("^SPEC", names(shp))    # special condition code
    sen <- grep("^SEN", names(shp))      # senescing crop
    emer <- grep("^EMER", names(shp))    # emerging crop
    irst <- grep("PA", names(shp))       # irrigation status (from IRR_TYP#PA)
    irty <- grep("PB", names(shp))       # irrigation type (from IRR_TYP#PB)
    pcnt <- grep("^PCN", names(shp))     # percent cover
    adoy <- grep("^ADOY", names(shp))    # adjusted day of year for crops
    yr_pl <- grep("^YR", names(shp))     # year planted
    hy_reg <- grep("^HYD", names(shp))   # hydro region
    reg <- grep("^REG", names(shp))      # region
    cty <- grep("COUNTY", names(shp))    # county
    
    # combine
    cols <- c(id, year, lon, lat,
              mult, class, sub, spec, sen, emer,
              irst, irty, pcnt, adoy, yr_pl,
              hy_reg, reg, cty)
    crops <- shp[,cols]
    return(crops)
  }
  crop_grab <- col_grab(crop_new)
  
  # build data frame from shapefile object:
  crop_clean <- function(shp){
    df <- st_drop_geometry(shp)
    
    # get rid of asterix values, replace 00 percent codes to 100, make number cols numeric:
    df_clean <- df %>% 
      mutate(across(everything(), ~replace(., . == "**", NA))) %>%
      mutate(across(everything(), ~replace(., . == "*", NA))) %>%
      mutate(across(everything(), ~replace(., . == "00", "100"))) %>%
      mutate(across(everything(), as.character))
    
    # make longer:
    # prepare columns for sorting into seasons:
    renamer <- function(df){
      numb <- str_extract(names(df), "[0-9]")
      char <- str_extract_all(names(df), "[:alpha:]+", simplify = TRUE)
      ch <- vector()
      for (i in 1:nrow(char)){
        ch[i] <- str_c(char[i,], collapse = "")
      }
      newnames <- str_remove(paste(numb, ch, sep = ""), "NA")
      colnames(df) <- newnames
      return(df)
    }
    df_cl <- renamer(df_clean)
    
    # pivoting:
    df_piv <- df_cl %>% 
      pivot_longer(-c(grep("^[a-zA-Z]", names(df_cl))), names_to = c("name"), values_to = "value") %>%
      mutate(type = str_extract(name, "[A-Z]+")) %>%
      mutate(season = str_extract(name, "[0-9]")) %>%
      select(-name) %>% group_by(UniqueID) %>%
      pivot_wider(names_from = type,
                  values_from = value) %>% ungroup() %>%
      mutate(across(c("UniqueID", "year", "SUBCLASS", "PCNT", "ADOY", "season"), as.numeric))
  }
  crops_out <- crop_clean(crop_grab)
  return(crops_out)
}

crs = 3857
year = 2016
crops <- shapefile_grab("LandIQ_shps/", year, sf = TRUE)
new_crops <- get_CARB_data(crops, crs, year)

#crop_df_23 <- new_crops  #note: 2022 and 2023 LandIQ shps have same number of rows
#crop_df_22 <- new_crops
#crop_df_21 <- new_crops
#crop_df_20 <- new_crops
#crop_df_19 <- new_crops
#crop_df_18 <- new_crops
crop_df_16 <- new_crops
crop_df_16 <- df_piv          # ran 05-15-25 for fixing 2016-2018 join
save(crop_df_16, file = "crops_2016_spatial_join.RData")

#if 2016:
crops <- shapefile_grab("LandIQ_shps/", 2016, sf = TRUE)
crops$UniqueID <- 1:nrow(crops) #uids_16 #1:nrow(crops) # didn't work re: pivoting: couldn't do the group_by()
crops$ADOY <- NA
new_crops <- get_CARB_data(crops, 3857, 2016)
crop_df_16 <- new_crops
crop_df_16_match <- new_crops

### harmonizing: -----
## adding columns for 2018-2020 to match more recent years
# identify the columns:
missing_2016 <- setdiff(names(crop_df_23), names(crop_df_16))
missing_2018 <- setdiff(names(crop_df_23), names(crop_df_18))
missing_2019 <- setdiff(names(crop_df_23), names(crop_df_19))
missing_2020 <- setdiff(names(crop_df_23), names(crop_df_20))
# add dummy columns to each set:
for (i in 1:length(missing_2016)){
  col <- missing_2016[i]
  crop_df_16[[col]] <- c(NA)
}
# order the columns:
crop_df_16 <- crop_df_16 %>%
  select(., names(crop_df_23))



# bind rows to make big dataframe:
crops_all_yrs_but_16 <- rbind(crop_df_18, crop_df_19, crop_df_20, crop_df_21, crop_df_22, crop_df_23)
crops_all_yrs <- rbind(crop_df_16, crop_df_18, crop_df_19, crop_df_20, crop_df_21, crop_df_22, crop_df_23)


# finding unique IDs for 2016:
# intersection between 2016 and 2018
test_intersect_16_18 <- st_intersects(test_16, test_18)
# get first value for all with more than one entry:
uids_16 <- vector()
for (i in 1:length(test_intersect_16_18)){
  uids_16[i] <- first(test_intersect_16_18[[i]])
}

# dealing with join:
shp_16_18 <- st_read("LandIQ_shps/join_tests/crop_16_18_join_try2.shp")
# crops_2016 and crop_2018 joining using 2016 centroids:
#grab_with_cents <- crop_2018[cents,]
# join:
test_join <- st_join(crops_2016, left = FALSE, crops_2018["UniqueID"])
# identify rows without duplicates
names <- rownames(test_join) 
dupl <- grep("[[punct:]]", names)
rm_dupl <- test_join[-dupl,]
# intersection with 2016:
#intersection <- st_intersects(crops_2016, rm_dupl)
#i <- st_intersection(crops_2016, crops_2018)
#eq <- st_equals(crops_2016, rm_dupl)
not <- lengths(st_intersects(crops_2016, rm_dupl)) > 0
#c16 <- crops_2016[which(not == TRUE),]
uids <- vector()
for (i in 1:length(not)) {
  if(not[i] == TRUE){
    uids[i] <- rm_dupl[i,]$UniqueID
  } else {
    uids[i] <- NA
  }
  #print(i)
}
crops_2016$UniqueID <- uids

# for (i in 1:nrow(crops_2016)){
#   if(crops_2016[i,]$Acres == rm_dupl[i,]$Acres){
#     uids[i] <- rm_dupl[i,]$UniqueID
#   } else {
#     uids[i] <- NA
#   }
# }


####-----TESTING ZONE-----####
#' ### Computing centroids: -----
#' #' @param crops = woody crop sf object from grabcrops (object)
#' #' @param crs = coordinate reference system (numeric)
#' #' @param year = crop data year (numeric)
#' centr <- function(shp, crs, year){
#'   crops <- st_transform(shp, crs) # change crs
#'   crops <- st_make_valid(crops) # make valid
#'   cents <- st_centroid(crops)  # find centroid
#'   cents <- st_transform(cents, crs)  # make same projection
#'   centpts <- st_coordinates(cents)  # get coordinates from centroids
#'   crops$centx <- centpts[,'X']  # add columns for coordinates to shapefile
#'   crops$centy <- centpts[,'Y']
#'   crops$year <- year  # add a column for data year
#'   crops <- st_zm(crops, drop = T, what = "ZM") # correct the extra Z dimension in geometry
#'   return(crops)
#' }
#' 
#' ### Columns for PEcAn dataframes:
#' #'@param shp = shapefile sf object, 'crops' from centroid comp function
#' #'@param year = year of shapefile data
#' col_grab <- function(shp){
#'   id <- grep("^Unique", names(shp))    # UniqueID from LandIQ
#'   year <- grep("year", names(shp))     # year of data
#'   lon <- grep("^centx", names(shp))    # centroid lon
#'   lat <- grep("^centy", names(shp))    # centroid lat
#'   mult <- grep("^MULT", names(shp))    # multiuse code
#'   class <- grep("^CLASS", names(shp))  # class code
#'   sub <- grep("^SUB", names(shp))      # subclass number
#'   spec <- grep("^SPEC", names(shp))    # special condition code
#'   sen <- grep("^SEN", names(shp))      # senescing crop
#'   emer <- grep("^EMER", names(shp))    # emerging crop
#'   irst <- grep("PA", names(shp))       # irrigation status (from IRR_TYP#PA)
#'   irty <- grep("PB", names(shp))       # irrigation type (from IRR_TYP#PB)
#'   pcnt <- grep("^PCN", names(shp))     # percent cover
#'   adoy <- grep("^ADOY", names(shp))    # adjusted day of year for crops
#'   reg <- grep("^REG", names(shp))      # region
#'   cty <- grep("COUNTY", names(shp))    # county
#'   
#'   # combine
#'   cols <- c(id, year, lon, lat,
#'             mult, class, sub, spec, sen, emer,
#'             irst, irty, pcnt, adoy,
#'             reg, cty)
#'   crops <- shp[,cols]
#'   return(crops)
#' }
#' 
#' ### Clean n' Flip
#' #'@param crops = shapefile from col_grab 
#' crop_clean <- function(shp){
#'   df <- st_drop_geometry(shp)
#'   # # identify columns for converting to numeric:
#'   # nums <- c(grep("^SUB", names(df)),
#'   #           grep("^PCN", names(df)),
#'   #           grep("^ADOY", names(df)))
#'   
#'   # get rid of asterix values, replace 00 percent codes to 100, make number cols numeric:
#'   df_clean <- df %>% 
#'     mutate(across(everything(), na_if, "**")) %>%
#'     mutate(across(everything(), na_if, "*")) %>%
#'     mutate(across(everything(), ~replace(., . == "00", "100"))) %>%
#'     mutate(across(everything(), as.character))
#'   
#'   # make longer:
#'   # prepare columns for sorting into seasons:
#'   renamer <- function(df){
#'     numb <- str_extract(names(df), "[0-9]")
#'     char <- str_extract_all(names(df), "[:alpha:]+", simplify = TRUE)
#'     ch <- vector()
#'     for (i in 1:nrow(char)){
#'       ch[i] <- str_c(char[i,], collapse = "")
#'     }
#'     newnames <- paste(numb, ch, sep = "")
#'     colnames(df) <- newnames
#'     return(df)
#'   }
#'   df_cl <- renamer(df_clean)
#'   
#'   # pivoting:
#'   df_test <- newtest %>% #newtest[,c(1, (grep("CLASS", names(newtest))))] %>%
#'     pivot_longer(-c(grep("^[a-zA-Z]", names(newtest))), names_to = c("name"), values_to = "value") %>%
#'     mutate(type = str_extract(name, "[A-Z]+")) %>%
#'     mutate(season = str_extract(name, "[0-9]")) %>%
#'     select(-name) %>% group_by(UniqueID) %>%
#'     pivot_wider(names_from = type,
#'                 values_from = value) %>% ungroup() %>%
#'     mutate(across(c("UniqueID", "year", "SUBCLASS", "PCNT", "ADOY", "season"), as.numeric))
#'   
#' }







#### ---- Archive ----####
# # columns not collapsed:
# cols <- c(grep("Unique", names(df_clean)),
#           grep("year", names(df_clean)),
#           grep("cent", names(df_clean)),
#           grep("REGION", names(df_clean)),
#           grep("COUNTY", names(df_clean)))

# # identify columns for converting to numeric:
# nums <- c(grep("^SUB", names(df)),
#           grep("^PCN", names(df)),
#           grep("^ADOY", names(df)))

# df_test <- newtest %>%
#   pivot_longer(
#     -c(grep("^[a-zA-Z]", names(newtest))),
#     names_to = c(".value", "season"),
#     names_pattern = "(.)(.)"
#   )

#df_piv <- df_test %>%

# pivot_longer(
#   cols = starts_with("CLASS"),
#   names_to = "season",
#   names_pattern = "(\\d+)",
#   names_transform = as.integer,
#   values_to = "class"
# )

# # Save new shapefile with centroid:
# # file in params for shp file function:
# shp_home <- "LandIQ_shps/"  # where the files live
# year <- 2022  # crop data year
# 
# cropmap <- shapefile_grab(shp_home, year, sf = TRUE)
# crop <- centr(cropmap, crs, year)
# 
# # file = ""
# #st_write(file)

