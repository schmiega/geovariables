SELECT
	  [NoOutstanding]				=		CAST(COUNT(ccodcta) AS int)
	, [NoOutstandingGPS]			=		CAST(SUM(CASE WHEN businesslocation LIKE 'NULL' THEN 1 ELSE 0 END) AS int)
	, [ShareWithGPS]				=		ROUND(CAST(SUM(CASE WHEN businesslocation LIKE 'NULL' THEN 1 ELSE 0 END) AS float) / CAST(COUNT(ccodcta) AS float), 4)
FROM LFSBAKU.dbo.cremcre
LEFT JOIN LFSBAKU.dbo.__JuakaliGPSData ON __JuakaliGPSData.loannumber = cremcre.ccodcta
WHERE cremcre.ccondic NOT IN ('x','y') AND cestado = 'F';