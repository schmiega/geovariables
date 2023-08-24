# Geo-Variables & Loan Mapping
Calculate geographical information based on a table of loans and a table of a bank's branches on a MSSQL server. 

This article documents the variables and functions developed for a demo-dashboard to showcase functionalities that are made possible by geographical information. The functions are written to be easily applyable on tables that include client GPS locations by adding the locations of the branches as a separate table. 

**Warning**: some of the functions contain filters and calculations that are specific to the region of Nigeria. In order to be used for other regions, these must be adjusted!

The following variables were established by using the functions in the next section.

## Client-centered Location Variables
#### Client home location
The GPS location of the clients home is gathered in the Juakali process and can be used as is. It will also be used for further computations.
#### Client business location
  The same is true for the business' location
#### Home business distance
  The distance between home and business locations. This can be calculated in SQL using the _STDistance(Point)_ function of the geography package. The client mapping project uses an intermediary function GetDistance for this, see below for details.
#### Distance to branch
  How far away the branch is from the clients home, or business, respectively. Calculated as a straight line connection. Takes the branch code (ccodofi) from cremcre and matches it to the __branches table (has to be added manually).
#### Is closest branch
  Is 1 if the branch (ccodofi) is the closest to the client's home/business, or 0 if a closer branch exists. Again, this considers only a straight line.
#### Client density
  Similar to population density; how many clients there are per square kilometer in a given radius (provide radius to function). The client mapping project uses the function GetDensity for this, see below.

## MSSQL Functions
### GetDistance ( lat1, lon1, lat2, lon2 )
A wrapper for the MSSQL function _geography::Point.STDistance(Point2)_. Takes two locations, returns accurate distance in meters. Used to get a single value.

**Warning**: verifies non-null coordinates by checking if latitude > 0. This is not suitable for all regions. 

### EstimateDistance ( lat1, lon1, lat2, lon2 )
Alternative to GetDistance with a lower computational footprint. Takes two locations, returns rough distance in meters. Used to get a single value.

Because _GetDensity_ is extremely computationally intense when calculated on a large dataset, using STDistance would result in infinitely long computing times. This function is less accurate but runs much faster because it approximates a conversion of coordinates to meters, instead of locating them and calculating the actual distance. The formula for the conversion was found here: https://en.wikipedia.org/wiki/Geographic_coordinate_system#Length_of_a_degree

The function works as follows. We provide Point __A__ as _lat1, lon1_ and Point __B__ as _lat2, lon2_. The function 

1. declares variables for the conversion factor (depending on the latitude of provided location __A__),
2. calculates pseudo-'vertical' and 'horizontal' distances (_a_ and _b_, alias AC and CB),
3. calculates the direct distance between the two points using the Pythagorean Theorem. 

<img src='https://upload.wikimedia.org/wikipedia/commons/thumb/f/fb/Pythagoras_similar_triangles_simplified.svg/1280px-Pythagoras_similar_triangles_simplified.svg.png' alt='Pythagorean Theorem - Wikipedia' width='333px'>

### GetGeoVars ( BusLat, BusLon, HomeLat, HomeLon, BranchLat, BranchLon )
A wrapper for some distance calculations. Used to get a table of values that can be outer applied to the loans. 

Returns the following as accurate distances in meters: _BusinessToHome, BusinessToBranch, HomeToBranch_

### GetDensity ( lat, lon, radius )
**Warning**: assumes conversion factors in EstimateDistance to be less than 125 km. This needs to be verified by calculating with the underlying formula if being used for countries other than Nigeria. 

Takes a location (called **A** here) and a radius in kilometers. Returns the density of clients within that area, per square kilometer. Used to get a column of values that can be outer applied to the loans. 

1. The function reduces the number of observations to compare to by applying the Pythagorean Theorem with a degree-to-kilometers conversion factor of 125. That is higher than the actual factor (for Nigeria), which is why the relevant observations + a few more will be selected. 
2. It then assigns each selected observation in the dataset an estimated distance to **A**
3. and calculates the density as the number of clients inside the radius divided by the circle area of the radius $r = \pi * r^2$

By filtering with a rough calculation inside of a CTE query, the number of more accurate point-to-point calculations is drastically removed. This brought down the run time from (hypothetically) several weeks to 5 minutes in the case of ABN. 
