"""Checks the DuckDB warehouse after run_etl.py.
Verifies data integrity, financial reconciliation, SCD consistency,
executes the 3 Milestone 1 dimensional queries, and outputs query latency metrics.

Usage:
    python check_etl.py
"""
import time
import duckdb

con = duckdb.connect("dwh.duckdb")


def show(title, query):
    print("\n" + "=" * 70)
    print(">>", title)
    print("=" * 70)
    con.sql(query).show()


def run_analytical_query(query_id, query_name, sql, limit=10):
    print("\n" + "=" * 70)
    print(f">> [ANALYTICAL QUERY - {query_id}]: {query_name}")
    print("=" * 70)
    t0 = time.time()
    try:
        rel = con.sql(sql)
        row_count = rel.shape[0]
        exec_ms = round((time.time() - t0) * 1000, 2)
        con.execute("""
            INSERT INTO query_performance_log (query_id, query_name, execution_ms, rows_returned, status)
            VALUES (?, ?, ?, ?, 'SUCCESS')
        """, [query_id, query_name, exec_ms, row_count])
        con.sql(f"{sql} LIMIT {limit}").show()
        print(f"Status: SUCCESS | Latency: {exec_ms} ms | Total Result Rows: {row_count}")
    except Exception as e:
        exec_ms = round((time.time() - t0) * 1000, 2)
        con.execute("""
            INSERT INTO query_performance_log (query_id, query_name, execution_ms, rows_returned, status)
            VALUES (?, ?, ?, 0, 'FAILED')
        """, [query_id, query_name, exec_ms])
        print(f"Status: FAILED | Latency: {exec_ms} ms | Error: {e}")


# 1. Pipeline Data Reconciliation
show("1. CSV rows = loaded rows + rejected rows",
     """SELECT 'sales' AS domain,
               (SELECT count(*) FROM raw_sales) AS csv_rows,
               (SELECT count(*) FROM Fact_Sales) AS loaded_rows,
               (SELECT count(*) FROM etl_rejects WHERE source_table = 'Fact_Sales') AS rejected_rows
        UNION ALL
        SELECT 'demand',
               (SELECT count(*) FROM raw_demand),
               (SELECT count(*) FROM Fact_Hospital_Demand),
               (SELECT count(*) FROM etl_rejects WHERE source_table = 'Fact_Hospital_Demand');""")

# 2. Financial Reconciliation (Zero Variance Required)
show("2. Gross Sales Financial Reconciliation (CSV vs Fact Table)",
     """SELECT (SELECT sum(TRY_CAST(GrossSalesAmountUSD AS DECIMAL(14,2))) FROM raw_sales) AS csv_gross_usd,
               (SELECT sum(GrossSalesAmountUSD) FROM Fact_Sales) AS fact_gross_usd,
               round((SELECT sum(GrossSalesAmountUSD) FROM Fact_Sales) - 
                     (SELECT sum(TRY_CAST(GrossSalesAmountUSD AS DECIMAL(14,2))) FROM raw_sales), 2) AS variance_usd;""")

# 3. Foreign Key Orphan Checks (Every number MUST be 0)
show("3. Orphan Foreign Keys (All counts MUST be 0)",
     """SELECT
          (SELECT count(*) FROM Fact_Sales f LEFT JOIN DimMedicine d ON d.MedicineKey = f.MedicineKey WHERE d.MedicineKey IS NULL) AS sales_orphan_medicine,
          (SELECT count(*) FROM Fact_Sales f LEFT JOIN DimPharmacy d ON d.PharmacyKey = f.PharmacyKey WHERE d.PharmacyKey IS NULL) AS sales_orphan_pharmacy,
          (SELECT count(*) FROM Fact_Sales f LEFT JOIN DimDate d ON d.DateKey = f.SaleDateKey WHERE d.DateKey IS NULL) AS sales_orphan_date,
          (SELECT count(*) FROM Fact_Sales f LEFT JOIN DimLocation d ON d.LocationKey = f.PharmacyLocationKey WHERE d.LocationKey IS NULL) AS sales_orphan_location,
          (SELECT count(*) FROM Fact_Hospital_Demand f LEFT JOIN DimHospital d ON d.HospitalKey = f.HospitalKey WHERE d.HospitalKey IS NULL) AS demand_orphan_hospital,
          (SELECT count(*) FROM Fact_Hospital_Demand f LEFT JOIN DimMedicine d ON d.MedicineKey = f.MedicineKey WHERE d.MedicineKey IS NULL) AS demand_orphan_medicine,
          (SELECT count(*) FROM Fact_Hospital_Demand f LEFT JOIN DimDate d ON d.DateKey = f.DemandMonthKey WHERE d.DateKey IS NULL) AS demand_orphan_date;""")

# 4. SCD Integrity Check
show("4. Active SCD Rows Check (Must return 0 rows)",
     """SELECT 'DimMedicine' AS dim_table, MedicineID AS natural_key, count(*) AS active_rows 
        FROM DimMedicine WHERE IsCurrent GROUP BY MedicineID HAVING count(*) > 1
        UNION ALL
        SELECT 'DimHospital', HospitalID, count(*) 
        FROM DimHospital WHERE IsCurrent GROUP BY HospitalID HAVING count(*) > 1
        UNION ALL
        SELECT 'DimPharmacy', PharmacyID, count(*) 
        FROM DimPharmacy WHERE IsCurrent GROUP BY PharmacyID HAVING count(*) > 1;""")

# 5. Cleaned Medicine Dosage Forms
show("5. Transformed Medicine Attributes & Form Abbreviations (First 5)",
     """SELECT MedicineID, MedName, DosageStrength, PackSizeBand, BaseUOM, ColdChainFlag, ShelfLifeBand, ProductStatus
        FROM DimMedicine ORDER BY MedicineKey LIMIT 5;""")

# 6. Cleaned Pharmacy Master
show("6. Standardized Pharmacy Dimension (First 5)",
     """SELECT PharmacyID, PharmacyGLN, PharmacyName, PharmacyType 
        FROM DimPharmacy ORDER BY PharmacyKey LIMIT 5;""")

# 7. Analytical Query 1 (Dashboard 2 in Project Spec): Channel Revenue Split & MoM Growth
q1_sql = """
SELECT 
    YearMonth,
    ReportingChannel,
    round(sum(net_sales_usd), 2) AS net_sales_usd,
    round(avg(gross_margin_pct), 2) AS avg_gross_margin_pct,
    round(avg(discount_rate_pct), 2) AS avg_discount_rate_pct,
    round(avg(mom_growth_pct), 2) AS avg_mom_growth_pct
FROM vw_bi_channel_performance
GROUP BY YearMonth, ReportingChannel
ORDER BY YearMonth DESC, ReportingChannel
"""
run_analytical_query("Q1_SDI", "Channel Revenue Split & MoM Growth Analysis", q1_sql, limit=12)

# 8. Analytical Query 2 (Dashboard 1 in Project Spec): Hospital Forecast vs Consumed & Unfulfilled Demand
q2_sql = """
SELECT 
    HospitalName,
    MedName,
    TherapeuticClass,
    sum(forecast_packs) AS total_forecast_packs,
    sum(consumed_packs) AS total_consumed_packs,
    round(sum(consumed_packs) * 100.0 / nullif(sum(forecast_packs), 0), 2) AS consumption_ratio_pct,
    sum(unfulfilled_packs) AS total_unfulfilled_packs,
    round(avg(mape_pct), 2) AS avg_mape_pct
FROM vw_bi_hospital_forecast_accuracy
GROUP BY HospitalName, MedName, TherapeuticClass
ORDER BY total_unfulfilled_packs DESC
"""
run_analytical_query("Q2_SDI", "Hospital Forecast vs Consumption & Unfulfilled Demand", q2_sql, limit=10)

# 9. Analytical Query 3 (Dashboard 3 in Project Spec): Drill-Across Cold Chain Fast Movers
q3_sql = """
SELECT 
    MedName,
    TherapeuticClass,
    pharmacy_sold_packs,
    hospital_consumed_packs,
    total_cold_chain_demand_packs,
    rank_fast_mover,
    rank_slow_mover
FROM vw_bi_fast_slow_moving_cold_chain
WHERE rank_fast_mover <= 2 OR rank_slow_mover <= 2
ORDER BY TherapeuticClass, rank_fast_mover
"""
run_analytical_query("Q3_SDI", "Multi-Fact Drill-Across Fast vs Slow Movers", q3_sql, limit=14)

# 10. Query Layer Observability Summary (Weightage: 2%)
show("10. Analytical Query Layer Latency & Health Observability (Phase 1 DE Rubric)",
     """SELECT 
            query_id,
            query_name,
            count(*) AS total_runs,
            round(avg(execution_ms), 2) AS avg_latency_ms,
            round(min(execution_ms), 2) AS min_latency_ms,
            round(max(execution_ms), 2) AS max_latency_ms,
            round(100.0 * sum(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END) / count(*), 2) AS error_rate_pct
        FROM query_performance_log
        GROUP BY query_id, query_name;""")

con.close()
