# Script for looking at union data from QGIS

####---- Libraries ----####
#install.packages("librarian")
#remotes::install_github("rspatial/terra")
librarian::shelf(terra, sf, tidyverse)

####---- Load Data ----####
setwd("/projectnb/dietzelab/malmborg/CARB/")  # set working directory to CARB

# 2016 to 2018 union from qgis
# file <- "LandIQ_shps/unions/union_wc_16_wc18_fixed.shp"
# woodshp <- st_read(file)

# load all crop layers:
shp_home <- "LandIQ_shps/allcrops/"  # where the files live
year <- 2019 # crop data year
crop2019 <- st_read(paste0(shp_home, "crops", as.character(year), ".shp"))


test # make a list with all hay members:
croplist <- list(crop2018, crop2019, crop2020, crop2021, crop2022, crop2023)
#haylist <- list(hay2018, hay2019, hay2020, hay2021, hay2022, hay2023) # objects made in LandIQ script
#rowlist <- list(row2018, row2019, row2020, row2021, row2022, row2023)
years <- c(2018, 2019, 2020, 2021, 2022, 2023)

# columns to save:
cols <- c("UniqueID", "MULTIUSE", "CROPTYP1", "CROPTYP2", "CROPTYP3", "CROPTYP4", 
          "PCNT1", "PCNT2", "PCNT3", "PCNT4","COUNTY", "ACRES", "geometry", "year")
# columns for binding to make all years set:
bindcols <- c("MULTIUSE", "CROPTYP1", "CROPTYP2", "CROPTYP3", "CROPTYP4", 
              "PCNT1", "PCNT2", "PCNT3", "PCNT4","COUNTY", "ACRES")
# column names to not exceed shapefile saving 10 character limit
namecols <- c("MLTU", "CT1", "CT2", "CT3", "CT4", "PC1", "PC2", "PC3", "PC4", "CNTY", "ACR")

#'@param croplist = the list of individual year crop layers
#'@param cols = character vector of columns wanted for earliest year of the bind
#'@param bindcols = character vector of column names wanted from subsequent year layers
#'@param namecols = new names to not exceed 10 character limit on column names
#'@param years = years of the shapefiles
by_uid <- function(croplist, cols, bindcols, namecols, years){
  # find the crop layers across years that have the same unique ID
  new_uids <- croplist[[1]]$UniqueID[croplist[[1]]$UniqueID %in% croplist[[2]]$UniqueID &
                                       croplist[[1]]$UniqueID %in% croplist[[3]]$UniqueID &
                                       croplist[[1]]$UniqueID %in% croplist[[4]]$UniqueID &
                                       croplist[[1]]$UniqueID %in% croplist[[5]]$UniqueID &
                                       croplist[[1]]$UniqueID %in% croplist[[6]]$UniqueID]
  all_years_set <- croplist[[1]][croplist[[1]]$UniqueID %in% new_uids,]
  
  # make the base (first year of all year set):
  crop_base <- all_years_set[,cols]
  
  # make new columns for binding for subsequent years:
  bindlist <- list()
  for (i in 2:length(years)){
    newcols <- vector()
    for (j in namecols){
      newcols[j] <- paste0(as.character(years[i]), "_" , j)
    }
    # make the new layer
    new_crop <- croplist[[i]][croplist[[i]]$UniqueID %in% new_uids, bindcols]
    cropcols <- st_drop_geometry(new_crop)
    colnames(cropcols) <- newcols
    bindlist[[i-1]] <- cropcols
  }
  crop_new <- dplyr::bind_cols(crop_base, bindlist)
  return(crop_new)
}

# do it for hay!
#hay_all <- by_uid(haylist, cols, bindcols, namecols, years)
#row_all <- by_uid(rowlist, cols, bindcols, namecols, years)
crops_all <- by_uid(croplist, cols, bindcols, namecols, years)

# make valid and save:
hay_all_valid <- st_make_valid(hay_all)
row_all_valid <- st_make_valid(row_all)
crops_all_valid <- st_make_valid(crops_all)
#woody_new_valid <- st_zm(woody_new_valid, drop=T, what='ZM')
#st_write(hay_all_valid, "LandIQ_shps/unions/hay_crops_2018-2023_same_uids_try1.shp")
#st_write(row_all_valid, "LandIQ_shps/unions/row_crops_2018-2023_same_uids_try1.shp")
st_write(crops_all_valid, "LandIQ_shps/unions/all_crops_2018-2023_same_uids_try5.shp")




### ARCHIVE ### for woody crops layers, adapted for all crops above -----
# find unique ID values common across all years
new_uids <- woodycrops_2018$UniqueID[woodycrops_2018$UniqueID %in% woodycrops_2019$UniqueID &
                                       woodycrops_2018$UniqueID %in% woodycrops_2020$UniqueID &
                                       woodycrops_2018$UniqueID %in% woodycrops_2021$UniqueID &
                                       woodycrops_2018$UniqueID %in% woodycrops_2022$UniqueID &
                                       woodycrops_2018$UniqueID %in% woodycrops_2023$UniqueID]

all_years_set <- woodycrops_2018[woodycrops_2018$UniqueID %in% new_uids,] # 2018 with all unique uids across years

# columns to save
cols <- c("UniqueID", "MULTIUSE", "CROPTYP1", "CROPTYP2", "CROPTYP3", "CROPTYP4", 
          "PCNT1", "PCNT2", "PCNT3", "PCNT4","COUNTY", "ACRES", "geometry", "year")

# columns for binding to make all years set:
bindcols <- c("MULTIUSE", "CROPTYP1", "CROPTYP2", "CROPTYP3", "CROPTYP4", 
              "PCNT1", "PCNT2", "PCNT3", "PCNT4","COUNTY", "ACRES")
# identify columns with years:
newcols <- vector()
for (i in bindcols){
  newcols[i] <- paste0("2019_", i)
}


#woody_base <- all_years_set[,cols] # 2018 data
new_wood <- woodycrops_2023[woodycrops_2023$UniqueID %in% new_uids, bindcols] #get next year's data
wood_cols <- st_drop_geometry(new_wood)
colnames(wood_cols) <- newcols 

# note: when making with 2022 for some reason last row is repeated, checked with duplicated(), dropped before adding to woody_new
#which(duplicated(test$UniqueID) == TRUE)

#woody_new <- cbind(all_years_set[,cols], wood_cols) # first run for 2019 add
woody_new <- cbind(woody_new, wood_cols) # subseqent runs changing for each year

# save it
# excl <- grep("^cent", colnames(woodycrops_2023))
# all_years_set <- woodycrops_2023[all_years_uids,-excl]
woody_new_valid <- st_make_valid(woody_new)
#woody_new_valid <- st_zm(woody_new_valid, drop=T, what='ZM')
st_write(woody_new_valid, "LandIQ_shps/unions/woody_crops_2018-2023_same_uids_try2.shp")

# checking if all the croptypes remain the same across years:
wc1823 <- st_read("LandIQ_shps/unions/woody_crops_2018-2023_same_uids_try2.shp")
len_u <- vector()
for (i in 1:nrow(wc1823)){
  testrows <- st_drop_geometry(wc1823[i, grep("crop2", names(wc1823))])
  len_u[i]<- nlevels(as.factor(as.matrix(testrows)))
}

# uids <- all_years_set$UniqueID
# a <- woodycrops_2018[woodycrops_2018$UniqueID %in% uids, bindcols]
# b <- woodycrops_2019[woodycrops_2019$UniqueID %in% uids, bindcols]
# c <- woodycrops_2020[woodycrops_2020$UniqueID %in% uids, bindcols]
# d <- woodycrops_2021[woodycrops_2021$UniqueID %in% uids, bindcols]
# e <- woodycrops_2022[woodycrops_2022$UniqueID %in% uids, bindcols]
# f <- woodycrops_2023[woodycrops_2023$UniqueID %in% uids, bindcols]

# fuck! they still don't align


# rename <- c("uniqueid", "2018_muli", "2018crop1", "2018crop2", "2018crop3", "2018crop4", 
#             "2018pct1", "2018pct2", "2018pct3", "2018pct4", "2018county", "2018acres", "2018year", 
#             "2019multi", "2019crop1", "2019crop2", "2019crop3", "2019crop4", "2019pct1", '2019pct2', 
#             "2019pct3", "2019pct4", "2019county", "2019acres", "2020multi", "2020crop1", "2020crop2", 
#             "2020crop3", "2020crop4", "2020pct1", "2020pct2", '2020pct3', "2020pct4", "2020county", 
#             "2020acres", "2021multi", "2021crop1", "2021crop2", "2021crop3", "2021crop4", "2021pct1", 
#             "2021pct2", "2021pct3", "2021pct4", "2021county", "2021acres", "2022multi", "2022crop1", 
#             "2022crop2", "2022crop3", "2022crop4", "2022pct1", "2022pct2", "2022pct3", "2022pct4", 
#             "2022county", "2022acres", "2023multi", "2023crop1", "2023crop2", "2023crop3", "2023crop4", 
#             "2023pct1", "2023pct2", "2023pct3", "2023pct4", "2023county", "2023acres", "geometry")

# thinking about how to do it in R:
# samesies <- which(woodycrops_2016$geometry %in% woodycrops_2018$geometry)
# just16 <- woodycrops_2016[-samesies,]
# 
# samesies2 <- which(woodycrops_2018$geometry %in% woodycrops_2016$geometry)
# just18 <- woodycrops_2018[-samesies2,]

#### working backwards from 2023
# same_22_23 <- which(woodycrops_2022$UniqueID %in% woodycrops_2023$UniqueID)  # which ones are in both
# set_22_23 <- woodycrops_2022[same_22_23,]  # grab the ones that are in both
# not_set_22_23 <- woodycrops_2022[-same_22_23,]  # the ones that are not in 2023
# 
# #same_21_22 <- which(woodycrops_2021$UniqueID %in% woodycrops_2022$UniqueID)  # which ones are in both
# same_set22_21 <- which(woodycrops_2021$UniqueID %in% set_22_23$UniqueID)  # which ones are in in both 2021 and 2022/2023
# #set_21_22 <- woodycrops_2021[same_21_22,]
# same_set_22_21 <- woodycrops_2021[same_set22_21,] 
# #not_set_21_22 <- woodycrops_2021[-same_21_22,]
# 
# same_20_23 <- which(woodycrops_2020$UniqueID %in% same_set_22_21$UniqueID)
# same_set_20_23 <- woodycrops_2020[same_20_23,]
# 
# same_19_23 <- which(woodycrops_2019$UniqueID %in% same_set_20_23$UniqueID)
# same_set_19_23 <- woodycrops_2019[same_19_23,]
# 
# same_18_23 <- which(woodycrops$UniqueID %in% same_set_19_23$UniqueID)
# same_set_18_23 <- woodycrops_2018[same_18_23,]
# 
# same_18_23_a <- which(woodycrops_2018$UniqueID %in% woodycrops_2023$UniqueID)
# same_set_18_23_a <- woodycrops_2023[same_18_23_a,] 

# all_years_uids <- which(woodycrops_2018$UniqueID %in% woodycrops_2023$UniqueID)
# excl <- grep("^cent", colnames(woodycrops_2023))
# all_years_set <- woodycrops_2023[all_years_uids,-excl]
# all_years_set <- st_make_valid(all_years_set)
# #all_years_set <- st_zm(all_years_set, drop=T, what='ZM')
# #st_write(all_years_set, "LandIQ_shps/unions/all_years_uids_try6.shp") 

# fuck! they still don't align
