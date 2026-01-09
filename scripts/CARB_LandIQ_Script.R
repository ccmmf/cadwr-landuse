### Script for checking out CARB data - LandIQ layers

####---- Libraries ----####
#install.packages("librarian")
#remotes::install_github("rspatial/terra")
librarian::shelf(terra, sf, tidyverse)

####---- Load Data ----####
setwd("/projectnb/dietzelab/malmborg/CARB/")  # set working directory to CARB

# as a function: ----
#' @param base_dir = 
#' @param year = year data were collected
#' @param sf = TRUE > open as simple feature or FALSE > open as spatvector
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

#cropmap_spv <- shapefile_grab(shp_home, 2016, sf = FALSE)
#join_16_18 <- st_read(paste0(shp_home, "2016_2018_uids_fix/2016_2018_spatial_join.shp"))
# load cropmap for 2016 then:
# landiq_2016_w_uids <- cropmap %>%
#   mutate(UniqueID = join_16_18$UniqueID, .after = DWR_revise)

shp_home <- "LandIQ_shps/"  # where the files live
year <- 2016  # crop data year
cropmap <- shapefile_grab(shp_home, year, sf = TRUE)

####---- Separating out woody crops for sf ----####
#' @param nclass = number of CLASSX columns in data: numeric
#' @param crops = croplands shapefile: sf object
#' @param woodclass = woody classes object: character or character vector
#' @param tclass = character for truck crops class the includes some woody crops: "T" character
#' @param tsub = subclasses that are woody: numeric, see metadata for numbers
grabwood <- function(nclass, crops, woodclass, tclass, tsub){
  if (nclass == 3){
    allwoody <- subset(crops, CLASS1 %in% woodclass 
                       | CLASS2 %in% woodclass
                       | CLASS3 %in% woodclass)
    truckwoody <- subset(crops, CLASS1 == tclass & SUBCLASS1 == tsub
                         | CLASS2 == tclass & SUBCLASS2 == tsub
                         | CLASS3 == tclass & SUBCLASS3 == tsub) 
    #woodycrops <- rbind(allwoody, truckwoody)
  }
  if (nclass == 4){
    allwoody <- subset(crops, CLASS1 %in% woodclass 
                       | CLASS2 %in% woodclass
                       | CLASS3 %in% woodclass
                       | CLASS4 %in% woodclass)
    truckwoody <- subset(crops, CLASS1 == tclass & SUBCLASS1 == tsub
                         | CLASS2 == tclass & SUBCLASS2 == tsub
                         | CLASS3 == tclass & SUBCLASS3 == tsub
                         | CLASS4 == tclass & SUBCLASS4 == tsub) 
    woodycrops <- rbind(allwoody, truckwoody)
  }
  rbind(allwoody, truckwoody)
}

woody <- c("D", "C", "V")  # woody classes in 2018
truck <- c("T")  # truck class for grabbing bush berries
tcrop <- c(19, 28)   # subclass for bush berries, blueberries in truck crops class
# note: main (ie summer season) crop class is in CLASS2 column, SUBCLASS2 for subclass re: LandIQ 2018 metadata
woodycrops <- grabwood(4, cropmap, woody, truck, tcrop)

####---- grabbing crops generally ----####
#' @param nclass = number of CLASSX columns in data: numeric
#' @param crops = croplands shapefile: sf object
#' @param cropclass = woody classes object: character or character vector
grabcrops <- function(nclass, crops, cropclass){
  if (nclass == 3){
    allcrop <- subset(crops, CLASS1 %in% cropclass 
                       | CLASS2 %in% cropclass
                       | CLASS3 %in% cropclass)
  }
  if (nclass == 4){
    allcrop <- subset(crops, CLASS1 %in% cropclass 
                       | CLASS2 %in% cropclass
                       | CLASS3 %in% cropclass
                       | CLASS4 %in% cropclass)
  }
  return(allcrop)
}

# cropclasses <- c("P", "G") # grass, hay, grain crops
# gcrop <- unique(cropmap$CROPTYP2[grep("^G", cropmap$CROPTYP2)]) #croptypes for grain/hay crops
# pcrop <- unique(cropmap$CROPTYP2[grep("^P", cropmap$CROPTYP2)]) #croptypes for pasture

# identify hay crops: G6 = miscellaneous grain and hay, G7 = mixed grain and hay
haycrops <- c("G6", "G7") # also P3 is mixed pasture, P4 is native pasture...
# hay <- subset(cropmap, CROPTYP1 %in% haycrops|
#                 CROPTYP2 %in% haycrops|
#                 CROPTYP3 %in% haycrops)
cols <- c("CROPTYP1", "CROPTYP2", "CROPTYP3")
rowcrops <- c("G1", "G2", "G3",  # 1) barley, 2) wheat, 3) oats,
              "F", "P", "T", "P7", "T12",
              unique(cropmap$CROPTYP2[grep("^F", cropmap$CROPTYP2)]), # field crops
              unique(cropmap$CROPTYP2[grep("^P", cropmap$CROPTYP2)]), # pasture crops
              unique(cropmap$CROPTYP2[grep("^T", cropmap$CROPTYP2)])) # truck crops

### Version for the crop type columns, not classes:
#' @param nclass = number of CROPTYPX columns in data: numeric
#' @param crops = croplands shapefile: sf object
#' @param cropclass = woody classes object: character or character vector
grabcrops <- function(nclass, crops, croptype){
  if (nclass == 3){
    allcrop <- subset(crops, CROPTYP1 %in% croptype 
                      | CROPTYP2 %in% croptype
                      | CROPTYP3 %in% croptype)
  }
  if (nclass == 4){
    allcrop <- subset(crops, CROPTYP1 %in% croptype 
                      | CROPTYP2 %in% croptype
                      | CROPTYP3 %in% croptype
                      | CROPTYP4 %in% croptype)
  }
  return(allcrop)
}

#hay <- grabcrops(3, cropmap, haycrops)
#hay <- grabcrops(4, cropmap, haycrops)
#row <- grabcrops(3, cropmap, rowcrops)
row <- grabcrops(4, cropmap, rowcrops)

####---- centroids ----####
## generalized version:
#' @param crops = woody crop sf object from grabcrops
#' @param year = crop data year
centr <- function(crops, year){
  crops <- st_make_valid(crops) # make valid
  crops <- st_transform(crops, 3857)
  cents <- st_centroid(crops)  # find centroid
  cents <- st_transform(cents, 3857)  # make same projection
  centpts <- st_coordinates(cents)  # get coordinates from centroids
  crops$centx <- centpts[,'X']  # add columns for coordinates to shapefile
  crops$centy <- centpts[,'Y']
  crops$year <- year  # add a column for data year
  crops
}

# hay centroids:
crops <- centr(cropmap, year)
#hay <- centr(hay, year)
#row <- centr(row, year)
# save hay layer
#crop2016 <- crops
#hay2023 <- hay
#row2023 <- row

## woody crop versions:----
#' #' @param crops = woody crop sf object from grabwood function
#' #' @param year = crop data year
#' centr <- function(crops, year){
#'   cents <- st_centroid(crops)
#'   cents <- st_transform(cents, 3857)
#'   centpts <- st_coordinates(cents)
#'   woodycrops$centx <- centpts[,'X']
#'   woodycrops$centy <- centpts[,'Y']
#'   woodycrops$year <- year
#'   woodycrops
#' }
#' #sf_use_s2(FALSE)
#' woodycrops <- centr(woodycrops, year)
#' head(woodycrops)
#' woodycrops_2016 <- woodycrops

####---- Making one big shapefile ----####
## 2016
# checking overlap between 2016 and 2018
# make geometries valid:
woodycrops_2016 <- st_make_valid(woodycrops_2016)
woodycrops_2018 <- st_make_valid(woodycrops_2018)

# make a union
#test <- st_union(woodycrops_2016, woodycrops_2018)

# # extract things we need:
# names(woodycrops_2016)
# wc16 <- woodycrops_2016[,"geometry"]         # polygon geometry data
# wc16$lat <- woodycrops_2016$centy            # centroid lat
# wc16$lon <- woodycrops_2016$centx            # centroid lon
# wc16$acres <- woodycrops_2016$Acres          # acreage
# wc16$county <- woodycrops_2016$County        # county
# wc16$multiuse <- woodycrops_2016$MULTIUSE    # multiuse code: S = single, M = mult?, D = double

# class columns:
#wc16 <- cbind(wc16, woodycrops_2016$CROPTYP1, woodycrops_2016$CROPTYP2, woodycrops_2016$CROPTYP3)
  
# dealing with CLASS/CROPTYP columns:
# samp <- sample(1:nrow(woodycrops_2016), 100)
# test <- woodycrops_2016[samp,]
# num <- vector()
# classes <- c(woody, "T")
# for (i in 1:nrow(test)){
#   a <- woodycrops_2016[i, c("CLASS1", "CLASS2", "CLASS3")] %in% classes
#   num[i] <- which(a == TRUE)
# }


####---- saving as shapefiles ----####
# # drop unintentionally created z dimension:
# woodycrop <- st_zm(woodycrops_2023, drop=T, what='ZM')
# # write to new shapefile:
# st_write(woodycrop, "LandIQ_shps/woodycrops/woodycrops2023.shp")

#hay <- st_zm(hay2023, drop=T, what='ZM')
crops <- st_zm(crops, drop = T, what = "ZM")
#st_write(hay, "LandIQ_shps/haycrops/hay2023.shp")
st_write(crops, "LandIQ_shps/allcrops/crops2023.shp")

#### archive #####
## single files version: ----
shp_folder <- "i15_Crop_Mapping_"
year <- 2016  # year you want to load
shp_end <- "_SHP" # end of folder
filepath <- paste0(shp_home, shp_folder, as.character(year), shp_end, "/")
shpfile <- paste0(filepath, shp_folder, as.character(year), ".shp")  # make filepath and file name for shapefile

cropmap <- vect(shpfile)  # load shapefile
names(cropmap)

# as list of shapefiles: ----
filelist <- list.files(shp_home, pattern = "^i15") # all shapefile files
shps <- list()  # empty list to populate
for (i in 1:length(filelist)){
  files <- list.files(paste0(shp_home,filelist[i]), pattern = ".shp")  # open file containing shapefile
  file <- paste0(shp_home, filelist[i],"/", files[1])  # grab shapefile name
  shps[[i]] <- vect(file)  # add shapefile to shapefile list
}

####---- Separating out columns with woody crops for spatvectors ----####
### 2016 -----
# woody crop list:
#grep("^Cr",names(cropmap))
# cropcol <- names(cropmap[[grep("^Cr", names(cropmap))]])
# col <- grep("^Cr", names(cropmap))

# woody <- c("Cherries", "Almonds", "Plums, Prunes and Apricots", "Walnuts", "Citrus",
#            "Miscellaneous Deciduous", "Pears", "Olives", "Apples", "Pistachios",
#            "Peaches/Nectarines", "Pomegranates", "Bush Berries", "Miscellaneous Subtropical Fruits")
# woodycrops <- subset(cropmap, subset = cropmap$Crop2016 %in% woody)

# #would love to be able to subset with replaceable object after the $ operator, but I cannot figure out how to do that. Tried several things:
# test <- subset(cropmap, subset = cropmap$as.factor(cropcol) %in% woody)
# test <- subset(cropmap, subset = cropmap$as.name(cropcol) %in% woody)
# test <- subset(cropmap, subset = cropmap@cropcol %in% woody)
# test <- subset(cropmap, subset = as.character(cropmap[[col]]) %in% woody)
# note: ultimately doesn't matter since the datasets use different classifications each year, so subsetting not repeatable

woody <- c("D", "C", "V")  # woody classes
truck <- c("T")  # truck class for grabbing bush berries
tcrop <- c(19, 28)   # subclass for bush berries, blueberries in truck crops class
# note: main (ie summer season) crop class is in CLASS2 column, SUBCLASS2 for subclass re: LandIQ 2018 metadata

allwoody <- subset(cropmap, subset = cropmap$CLASS1 %in% woody 
                   | cropmap$CLASS2 %in% woody
                   | cropmap$CLASS3 %in% woody)
truckwoody <- subset(cropmap, subset = cropmap$CLASS1 == truck & cropmap$SUBCLASS1 == tcrop
                     | cropmap$CLASS2 == truck & cropmap$SUBCLASS2 == tcrop
                     | cropmap$CLASS3 == truck & cropmap$SUBCLASS3 == tcrop) 
woodycrops <- rbind(allwoody, truckwoody)
  # only up to CLASS3
### 2018-202X -----
woody <- c("D", "C", "V")  # woody classes in 2018
truck <- c("T")  # truck class for grabbing bush berries
tcrop <- c(19, 28)   # subclass for bush berries, blueberries in truck crops class
# note: main (ie summer season) crop class is in CLASS2 column, SUBCLASS2 for subclass re: LandIQ 2018 metadata

# allwoody <- subset(cropmap, subset = cropmap$CLASS2 %in% woody)  # woody crops with all subclasses
# truckwoody <- subset(cropmap, subset = cropmap$CLASS2 == truck & cropmap$SUBCLASS2 == tcrop)  # bush berries from truck crops class
# #woodycrops <- rbind(allwoody, truckwoody)
## ^ for woody crops in CLASS2 (main crops), below: code for including multiuse plots

allwoody <- subset(cropmap, subset = cropmap$CLASS1 %in% woody 
                   | cropmap$CLASS2 %in% woody
                   | cropmap$CLASS3 %in% woody
                   | cropmap$CLASS4 %in% woody)
truckwoody <- subset(cropmap, subset = cropmap$CLASS1 == truck & cropmap$SUBCLASS1 == tcrop
                     | cropmap$CLASS2 == truck & cropmap$SUBCLASS2 == tcrop
                     | cropmap$CLASS3 == truck & cropmap$SUBCLASS3 == tcrop
                     | cropmap$CLASS4 == truck & cropmap$SUBCLASS4 == tcrop) 
woodycrops <- rbind(allwoody, truckwoody)


# allwoody <- subset(cropmap, CLASS1 %in% woody 
#                    | CLASS2 %in% woody
#                    | CLASS3 %in% woody)
# truckwoody <- subset(cropmap, CLASS1 == truck & SUBCLASS1 == tcrop
#                      | CLASS2 == truck & SUBCLASS2 == tcrop
#                      | CLASS3 == truck & SUBCLASS3 == tcrop) 
# woodycrops <- rbind(allwoody, truckwoody)

### Centroids:----
# #attrtab <- as.data.frame(cropmap) # attribute table
# cents <- centroids(woodycrops)  # compute centroids - wanted to do inside = TRUE to confirm they are inside the polygons, but this version does not support?
# #centsdf <- as.data.frame(cents)
# centpts <- as.data.frame(geom(cents)) # extracting coordinates from centroids
# #attrtab$centx <- centpts$x  # add them to the polygon attribute table
# #attrtab$centy <- centpts$y
# woodycrops$centx <- centpts$x  # add centroid lat lon to crop data
# woodycrops$centy <- centpts$y

# # make new shapefile with centroids data
# outfile <- paste0(shp_home, "woodycrops_","wcent_",as.character(year),".shp")
# writeVector(woodycrops, outfile, overwrite = TRUE)