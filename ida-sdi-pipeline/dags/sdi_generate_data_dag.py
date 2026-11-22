"""
DAG 1 - Data Oversampling Layer (runs automatically)

Every 30 minutes this DAG simulates a new batch of business data arriving:
  * If staging is still empty, it sends the ORIGINAL 3 CSVs through first.
  * Otherwise it generates the NEXT quarter after the last one generated:
        refresh 1 = Jan-Mar 2026, 2 = Apr-Jun, 3 = Jul-Sep, 4 = Oct-Dec 2026
  * It stops after refresh 4 (one full year of new data).
  * It waits (skips) if the previous files have not been ingested yet, so
    batches never pile up.

The ingestion DAG (sdi_ingest_pipeline) notices the new files on its own,
so the whole pipeline runs with no clicks.

Manual use: Trigger DAG w/ config and set refresh_no to 0-4 to force a
specific refresh. Leave it at -1 for the automatic "next refresh" logic.
"""
import glob
import os
import shutil
from datetime import datetime

from airflow import DAG
from airflow.exceptions import AirflowSkipException
from airflow.models.param import Param
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook

from sdi_lib import generate_data

DATA_DIR = "/opt/airflow/data"
SOURCE_DIR = f"{DATA_DIR}/source"
INCOMING_DIR = f"{DATA_DIR}/incoming"
ORIGINAL_FILES = [generate_data.MASTER_FILE, generate_data.SALES_FILE, generate_data.HOSP_FILE]
AUTO = -1


def _hook():
    return PostgresHook(postgres_conn_id="pharma_db")


def _log(stats):
    for s in stats:
        _hook().run(
            """INSERT INTO ops.generation_log
               (refresh_no, source_name, period_start, period_end, rows_generated, file_name)
               VALUES (%s,%s,%s,%s,%s,%s)""",
            parameters=(s["refresh_no"], s["source_name"], s["period_start"],
                        s["period_end"], s["rows_generated"], s["file_name"]),
        )


def copy_original_files():
    """Refresh 0: send the original data through the pipeline once."""
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")
    stats = []
    for f, source in zip(ORIGINAL_FILES, ["master", "sales", "hospital_demand"]):
        name = f.replace(".csv", f"_R0_{stamp}.csv")
        tmp = os.path.join(INCOMING_DIR, name + ".tmp")
        shutil.copyfile(os.path.join(SOURCE_DIR, f), tmp)
        os.replace(tmp, os.path.join(INCOMING_DIR, name))
        stats.append({"refresh_no": 0, "source_name": source, "period_start": "2023-01-01",
                      "period_end": "2025-12-31", "rows_generated": None, "file_name": name})
        print(f"[initial load] copied {f} -> {name}")
    return stats


def next_refresh_no():
    """Pick what to generate next, based on what is already in the database."""
    loaded = _hook().get_first('SELECT count(*) FROM staging.stg_sales')[0]
    if loaded == 0:
        return 0
    last = _hook().get_first("SELECT max(refresh_no) FROM ops.generation_log WHERE refresh_no > 0")[0]
    return (last or 0) + 1


def run_generator(**context):
    chosen = int(context["params"]["refresh_no"])
    if chosen == AUTO:
        if glob.glob(os.path.join(INCOMING_DIR, "*.csv")):
            raise AirflowSkipException("Previous files not ingested yet - waiting for next run")
        chosen = next_refresh_no()
        if chosen > generate_data.MAX_REFRESH:
            raise AirflowSkipException(f"All {generate_data.MAX_REFRESH} refreshes done - nothing to generate")
    print(f"[generator] running refresh {chosen}")

    if chosen == 0:
        _log(copy_original_files())
    else:
        _log(generate_data.run(chosen, SOURCE_DIR, INCOMING_DIR))


with DAG(
    dag_id="sdi_generate_data",
    description="Oversampling layer: makes new source files for the next time period",
    start_date=datetime(2026, 1, 1),
    schedule="*/30 * * * *",   # a new batch of data every 30 minutes
    catchup=False,
    max_active_runs=1,
    params={"refresh_no": Param(AUTO, type="integer", minimum=-1, maximum=generate_data.MAX_REFRESH,
                                description="-1 = automatic (next period), 0 = original data, "
                                            "1-4 = a specific quarter of 2026")},
    tags=["sdi", "phase1", "oversampling"],
) as dag:
    PythonOperator(task_id="generate_source_files", python_callable=run_generator)
