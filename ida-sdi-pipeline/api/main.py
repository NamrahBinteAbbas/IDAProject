"""
Data Ingestion API - Phase 1

The entry point for new data. A source system (or a person, through the
web page at http://localhost:8000/docs) sends a CSV file to the API.
The API checks it and drops it into data/incoming. The Airflow file
watcher then loads it into the Postgres staging area.

Endpoints
  GET  /health                 is the API running?
  POST /ingest/{source}        upload a CSV (source = master, sales, hospital_demand)
  GET  /ingest/pending         files waiting to be loaded by Airflow
  GET  /ingest/status          latest load results from ops.batch_load_log
"""
import csv
import io
import os
from datetime import datetime

import psycopg2
from fastapi import FastAPI, File, HTTPException, UploadFile

DATA_DIR = os.environ.get("DATA_DIR", "/data")
INCOMING_DIR = os.path.join(DATA_DIR, "incoming")
SOURCE_DIR = os.path.join(DATA_DIR, "source")
DB_URL = os.environ.get("PHARMA_DB_URL", "postgresql://pharma:pharma@pharma-db:5432/pharma_dwh")

# source name -> (file name prefix, original file used to check the columns)
SOURCES = {
    "master": ("01_master_data", "01_master_data.csv"),
    "sales": ("05_pharmacy_sales_data", "05_pharmacy_sales_data.csv"),
    "hospital_demand": ("06_hospital_demand_data", "06_hospital_demand_data.csv"),
}

app = FastAPI(
    title="Pharma SDI Ingestion API",
    description="Send new source files into the pipeline. Airflow loads them into Postgres staging.",
    version="1.0",
)


def _expected_columns(source):
    with open(os.path.join(SOURCE_DIR, SOURCES[source][1]), newline="", encoding="utf-8") as f:
        return next(csv.reader(f))


@app.get("/health")
def health():
    return {"status": "ok", "time": datetime.now().isoformat(timespec="seconds")}


@app.post("/ingest/{source}")
async def ingest(source: str, file: UploadFile = File(...)):
    if source not in SOURCES:
        raise HTTPException(404, f"Unknown source '{source}'. Use one of {list(SOURCES)}")
    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(400, "Only .csv files are accepted")

    content = await file.read()
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise HTTPException(400, "File must be UTF-8 text")
    reader = csv.reader(io.StringIO(text))
    header = next(reader, None)
    if header is None:
        raise HTTPException(400, "File is empty")

    expected = _expected_columns(source)
    missing = [c for c in expected if c not in header]
    if missing:
        raise HTTPException(422, {"error": "Columns missing", "missing": missing})
    rows = sum(1 for _ in reader)
    if rows == 0:
        raise HTTPException(400, "File has a header but no rows")

    # write under a temp name, then rename, so the file watcher never sees a half-written file
    stamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
    name = f"{SOURCES[source][0]}_API_{stamp}.csv"
    os.makedirs(INCOMING_DIR, exist_ok=True)
    tmp = os.path.join(INCOMING_DIR, name + ".tmp")
    with open(tmp, "wb") as f:
        f.write(content)
    os.replace(tmp, os.path.join(INCOMING_DIR, name))

    return {
        "status": "accepted",
        "source": source,
        "stored_as": name,
        "rows_received": rows,
        "next_step": "Airflow file watcher will load it into staging within 5 minutes",
    }


@app.get("/ingest/pending")
def pending():
    files = sorted(f for f in os.listdir(INCOMING_DIR) if f.endswith(".csv")) if os.path.isdir(INCOMING_DIR) else []
    return {"waiting_to_load": files, "count": len(files)}


@app.get("/ingest/status")
def status(limit: int = 20):
    try:
        with psycopg2.connect(DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                """SELECT source_name, file_name, rows_read, rows_loaded, rows_rejected,
                          duration_sec, status, ended_at
                   FROM ops.batch_load_log ORDER BY log_id DESC LIMIT %s""",
                (limit,),
            )
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, r)) for r in cur.fetchall()]
    except psycopg2.Error as e:
        raise HTTPException(503, f"Database not reachable: {e}")
