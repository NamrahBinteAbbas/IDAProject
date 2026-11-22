"""
Storage layer monitoring.

After every load, records for each staging table:
  * row count            (SELECT COUNT(*))
  * storage size in MB   (table + indexes, from Postgres)
  * date coverage        (first date, last date, number of days covered)
plus the size of the whole database. Results go to ops.storage_metrics,
which feeds the storage dashboard.
"""

CREATE_SQL = """
CREATE TABLE IF NOT EXISTS ops.storage_metrics (
    metric_id      SERIAL PRIMARY KEY,
    captured_at    TIMESTAMPTZ DEFAULT now(),
    batch_id       VARCHAR(40),
    table_name     VARCHAR(60),
    row_count      BIGINT,
    size_mb        NUMERIC(12,3),
    first_date     DATE,
    last_date      DATE,
    coverage_days  INTEGER
)"""

# table -> its main date column
TABLES = {
    "staging.stg_master": "EffectiveFromDate",
    "staging.stg_sales": "SalesDate",
    "staging.stg_hospital_demand": "DemandMonth",
}


def record(conn, batch_id):
    rows = []
    with conn.cursor() as cur:
        cur.execute(CREATE_SQL)
        for table, date_col in TABLES.items():
            cur.execute(
                f"""SELECT count(*),
                           pg_total_relation_size('{table}') / 1024.0 / 1024.0,
                           min("{date_col}"), max("{date_col}")
                    FROM {table}"""
            )
            count, size_mb, first, last = cur.fetchone()
            days = (last - first).days if first and last else None
            rows.append((batch_id, table, count, size_mb, first, last, days))
        cur.execute("SELECT pg_database_size(current_database()) / 1024.0 / 1024.0")
        rows.append((batch_id, "DATABASE TOTAL", None, cur.fetchone()[0], None, None, None))
        cur.executemany(
            """INSERT INTO ops.storage_metrics
               (batch_id, table_name, row_count, size_mb, first_date, last_date, coverage_days)
               VALUES (%s,%s,%s,%s,%s,%s,%s)""",
            rows,
        )
    conn.commit()
    for r in rows:
        print(f"[storage] {r[1]:30s} rows={r[2]} size_mb={float(r[3]):.2f} {r[4]} -> {r[5]}")
    return rows
