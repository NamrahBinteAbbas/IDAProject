import duckdb
for f in ["01_master_data.csv", "05_pharmacy_sales_data.csv", "06_hospital_demand_data.csv"]:
    print("\n==", f)
    for row in duckdb.sql(f"DESCRIBE SELECT * FROM read_csv('data/{f}', all_varchar=true)").fetchall():
        print(row[0])