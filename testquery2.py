import duckdb

con = duckdb.connect("dwh.duckdb", read_only=True)

sql = """
SELECT 
    h.HospitalName,
    m.MedName,
    sum(f.ForecastDemandPacks) AS forecast_packs,
    sum(f.ConsumedQuantityPacks) AS consumed_packs,
    round(sum(f.ConsumedQuantityPacks) * 100.0 / nullif(sum(f.ForecastDemandPacks), 0), 2) AS consumption_ratio_pct,
    sum(f.UnfulfilledDemandPacks) AS unfulfilled_shortage,
    round(avg(abs(f.ForecastDemandPacks - f.ConsumedQuantityPacks) * 100.0 / nullif(f.ConsumedQuantityPacks, 0)), 2) AS mape_error_pct
FROM Fact_Hospital_Demand f
JOIN DimHospital h ON h.HospitalKey = f.HospitalKey
JOIN DimMedicine m ON m.MedicineKey = f.MedicineKey
GROUP BY h.HospitalName, m.MedName
ORDER BY unfulfilled_shortage DESC
LIMIT 5;
"""

con.sql(sql).show()
con.close()