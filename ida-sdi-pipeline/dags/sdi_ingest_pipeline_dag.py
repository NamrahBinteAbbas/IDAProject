"""
DAG 2 - Ingestion into the Postgres staging area (ODS)

Runs every 5 minutes. Each run:
  1. watch_incoming_folder : file watcher - waits until a new CSV appears in
                             data/incoming (skips the run quietly if none)
  2. ingest_master         : loads 01_master_data*.csv first (dimension data)
  3. ingest_sales          : loads 05_pharmacy_sales_data*.csv   } in parallel
     ingest_hospital_demand: loads 06_hospital_demand_data*.csv  }
  4. record_storage_metrics: row counts, size in MB and date coverage of each
                             staging table -> ops.storage_metrics
  5. staging_ready         : marker task. The transformation (DuckDB star
                             schema) and query layer tasks go after this one.

Every loaded file is moved to data/processed (or data/failed if it broke),
and its numbers (duration, rows, success) go to ops.batch_load_log.
"""
import glob
import os
import shutil
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.sensors.python import PythonSensor

from sdi_lib.ingest import SOURCES, load_file
from sdi_lib import storage_metrics

DATA_DIR = "/opt/airflow/data"
INCOMING_DIR = f"{DATA_DIR}/incoming"
PROCESSED_DIR = f"{DATA_DIR}/processed"
FAILED_DIR = f"{DATA_DIR}/failed"


def _files_for(source_name):
    prefix = SOURCES[source_name].file_prefix
    return sorted(glob.glob(os.path.join(INCOMING_DIR, f"{prefix}*.csv")))


def new_files_waiting():
    files = glob.glob(os.path.join(INCOMING_DIR, "*.csv"))
    if files:
        print(f"[file watcher] found {len(files)} new file(s): {[os.path.basename(f) for f in files]}")
    return bool(files)


def ingest_source(source_name, **context):
    files = _files_for(source_name)
    if not files:
        print(f"[ingest] no new {source_name} files")
        return
    conn = PostgresHook(postgres_conn_id="pharma_db").get_conn()
    batch_id = context["run_id"][-40:]
    failed = []
    try:
        for path in files:
            try:
                load_file(conn, source_name, path, batch_id)
                shutil.move(path, os.path.join(PROCESSED_DIR, os.path.basename(path)))
            except Exception as e:  # noqa: BLE001
                print(f"[ingest] FAILED {os.path.basename(path)}: {e}")
                shutil.move(path, os.path.join(FAILED_DIR, os.path.basename(path)))
                failed.append(os.path.basename(path))
    finally:
        conn.close()
    if failed:
        raise RuntimeError(f"{len(failed)} file(s) failed: {failed}")


def record_storage(**context):
    conn = PostgresHook(postgres_conn_id="pharma_db").get_conn()
    try:
        storage_metrics.record(conn, context["run_id"][-40:])
    finally:
        conn.close()


default_args = {"retries": 1, "retry_delay": timedelta(minutes=1)}

with DAG(
    dag_id="sdi_ingest_pipeline",
    description="File watcher + ingestion of Phase 1 files into Postgres staging",
    start_date=datetime(2026, 1, 1),
    schedule="*/5 * * * *",
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["sdi", "phase1", "ingestion"],
) as dag:
    watch = PythonSensor(
        task_id="watch_incoming_folder",
        python_callable=new_files_waiting,
        poke_interval=30,
        timeout=4 * 60,          # give up before the next run starts
        mode="reschedule",
        soft_fail=True,          # no files = "skipped", not "failed"
    )
    master = PythonOperator(task_id="ingest_master", python_callable=ingest_source,
                            op_kwargs={"source_name": "master"})
    sales = PythonOperator(task_id="ingest_sales", python_callable=ingest_source,
                           op_kwargs={"source_name": "sales"})
    hospital = PythonOperator(task_id="ingest_hospital_demand", python_callable=ingest_source,
                              op_kwargs={"source_name": "hospital_demand"})
    storage = PythonOperator(task_id="record_storage_metrics", python_callable=record_storage)
    ready = EmptyOperator(task_id="staging_ready")

    # >>> Transformation (DuckDB star schema) and query-layer tasks go after `ready`
    watch >> master >> [sales, hospital] >> storage >> ready
