##### ---------- ><><><><>< ---------- #####
###         P L A Y G R O U N D          ###
##### ---------- ><><><><>< ---------- #####

library(dplyr)

# working directory
setwd("/projectnb/dietzelab/malmborg/CARB")
# load the big CARB dataframe (2016-2023 data)
load("crops_all_years.RData")

# filtering woody and herbaceous:
crops_wood_herb <- crops_all %>%
  filter(CLASS %in% c("D", "C")) %>%
  filter(year == 2018)

field_test <- crops_all %>%
  filter(year == 2018) %>%
  select(UniqueID, year, season, CLASS, PCNT) %>%
  group_by(UniqueID) %>% 
  mutate(total_pcnt = sum(PCNT, na.rm = T))

# playing with harmonization
crop_harm <- crops_all %>%
  filter(year > 2016) %>%
  filter(season == 2) %>%
  select(UniqueID, year, season, CLASS, SUBCLASS, PCNT) %>%
  arrange(UniqueID, year)

parcels <- sample(unique(crop_harm$UniqueID), 10)

crop_harm_samp <- crop_harm[crop_harm$UniqueID %in% parcels,]
