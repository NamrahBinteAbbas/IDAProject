"""Runs the Phase 1 Sales & Demand Intelligence (SDI) ETL in DuckDB.
Enterprise Data Engineering Pipeline for Milestone 1.

Usage:
    python run_etl.py           # Standard incremental run / load
    python run_etl.py --rebuild # Clean rebuild from source CSVs

Idempotent: Safe to run repeatedly; preserves SCD history and only adds new rows.
"""
import sys
import os
import pathlib
import time
import duckdb

DB_FILE = "dwh.duckdb"
SQL_FILE = "phase1_sdi_duckdb.sql"

if "--rebuild" in sys.argv and os.path.exists(DB_FILE):
    print(f"Rebuilding database: removing existing {DB_FILE}...")
    try:
        os.remove(DB_FILE)
        print("Existing database removed.")
    except Exception as e:
        print(f"Notice: Could not delete {DB_FILE} directly ({e}). Proceeding with table replacement.")

print(f"Connecting to DuckDB database: {DB_FILE}")
con = duckdb.connect(DB_FILE)

print(f"Executing SQL script: {SQL_FILE}")
start_time = time.time()
sql = pathlib.Path(SQL_FILE).read_text(encoding="utf-8")
con.execute(sql)
elapsed = round(time.time() - start_time, 2)
print(f"ETL Execution completed in {elapsed} seconds.\n")

print("=" * 60)
print(f"{'Table / Mart View':<35} {'Row Count':>15}")
print("=" * 60)

tables_to_check = [
    "DimDate",
    "DimLocation",
    "DimMedicine",
    "DimHospital",
    "DimPharmacy",
    "Fact_Sales",
    "Fact_Hospital_Demand",
    "etl_rejects",
    "vw_bi_channel_performance",
    "vw_bi_hospital_forecast_accuracy",
    "vw_bi_fast_slow_moving_cold_chain"
]

for item in tables_to_check:
    try:
        count = con.execute(f"SELECT count(*) FROM {item}").fetchone()[0]
        print(f"{item:<35} {count:>15,}")
    except Exception as err:
        print(f"{item:<35} {'ERROR: ' + str(err):>15}")

con.close()
print("=" * 60)
print("DuckDB SDI Mart is ready for analytical queries and BI dashboard connection.")
