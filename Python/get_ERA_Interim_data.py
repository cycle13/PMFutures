#!/usr/bin/env python

# This script is used to get data from ecmwf web API
# https://software.ecmwf.int/wiki/display/WEBAPI/Python+ERA-interim+examples
# Requests format created from ECMWF GUI and MARS request
# http://apps.ecmwf.int/datasets/data/interim-full-daily/levtype=sfc/
# HIT "View the MARS request buttom at the bottom to use this script for data"

import sys
import numpy as np
from ecmwfapi import ECMWFDataServer

# Get command line arguments
VAR         = sys.argv[1]
startYear   = int(sys.argv[2])
endYear     = int(sys.argv[3])
levtype     = sys.argv[4] #"sfc" # "pl"
gridSpacing = "0.75/0.75" # "0.75/0.75" | "1.50/1.50"

if gridSpacing == "0.75/0.75":
	DataDir = "/barnes-scratch/sbrey/era_interim_nc_6_hourly/"
else:
	DataDir = "/barnes-scratch/sbrey/era_interim_nc_6_hourly_1_5/"


nYears = (endYear - startYear) + 1
yearArray = np.arange(startYear, endYear+1)


# Connect to the server
server = ECMWFDataServer()

# get param based on dictionary
# TODO: UPDATE once the better names are known
param_dict = {"sp":"134.128",
	           "t2m":"167.128",
              "d2m":"168.128",
              "u10":"165.128",
              "v10":"166.128",
              "tp":"228.128",
	           "z":"129.128",
	           "vo":"138.128",
	           "u":"131.128",
              "v":"132.128",
              "t":"130.128",
              "wgust":"49.128",
              "evap":"182.128"
              }

param = param_dict[VAR]

# handle the fact that some variables have different time steps
if (param == "228.128") or (param == "182.128"):
	# For explanation on why step needs to be 12 for these times to get daily
	# totals, please see example 1 of the following link.
	# https://software.ecmwf.int/wiki/pages/viewpage.action?pageId=56658233
	print "getting precip, changing step and time"
	step = "12"
	time = "00:00:00/12:00:00"
else:
	step = "0"
	time = "00:00:00/06:00:00/12:00:00/18:00:00"

# Loop through years, download each as its own request
for i in range(nYears):

	year_str = str(yearArray[i])

	# write the save location
	target = DataDir + VAR + "_" + year_str + ".nc"
	# write the date range to be downloaded
	date = year_str + "-01-01/to/" + year_str + "-12-31"

	print "---------------------------------------------------------------"
	print "Working on downloading " + VAR +":" +param + " for " + year_str
	print "writing: " + target
	print "---------------------------------------------------------------"

	if levtype == "sfc":

		if (param == "228.128") or (param == "182.128"):
		# precip and evap requires special treatment
			server.retrieve({
    				"class": "ei",
    				"dataset": "interim",
    				"date": date,
				    "expver": "1",
				    "grid": gridSpacing,
			    	"levtype": "sfc",
			    	"param": param,
			    	"step": "6",
			    	"stream": "oper",
			    	"time": "00:00:00/12:00:00",
			    	"type": "fc",
				    "format" : "netcdf",
			    	"target": target,
			})
		else:
			server.retrieve({
				"class": "ei",
				"dataset": "interim",
				"date": date,
				"expver": "1",
				"grid": gridSpacing,
				"levtype": "sfc",
				"param": param,
				"step": step,
				"stream": "oper",
				"time": time,
				"type": "an",
				"format" : "netcdf",
				"target": target,
			})

	else:

		server.retrieve({
		"class": "ei",
		"dataset": "interim",
		"date": date,
		"expver": "1",
		"grid": gridSpacing,
		"levelist": "250/500/850/1000",
		"levtype": "pl",
		"param": param,
		"step": step,
		"stream": "oper",
		"time": time,
		"type": "an",
		"format" : "netcdf",
		"target": target,
		})







