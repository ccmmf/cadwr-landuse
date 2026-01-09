# Script for harmonizing tests and attempts for CARB data across years

# load libraries
librarian::shelf(tidyverse, terra, sf)

# working directory
setwd("/projectnb/dietzelab/malmborg/CARB")
# load the big CARB dataframe (2016-2023 data)
load("crops_all_years.RData")

# fixing 2016 UniqueIDs 5/15/25
crops_all_fix <- crops_all %>%
  filter(year %in% 2018:2023)

crops_all_years <- bind_rows(df_piv, crops_all_fix)


# adding YRPLANTED to years without
cay_fill <- playing %>%
  group_by(UniqueID) %>% fill(YRPLANTED)  # test version >> works!

crops_all_yrs <- crops_all_years
crops_all <- crops_all_yrs %>%
  group_by(UniqueID) %>% fill(YRPLANTED, .direction = "downup") %>%
  fill(HYDRORGN, .direction = "up")

#save(crops_all, file = "crops_all_years_3.RData")  # saving fixed 2023 provisional and harmonized YR_PLANTED
write.csv(crops_all, file = "/projectnb/dietzelab/ccmmf/LandIQ_data/crops_all_years.csv")
