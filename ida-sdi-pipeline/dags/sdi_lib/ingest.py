"""
Data Ingestion Layer - Phase 1

Reads a CSV file from data/incoming, checks every row, loads the good rows
into the Postgres staging area (the ODS), saves the bad rows with a reason,
and writes one monitoring row per file into ops.batch_load_log.

New rows are ADDED to staging. If a row with the same ID is already there,
it is skipped (counted as a duplicate), so loading the same file twice does
no harm.
"""
import io
import time
from dataclasses import dataclass
from datetime import datetime, timezone

import pandas as pd


@dataclass
class Source:
    name: str            # short name used in logs
    file_prefix: str     # files starting with this belong to this source
    table: str           # staging table
    key_cols: list       # primary key columns
    record_id_col: str   # column shown in the rejected-rows table


SOURCES = {
    "master": Source("master", "01_master_data", "staging.stg_master",
                     ["MedicineID", "EffectiveFromDate"], "MedicineID"),
    "sales": Source("sales", "05_pharmacy_sales_data", "staging.stg_sales",
                    ["SalesTransactionID"], "SalesTransactionID"),
    "hospital_demand": Source("hospital_demand", "06_hospital_demand_data",
                              "staging.stg_hospital_demand",
                              ["HospitalDemandRecordID"], "HospitalDemandRecordID"),
}


# ------------------------------------------------------------ validation
def _bad_date(series):
    parsed = pd.to_datetime(series, format="%Y-%m-%d", errors="coerce")
    return parsed.isna()


def _not_positive(series):
    n = pd.to_numeric(series, errors="coerce")
    return n.isna() | (n <= 0)


def _negative(series):
    n = pd.to_numeric(series, errors="coerce")
    return n.isna() | (n < 0)


def validate(source_name, df):
    """Return (good_rows, rejected) where rejected has record_id + reason."""
    checks = []  # list of (mask_of_bad_rows, reason)
    checks.append((df["MedicineID"].isna() | (df["MedicineID"].str.strip() == ""),
                   "MedicineID is empty"))

    if source_name == "master":
        checks.append((_bad_date(df["EffectiveFromDate"]), "Invalid EffectiveFromDate"))
        for c in ["UnitManufacturingCostUSD", "WholesalePriceUSD", "RecommendedRetailPriceUSD"]:
            checks.append((_not_positive(df[c]), f"{c} is not > 0"))

    elif source_name == "sales":
        checks.append((df["SalesTransactionID"].isna(), "SalesTransactionID is empty"))
        checks.append((_bad_date(df["SalesDate"]), "Invalid SalesDate"))
        checks.append((_not_positive(df["UnitRetailPriceUSD"]), "UnitRetailPriceUSD is not > 0"))
        checks.append((_not_positive(df["QuantitySoldPacks"]), "QuantitySoldPacks is not > 0"))

    elif source_name == "hospital_demand":
        checks.append((df["HospitalID"].isna(), "HospitalID is empty"))
        checks.append((_bad_date(df["DemandMonth"]), "Invalid DemandMonth"))
        for c in ["ForecastDemandPacks", "RequestedQuantityPacks", "ConsumedQuantityPacks"]:
            checks.append((_negative(df[c]), f"{c} is negative"))

    reason = pd.Series([None] * len(df), index=df.index, dtype=object)
    for mask, text in checks:
        reason = reason.where(~(mask & reason.isna()), text)  # keep first reason

    bad = reason.notna()
    rejected = pd.DataFrame({
        "record_id": df.loc[bad, SOURCES[source_name].record_id_col].astype(str),
        "reason": reason[bad],
    })
    return df.loc[~bad].copy(), rejected


# ------------------------------------------------------------- loading
def _copy_df(cur, df, table, columns):
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False, columns=columns)
    buf.seek(0)
    col_sql = ", ".join(f'"{c}"' if c[0].isupper() else c for c in columns)
    cur.copy_expert(f"COPY {table} ({col_sql}) FROM STDIN WITH (FORMAT csv, NULL '')", buf)


def load_file(conn, source_name, file_path, batch_id):
    """Load one file. Returns a dict with the monitoring numbers."""
    src = SOURCES[source_name]
    file_name = file_path.replace("\\", "/").split("/")[-1]
    started = datetime.now(timezone.utc)
    t0 = time.perf_counter()
    stats = dict(batch_id=batch_id, source_name=source_name, file_name=file_name,
                 started_at=started, rows_read=0, rows_loaded=0, rows_rejected=0,
                 rows_duplicate=0, status="FAILED", error_message=None)
    try:
        df = pd.read_csv(file_path, dtype=str)
        stats["rows_read"] = len(df)

        good, rejected = validate(source_name, df)
        good = good.drop_duplicates(subset=src.key_cols)
        good["batch_id"] = batch_id
        good["source_file"] = file_name
        columns = list(good.columns)

        with conn.cursor() as cur:
            # load into a temp copy first, then add only rows that are new
            tmp = f"tmp_{source_name}"
            cur.execute(f"CREATE TEMP TABLE {tmp} (LIKE {src.table} INCLUDING DEFAULTS) ON COMMIT DROP")
            _copy_df(cur, good, tmp, columns)
            col_sql = ", ".join(f'"{c}"' if c[0].isupper() else c for c in columns)
            cur.execute(
                f"INSERT INTO {src.table} ({col_sql}) SELECT {col_sql} FROM {tmp} "
                f"ON CONFLICT DO NOTHING"
            )
            stats["rows_loaded"] = cur.rowcount
            stats["rows_duplicate"] = len(good) - cur.rowcount

            if len(rejected):
                rejected = rejected.assign(batch_id=batch_id, source_name=source_name)
                _copy_df(cur, rejected, "ops.rejected_rows",
                         ["batch_id", "source_name", "record_id", "reason"])
            stats["rows_rejected"] = len(rejected)
        conn.commit()
        stats["status"] = "SUCCESS"
    except Exception as e:  # noqa: BLE001 - we log every failure
        conn.rollback()
        stats["error_message"] = str(e)[:2000]
        raise
    finally:
        stats["ended_at"] = datetime.now(timezone.utc)
        stats["duration_sec"] = round(time.perf_counter() - t0, 3)
        _write_log(conn, stats)
        print(f"[ingest] {source_name:16s} {file_name}: read={stats['rows_read']:,} "
              f"loaded={stats['rows_loaded']:,} rejected={stats['rows_rejected']:,} "
              f"duplicate={stats['rows_duplicate']:,} {stats['duration_sec']}s {stats['status']}")
    return stats


def _write_log(conn, s):
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO ops.batch_load_log (batch_id, source_name, file_name, started_at,
                   ended_at, duration_sec, rows_read, rows_loaded, rows_rejected,
                   rows_duplicate, status, error_message)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (s["batch_id"], s["source_name"], s["file_name"], s["started_at"],
             s["ended_at"], s["duration_sec"], s["rows_read"], s["rows_loaded"],
             s["rows_rejected"], s["rows_duplicate"], s["status"], s["error_message"]),
        )
    conn.commit()
