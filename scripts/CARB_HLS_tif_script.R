### Saving all the .nc data as TIFs:

# load libraries
librarian::shelf(dplyr, ncdf4, terra, stringr)

### Set where to load/save the downloaded product
hls_dir <- "/projectnb/dietzelab/malmborg/CARB/HLS_data/"
hls_save <- "/projectnb/dietzelab/malmborg/CARB/HLS_tifs/"
# set it as the working directory
setwd(hls_dir)

# load files:
pheno_2016 <- pheno_ncfiles[grep("_2016", pheno_ncfiles)]
pheno_2017 <- pheno_ncfiles[grep("_2017", pheno_ncfiles)]
pheno_2018 <- pheno_ncfiles[grep("_2018", pheno_ncfiles)]
pheno_2019 <- pheno_ncfiles[grep("_2019", pheno_ncfiles)]

files_samp <- sample(pheno_2016, size = 3)
# open as raster and save as tif:
for (i in 1:length(files_samp)){
  raster <- terra::rast(files_samp[i])
  name <- str_remove(files_samp[i], ".nc")
  raster_project <- terra::project(raster, "+proj=lonlat +datum=WGS84")
  writeRaster(raster_project, paste0(hls_save, name, ".tif"), filetype = "GTiff")
  print(i)
}


tif_test <- terra::rast(paste0(hls_save, "MSLSP_11SLB_2016.tif"))
                        