USE LFSBAKU
----------------------------------------------------------------------------------------------------------
-- Functions:
DROP FUNCTION IF EXISTS GetDistance
GO

-- function to calculate the distance between GPS locations
CREATE OR ALTER FUNCTION dbo.GetDistance (
	@lat1 float, @lon1 float, @lat2 float, @lon2 float
)
RETURNS int
AS BEGIN
	DECLARE @ret int = 0
	IF @lat1 > 0 AND @lat2 > 0
		SET @ret = CAST(geography::Point(@lat1, @lon1, 4326).STDistance(geography::Point(@lat2, @lon2, 4326)) AS INT)
	ELSE
		SET @ret = NULL
	RETURN @ret
END;
GO

DROP FUNCTION IF EXISTS dbo.EstimateDistance
GO
-- estimates distance based on formula from https://en.wikipedia.org/wiki/Geographic_coordinate_system#Length_of_a_degree
-- goal is to accelerate the calculation from using geography..STDistance()
CREATE OR ALTER FUNCTION dbo.EstimateDistance (
	@lat1 float, @lon1 float, @lat2 float, @lon2 float
)
RETURNS bigint
AS BEGIN
	DECLARE @a float			=	Cos(@lat1)
	DECLARE @distlat float			=	111132.92 - 559.82 * 2 * @a + 1.175 * 4 * @a - 0.0023 * 6 * @a
	DECLARE @distlon float			=	111412.84 * @a - 93.5 * 3 * @a + 0.118 * 5 * @a
	DECLARE @b float			=	0.00 --Cos(@lat2)
	-- -- removed averaging to improve speed at the cost of accuracy
	--DECLARE @distlat2 float		=	111132.92 - 559.82 * 2 * @b + 1.175 * 4 * @b - 0.0023 * 6 * @b
	--DECLARE @distlon2 float		=	111412.84 * @b - 93.5 * 3 * @b + 0.118 * 5 * @b
	--DECLARE @distlat float		=	(@distlat1 + @distlat2) / 2
	--DECLARE @distlon float		=	(@distlon1 + @distlon2) / 2
	SET @a					=	ABS(@lat2 - @lat1) * @distlat
	SET @b					=	ABS(@lon2 - @lon1) * @distlon
	DECLARE @ret float			=	SQRT(POWER(@a, 2) + POWER(@b, 2))
	RETURN @ret
END;
GO

DROP FUNCTION IF EXISTS dbo.GetGeoVars
GO
-- calculates distances branch-home, branch-business and home-business 
CREATE OR ALTER FUNCTION dbo.GetGeoVars (
	@BusLat float, @BusLon float, @HomeLat float, @HomeLon float, @BranchLat float, @BranchLon float
)
RETURNS TABLE AS RETURN (
	WITH loc AS (
		SELECT
			  Bus 			=	CASE WHEN ABS(@BusLat) > 0 AND ABS(@BusLon) > 0 THEN geography::Point(@BusLat, @BusLon, 4326) ELSE NULL END
			, Home 			=	CASE WHEN ABS(@HomeLat) > 0 AND ABS(@HomeLon) > 0 THEN geography::Point(@HomeLat, @HomeLon, 4326) ELSE NULL END
			, Branch		=	CASE WHEN ABS(@BranchLat) > 0 AND ABS(@BranchLon) > 0 THEN geography::Point(@BranchLat, @BranchLon, 4326) ELSE NULL END
	)
	SELECT 
		  BusinessToHome		=	CASE WHEN Bus IS NOT NULL AND Branch IS NOT NULL THEN 		Round(Bus.STDistance(Home), 2)		ELSE NULL END
		, BusinessToBranch		=	CASE WHEN Home IS NOT NULL AND Branch IS NOT NULL THEN 		Round(Bus.STDistance(Branch), 2) 	ELSE NULL END
		, HomeToBranch			=	CASE WHEN Home IS NOT NULL AND Bus IS NOT NULL THEN 	
								CASE WHEN @HomeLat = @BusLat AND @HomeLon = @BusLon THEN NULL
								ELSE Round(Home.STDistance(Branch), 2) 	
								END ELSE NULL END
	FROM loc
)
GO
----------------------------------------------------------------------------------------------------------------
-- Joins:
DROP TABLE IF EXISTS #selection
DECLARE @db_date DATETIME = (SELECT MAX(dfecpro) FROM dbo.avidkard)
SELECT cremcre.ccodcta
	, cremcre.ccodcli
	, [OutstandingAmount]		=	Round(cremcre.ncapdes - cremcre.ncappag, 2)
	, [CurrentOverdueDays]		=	ISNULL(MAX(CASE
		WHEN credppg.cestado 	= 'P' 		THEN	0
		WHEN credppg.cestado 	= 'E'
		AND  credppg.dfecven 	< @db_date 	THEN 	DATEDIFF(day, credppg.dfecven, @db_date )
		WHEN credppg.cestado 	= 'E' 		THEN 	0
		END), 0)
INTO #selection FROM cremcre
INNER JOIN credppg ON cremcre.ccodcta = credppg.ccodcta
WHERE cremcre.ccondic NOT IN ('x','y')
AND cremcre.cestado = 'F'
GROUP BY cremcre.ccodcta, cremcre.ccodcli, cremcre.ncapdes, cremcre.ncappag, cremcre.ccondic

DROP TABLE IF EXISTS #selection2
SELECT #selection.*
--	, #upload.*
	, ApplicationDate		=	CONVERT(VARCHAR, dFecSol, 23)
	, AmountApproved		=	nmonapr	
	, Age				=	DATEDIFF(YEAR, dnacimi, @db_date)
	, Gender			=	CASE WHEN csexo = 'F' THEN 'Female' WHEN csexo = 'M' THEN 'Male' WHEN csexo IS NULL THEN 'Other' END
	, GenderFemale			=	CASE WHEN csexo = 'F' THEN 1 WHEN csexo = 'M' THEN 0 END
	, MaritalStatus			=	(SELECT TOP 1 cdescri FROM tabttab WHERE ccodtab = 12 AND climide.cestciv = tabttab.ccodigo)
	, LoanOfficer			=	ccodana
	, DisbursementDate		=	CONVERT(VARCHAR, dfecvig, 23)
	, BranchCode			= 	cremcre.ccodofi	
	, LoanPurpose			=	(SELECT TOP 1 cdescri FROM tabttab WHERE ccodtab = 099 AND cremcre.cProCre = tabttab.ccodigo)
	, Sector			=	(SELECT TOP 1 cdescri FROM tabttab WHERE ccodtab = 098 AND ccodigo = SUBSTRING(cremcre.cSector, 1, 2))
	, SubSector			=	(SELECT TOP 1 cdescri FROM tabttab WHERE ccodtab = 098 AND ccodigo = SUBSTRING(cremcre.cSector, 1, 4))
	, UsedDigital			=	ISNULL((SELECT TOP 1 1 FROM dbo.__digital_transactions WHERE AccountNumber = cremcre.cCurAcc AND Channel <> 'Agent'), 0)
--	, CreditLine			= 	cdeslin
	, LoanProduct			=	(SELECT TOP 1 cdescri FROM tabttab WHERE ccodtab = 080 AND cremcre.cservicio = tabttab.ccodigo)
	, LoanCycle			=	1 + (SELECT COUNT(cremcre.ccodcli) FROM cremcre WHERE cestado = 'G' AND cremcre.ccodcli = #selection.ccodcli)
	, ProcessingTimeMinutes		=	DATEDIFF(MINUTE, cremcre.dFecSol, cremcre.dfecvig)
	, ProcessingTimeDays		=	DATEDIFF(DAY, cremcre.dFecSol, cremcre.dfecvig)
	, PAR30				=	ISNULL(CASE WHEN CurrentOverdueDays >= 30 THEN OutstandingAmount END, 0)
	, InPAR30			=	ISNULL(CASE WHEN OutstandingAmount > 0 AND CurrentOverdueDays >= 30 THEN 1 END, 0)
	, ncapdes			AS	AmountDisbursed
	, ntasint			AS	InterestRate
	, ndiaatr			AS	LoanOverdueDays
	, ccondic			AS	LoanCondition
	, cestado			AS	LoanStatus
	, Latitude			AS 	LatitudeMymbs
	, Longitude			AS 	LongitudeMymbs
	, Latitude 			= 	TRY_CAST(businesslocation1 AS float)
	, Longitude			=	TRY_CAST(businesslocation2 AS float)
	, HomeLat 			= 	TRY_CAST(residentlocation1 AS float)
	, HomeLon 			= 	TRY_CAST(residentlocation2 AS float)
INTO #selection2
FROM #selection
INNER JOIN climide ON #selection.ccodcli = climide.ccodcli
INNER JOIN cremcre ON #selection.ccodcta = cremcre.ccodcta
LEFT JOIN __JuakaliGPSData ON #selection.ccodcta = __JuakaliGPSData.loannumber
DROP TABLE IF EXISTS #selection

DROP TABLE IF EXISTS __loans_GPS_temp
SELECT a.*, g.*
	, LoanCycleGroup		=	CASE WHEN 	LoanCycle 	= 	1 	THEN '1' 
						WHEN 		LoanCycle 	IN 	(2,3,4) THEN '2-4' 
						WHEN 		LoanCycle 	> 	4 	THEN '5+' 
						ELSE NULL END
INTO __loans_GPS_temp FROM #selection2 a
LEFT JOIN __branches b
ON a.BranchCode LIKE b.BranchCode
OUTER APPLY dbo.GetGeoVars(a.Latitude, a.Longitude, a.HomeLat, a.HomeLon, b.Latitude, b.Longitude) g
WHERE a.Latitude > 4.2 AND a.Latitude < 13.7
AND a.Longitude > 2.6 AND a.Longitude < 14.7

DROP TABLE IF EXISTS #selection2

------------------------------------------------------------------------------------------------------
-- Density function: 

DROP FUNCTION IF EXISTS dbo.GetDensity
GO
CREATE OR ALTER FUNCTION dbo.GetDensity (
	@lat float, @lon float, @radius int -- radius in km
)
RETURNS TABLE AS RETURN (
	WITH cte AS (
		SELECT
			    ccodcta
			  , dist = CAST(dbo.EstimateDistance(@lat, @lon, Latitude, Longitude) AS float) / 1000
		FROM (
			SELECT * FROM __loans_GPS_temp
			WHERE Latitude <> @lat 
			-- to avoid 0 distance to self
			AND SQRT(POWER(ABS(Latitude - @lat) * 125, 2) + POWER(ABS(Longitude - @lon) * 125, 2)) < @radius 
			-- 125 km is more than @distlat and @distlon can be, but small enough to speed up the query
		) a
	)
	SELECT Density = CAST(ROUND(((COUNT(ccodcta) + 0.0001) / (3.14159 * POWER(@radius, 2))), 2) AS float)
	FROM cte
	WHERE dist <= @radius -- only neighbors within radius
)
GO

-------------------------------------------
-- Density table: 

-- Specify radius as function parameter
DROP TABLE IF EXISTS #density
SELECT z.*, a.ccodcta
INTO #density FROM __loans_GPS_temp a
OUTER APPLY dbo.GetDensity(Latitude, Longitude, 2.5) AS z 
DROP TABLE IF EXISTS __loans_GPS
SELECT a.*, z.Density
INTO __loans_GPS FROM __loans_GPS_temp a
INNER JOIN #density z ON a.ccodcta = z.ccodcta
DROP TABLE IF EXISTS __loans_GPS_temp
