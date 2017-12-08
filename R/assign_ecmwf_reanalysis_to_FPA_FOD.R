#!/usr/bin/env Rscript
args = commandArgs(trailingOnly=TRUE)
if(length(args)==0){
  args=2003
}

# readFPAFODFireFeatures.R
# execute via command line 
# Rscript --vanilla R/assign_ecoregion_to_FPAFOD.R 2003
################################################################################
# assign_ecmwf_reanalysis_to_FPA_FOD.R

# This script is assigns ecmwf daily weather attributes to FPA-FOD, fire 
# ingition conditions. 

# Assgin:
  # RH
  # T
  # precip, TODO: how much precip in season so far
  # days_since_rain_2003_2016.nc
  # dew point 

library(stringr)
library(maps)
library(ncdf4)

# Load FPA-FOD data, the one with all attributes (ecoregions) assgined.
load("Data/FPA_FOD/FPA_FOD_2003_2013.RData")
nRow     <- dim(FPA_FOD)[1]
fireDate <- FPA_FOD$DISCOVERY_DATE
fireLat  <- FPA_FOD$LATITUDE
fireLon  <- FPA_FOD$LONGITUDE

# NOTE: This only works since all fires are treated as points, and only exist
# NOTE: in the western hemisphere. 
fireLonAdjusted <- fireLon + 360

# Get GFED4s monthly burn area from DM file
ncDir <- "/Volumes/Brey_external/era_interim_nc_daily_merged/"
#ncDir <- "/Volumes/Brey_external/era_interim_nc_daily/"

print("Loading lots of nc data")

nc_file <- paste0(ncDir,"t2m_2003_2016.nc")
nc <- nc_open(nc_file)

# Handle ecmwf time with origin 1900-01-01 00:00:0.0
ecmwf_hours <- ncvar_get(nc, "time")
ecmwf_seconds <- ecmwf_hours * 60^2

# make time useful unit
t0 <- as.POSIXct("1900-01-01 00:00:0.0", tz="UTC")
ecmwfDate <- t0 + ecmwf_seconds

# We only want to load through 2013
tf <- which(ecmwfDate == as.POSIXct("2013-12-31", tz="UTC"))

# Now actually load the data
ecmwf_latitude <- ncvar_get(nc, "latitude")
ecmwf_longitude <- ncvar_get(nc, "longitude")
nLat <- length(ecmwf_latitude)
nLon <- length(ecmwf_longitude)

t2m <- ncvar_get(nc, "t2m", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

# To keep things as clear as possible, subset the time array so that they ALL
# match in terms of dimensions. 
ecmwfDate <- ecmwfDate[1:tf]
if(length(ecmwfDate) != dim(t2m)[3]){
  stop("The ecmwfDate date array and variable array do not match in length")
}

# RH% 
nc_file <- paste0(ncDir,"rh2m_2003_2016.nc")
nc <- nc_open(nc_file)
rh2m <- ncvar_get(nc, "rh2m", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

# days since rain 
nc_file <- paste0(ncDir,"days_since_rain_2003_2016.nc")
nc <- nc_open(nc_file)
daysSinceRain <- ncvar_get(nc, "days_since_rain", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

# total precip
nc_file <- paste0(ncDir,"tp_2003_2016.nc")
nc <- nc_open(nc_file)
tp <- ncvar_get(nc, "tp", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

# dew point
nc_file <- paste0(ncDir,"d2m_2003_2016.nc")
nc <- nc_open(nc_file)
d2m <- ncvar_get(nc, "d2m", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

# Wind speed
nc_file <- paste0(ncDir,"u10_2003_2016.nc")
nc <- nc_open(nc_file)
u10 <- ncvar_get(nc, "u10", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

nc_file <- paste0(ncDir,"v10_2003_2016.nc")
nc <- nc_open(nc_file)
v10 <- ncvar_get(nc, "v10", start=c(1,1,1), count=c(nLon, nLat, tf))
nc_close(nc)

windSpeed <- sqrt(u10^2 + v10^2)
# save workspace memory 
rm(v10, u10)

# Get the nc grid attributes
nc_file <- "Data/grid_attributes/grid_attributes_25x25.nc"
nc <- nc_open(nc_file)
elev  <- ncvar_get(nc, "elevation")
elev_lat <- ncvar_get(nc, "latitude")
elev_lon <- ncvar_get(nc, "longitude")
nc_close(nc)


# Plot the grids and data together to make sure the grids are the same
# Sanity check the placement of everything by visualized ecmwf and fire locations
quartz(width=8, height=5)
elev_flipper <- length(elev_lat):1
image.plot(elev_lon, elev_lat[elev_flipper], elev[,elev_flipper])
points(fireLon, fireLat, pch=".", col="black")
title("The fire locations (black dots, should be over thge U.S. )")


quartz(width=8, height=5)

flipper        <- length(ecmwf_latitude):1
ecmwf_latitude_flipped <- ecmwf_latitude[flipper]
t2m_flipped    <- t2m[,flipper,]

image.plot(ecmwf_longitude, ecmwf_latitude_flipped, t2m_flipped[,,100])
points(fireLonAdjusted, fireLat, pch=".", col="black")
title("The fire locations (black dots, should be over thge U.S. )")
#dev.off()


# Get the assignment loop working, first just for temperature
t2m_assigned           <- rep(NA, nRow)
rh2m_assigned          <- rep(NA, nRow)
daysSinceRain_assigned <- rep(NA, nRow)
tp_assigned            <- rep(NA, nRow)
d2m_assigned           <- rep(NA, nRow)
elev_assigned          <- rep(NA, nRow)

# Long term predictive measures
tm2_lastMonth  <- rep(NA, nRow)
rh2m_lastMonth <- rep(NA, nRow)
tp_lastMonth   <- rep(NA, nRow)

# After fire start days metric. Namely I am going to look at precip and wind
windSpeed_MonthAfter <- rep(NA, nRow)
tp_MonthAfter        <- rep(NA, nRow)
t2m_monthAfter       <- rep(NA, nRow)

# Loop through every single fire and assign its past current and future weather
nECMWFTime <- length(ecmwfDate)
for (i in 1:nRow){
  
  # Find the fire match in space and time in the reanalysis data 
  xi <- which.min(abs(fireLonAdjusted[i] - ecmwf_longitude))
  yi <- which.min(abs(fireLat[i] - ecmwf_latitude))
  ti <- which(fireDate[i] == ecmwfDate)
  
  # Assign each environmental variable
  t2m_assigned[i] <- t2m[xi, yi, ti]
  rh2m_assigned[i] <- rh2m[xi, yi, ti]
  daysSinceRain_assigned[i] <- daysSinceRain[xi, yi, ti]
  tp_assigned[i] <- tp[xi, yi, ti]
  d2m_assigned[i] <- d2m[xi, yi, ti]
  
  # Assign environmental variables with a timescale greater than say of. 
  pastIndicies <- (ti-29):ti # length == 30
  if(pastIndicies[1] > 0){
    
    tm2_lastMonth[i] <- mean(tp[xi, yi, pastIndicies])
    tp_lastMonth[i]  <- sum(t2m[xi, yi, pastIndicies])
    rh2m_lastMonth[i]<- mean(rh2m[xi, yi, pastIndicies])
    
  }

  # After fire start date indicies 
  futureIndicies <- ti:(ti+29) # length == 30
  if(futureIndicies[30] <= nECMWFTime){
    
    windSpeed_MonthAfter[i] <- mean(windSpeed[xi, yi, futureIndicies])
    tp_MonthAfter[i]        <- sum(tp[xi, yi, futureIndicies])
    t2m_monthAfter[i]       <- mean(t2m[xi, yi, futureIndicies])
    
  }
  
  # Not ecmwf, but elevation too, no time dimension
  # NOTE: non adjusted lon
  xxi <- which.min(abs(fireLon[i] - elev_lon))
  yyi <- which.min(abs(fireLat[i] - elev_lat))
  elev_assigned[i] <- elev[xxi, yyi]
  
  # Output progress to the screen
  if(i %% 1000 == 0){
    print(paste("Percent Complete: ", i/nRow*100))
  }
  
}

# Assign each of the new environmental arrays to FPA_FOD
FPA_FOD$t2m             <- t2m_assigned
FPA_FOD$rh2m            <- rh2m_assigned
FPA_FOD$days_since_rain <- daysSinceRain_assigned
FPA_FOD$tp              <- tp_assigned
FPA_FOD$d2m             <- d2m_assigned

# Past environment
FPA_FOD$tm2_lastMonth  <- tm2_lastMonth
FPA_FOD$tp_lastMonth   <- tp_lastMonth
FPA_FOD$rh2m_lastMonth <- rh2m_lastMonth

# Future environment
FPA_FOD$windSpeed_MonthAfter <- windSpeed_MonthAfter
FPA_FOD$tp_MonthAfter        <- tp_MonthAfter
FPA_FOD$t2m_monthAfter       <- t2m_monthAfter

# static in time 
FPA_FOD$elevation <- elev_assigned

save(FPA_FOD, file = "Data/FPA_FOD/FPA_FOD_ecmwf_2003_2013.RData")
# The end. 