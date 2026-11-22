import pathlib
import duckdb

db_file = "dwh.duckdb" if pathlib.Path("dwh.duckdb").exists() else "../dwh.duckdb"
con = duckdb.connect(db_file, read_only=True)

sql = """
WITH sales_demand AS (
    SELECT 
        m.MedicineKey,
        m.MedName,
        m.TherapeuticClass,
        sum(f.QuantitySoldPacks) AS pharmacy_sold_packs
    FROM Fact_Sales f
    JOIN DimMedicine m ON f.MedicineKey = m.MedicineKey
    WHERE m.ColdChainFlag = TRUE
    GROUP BY m.MedicineKey, m.MedName, m.TherapeuticClass
),
hospital_demand AS (
    SELECT 
        m.MedicineKey,
        sum(f.ConsumedQuantityPacks) AS hospital_consumed_packs
    FROM Fact_Hospital_Demand f
    JOIN DimMedicine m ON f.MedicineKey = m.MedicineKey
    WHERE m.ColdChainFlag = TRUE
    GROUP BY m.MedicineKey
)
SELECT 
    s.MedName,
    s.TherapeuticClass,
    s.pharmacy_sold_packs,
    coalesce(h.hospital_consumed_packs, 0) AS hospital_consumed_packs,
    (s.pharmacy_sold_packs + coalesce(h.hospital_consumed_packs, 0)) AS total_demand,
    rank() OVER (PARTITION BY s.TherapeuticClass ORDER BY (s.pharmacy_sold_packs + coalesce(h.hospital_consumed_packs, 0)) DESC) AS rank_fast_mover
FROM sales_demand s
LEFT JOIN hospital_demand h ON s.MedicineKey = h.MedicineKey
ORDER BY s.TherapeuticClass, rank_fast_mover;
"""

con.sql(sql).show()
con.close()
