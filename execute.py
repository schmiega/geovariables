# Created on 2023-07-20 by LFS\aschmieg

# This script needs to be run to prepares the table __JuakaliGPSData to be used by 
# the Client GPS Dashboard on Qliksense. It requires the following tables to be present:
# - branches.csv, locally, containing at least BranchCode, Latitude, Longitude
# - juakali data, on a PostgreSQL server, containing at least 
#   loannumber, Latitude, Longitude (where loannumber is ccodcta)

# Server, database, tables, and authentication are defined in SQL.py

#%%
# Setup workdir
import os
workdir = os.path.abspath("")
os.chdir(workdir)

import pandas as pd
branches = pd.read_csv("__branches.csv")
with open("join.sql") as file:
    query = file.read()
from methods import SQL
juakali = SQL.fetch_pgsql("SELECT * FROM public.vw_loan_application")
juakali.to_csv("__JuakaliGPSData.csv", index=False)

#%%
# Uploads to SQL
SQL.upload(juakali, table = "__JuakaliGPSData")
SQL.upload(branches, table = "__branches")

#%%
# Run join and test for success
# SQL.execute(query)
# df = SQL.fetch_mssql("SELECT TOP * FROM __loans_GPS")
success_test = SQL.fetch_mssql(f"""
SELECT 
successCount = CASE WHEN OBJECT_ID('dbo.__loans_GPS', 'U') IS NOT NULL THEN (SELECT COUNT(ccodcta) FROM dbo.__loans_GPS) ELSE 0 END, 
successRate = CASE WHEN OBJECT_ID('dbo.__loans_GPS', 'U') IS NOT NULL THEN 
	CAST((SELECT COUNT(ccodcta) FROM dbo.__loans_GPS) AS float) / {juakali.shape[0]}
ELSE 0 END
""")
print(f"Completed calculations for: {success_test.successCount[0]} loans = {success_test.successRate[0]:.1%} of applications.")

print("All done. You can now import from SQL in the QlikSense app.")

#%%























#%%
# tests for faster upload
breakpoint()
#%%
# https://9to5answer.com/speeding-up-pandas-dataframe-to_sql-with-fast_executemany-of-pyodbc
# https://stackoverflow.com/questions/29706278/python-pandas-to-sql-with-sqlalchemy-how-to-speed-up-exporting-to-ms-sql

import pyodbc as pdb

df_tuples = [tuple(r) for r in juakali.to_numpy()]

conn = pdb.connect(
    "Driver={ODBC Driver 17 for SQL Server};"
    "Server=SLFSABNRPT;"
    "Database=LFSBAKU;"
    "Trusted_Connection=yes;"
    "autocommit=True;"
)
cursor = conn.cursor()
cursor.fast_executemany = True
sql_statement = """
DROP TABLE IF EXISTS dbo.__JuakaliGPSData;
CREATE TABLE dbo.__JuakaliGPSData (
    loannumber nvarchar NOT NULL,
    residencelocation nvarchar,
    businesslocation nvarchar,
    loanofficer nvarchar,
    residentlocation1 float,
    residentlocation2 float,
    businesslocation1 float,
    businesslocation2 float
);
INSERT INTO dbo.__JuakaliGPSData VALUES (?, ?, ?, ?, ?, ?, ?, ?);
"""

conn.commit()
cursor.close()
conn.close()

#%%
