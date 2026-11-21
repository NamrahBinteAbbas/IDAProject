import duckdb
out = open("columns.txt", "w", encoding="utf-8")
for f in ["01_master_data.csv", "05_pharmacy_sales_data.csv", "06_hospital_demand_data.csv"]:
    out.write("\n== " + f + "\n")
    rel = duckdb.sql(f"SELECT * FROM read_csv('data/{f}', all_varchar=true) LIMIT 2")
    for name, value in zip(rel.columns, rel.fetchall()[0]):
        out.write(f"{name} = {value}\n")
out.close()
print("done, now open columns.txt")