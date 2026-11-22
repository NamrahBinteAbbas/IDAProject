# Data Generation & Ingestion Report: Phase 1 (SDI Data Mart)

<p style="text-align:center;margin-top:0">Intelligent Data Architectures, Fall 2026<br>Pharma Cold Chain DWH + BI Pipeline</p>

## 1. Goal

The source data ends in December 2025. To show a live, automated pipeline, we need **new data arriving over time**, so the warehouse and dashboards can be refreshed. The generator adds new rows to the 3 Phase-1 files. Old data is never replaced: the DWH keeps the full history.

## 2. Generation logic

| Rule | Why |
|---|---|
| Each refresh = one new 3-month period. Refresh 1 = Jan-Mar 2026, 2 = Apr-Jun, 3 = Jul-Sep, 4 = Oct-Dec 2026 (one full year) | At least two refreshes over different time periods, as required |
| A new refresh is generated **automatically every 30 minutes**. It waits if the previous files are not ingested yet, and stops after Refresh 4 | Simulates a live 24/7 automated pipeline with no manual steps |
| New sales copy the **same months one year earlier** (e.g. Jan-Mar 2025 → Jan-Mar 2026) | Keeps real seasonality (the data has a large January spike every year) |
| Sales quantity changed by ±15% and demand quantities by ±10% | New data looks realistic, not an exact copy |
| Money columns recalculated from unit price | Business rules still hold: Net = Gross − Discount, Margin = Net − COGS |
| Hospital demand keeps Approved ≤ Requested, Received ≤ Approved | Data stays logically valid |
| 5 medicines per refresh get a 3-10% price rise (new row, new EffectiveFromDate) | Lets us demonstrate SCD Type 2 in Dim_Medicine |
| ~0.2% of rows broken on purpose (empty MedicineID, invalid date, negative price/quantity) | Proves the validation step catches bad data |
| New unique IDs per refresh (e.g. SALE-R1-00000001) | No clash with existing keys |

**Why this much data:** each refresh is about one quarter of real activity, so it follows the real monthly volumes instead of a made-up number. This makes the dashboard changes after each refresh realistic and visible.

## 3. Data generated (statistics)

Generated rows (rows loaded after validation in brackets):

| Source | Original 2023-2025 | R1 Jan-Mar 2026 | R2 Apr-Jun 2026 | R3 Jul-Sep 2026 | R4 Oct-Dec 2026 | Total in staging |
|---|---|---|---|---|---|---|
| Master | 63 | 5 | 5 | 5 | 5 | 83 |
| Pharmacy sales | 500,000 | 112,794 (112,569) | 18,737 (18,700) | 17,575 (17,540) | 30,273 (30,213) | 679,022 |
| Hospital demand | 27,216 | 2,268 (2,264) | 2,268 (2,264) | 2,268 (2,264) | 2,268 (2,264) | 36,272 |

Refresh 1 is much larger than the others because the source data has a strong January peak (about 95,000 sales in Jan 2025 vs about 6,000 in May 2025). Refresh 4 is larger than 2 and 3 because sales also rise in November and December.

**Rows rejected by validation (all refreshes):**

| Source | Reason | Count |
|---|---|---|
| Sales | MedicineID is empty | 120 |
| Sales | Invalid SalesDate | 119 |
| Sales | UnitRetailPriceUSD is not > 0 | 118 |
| Hospital demand | MedicineID is empty | 8 |
| Hospital demand | Invalid DemandMonth | 4 |
| Hospital demand | RequestedQuantityPacks is negative | 4 |

## 4. Ingestion method

0. **Ingestion API (FastAPI, `http://localhost:8000`)** is the entry point for new files. `POST /ingest/{source}` accepts a CSV for master, sales or hospital demand, checks the file type and that all expected columns are present, and stores it in `data/incoming`. `GET /ingest/status` returns the latest load results and `GET /ingest/pending` lists files waiting to load.
1. **Generator (Airflow DAG `sdi_generate_data`)** runs every 30 minutes and writes the next period's CSV files into `data/incoming`. It can also be triggered by hand for a specific refresh. Files are written under a temporary name and renamed when complete, so a half-written file is never picked up.
2. **File watcher (Airflow DAG `sdi_ingest_pipeline`)** runs every 5 minutes. A Python sensor checks the folder. If there are no files, the run is skipped.
3. **Ingestion:** each file is read with Python (pandas), every row is validated, and good rows are bulk-loaded into Postgres using the `COPY` command. Rows whose key already exists are skipped, so loading a file twice is safe. Bad rows go to `ops.rejected_rows` with a reason.
4. **Order:** master data first (dimension data), then sales and hospital demand in parallel.
5. **Monitoring:** every file load writes duration, rows read/loaded/rejected and SUCCESS/FAILED to `ops.batch_load_log` (feeds the ingestion dashboard).

Sales load times measured on our laptop:

| Load | Sales rows | Sales load time | Status |
|---|---|---|---|
| Original | 500,000 | 106 s | SUCCESS |
| Refresh 1 | 112,794 | 11 s | SUCCESS |
| Refresh 2 | 18,737 | 4 s | SUCCESS |

## 5. Storage

Postgres (Docker) database `pharma_dwh`: schema `staging` (one table per source file, plus `batch_id`, `source_file`, `loaded_at` on every row) and schema `ops` (monitoring). Indexes on dates, MedicineID, HospitalID and batch_id speed up the transformation step (a one-quarter sales query uses the date index: ~15 ms).

After every load, an Airflow task records the row count, size in MB and date coverage of each staging table in `ops.storage_metrics` (feeds the storage dashboard). After all 4 refreshes:

| Table | Rows | Size (MB, incl. indexes) | Date coverage |
|---|---|---|---|
| stg_sales | 679,022 | 378.7 | 30 Jan 2023 to 31 Dec 2026 |
| stg_hospital_demand | 36,272 | 16.6 | Jan 2023 to Dec 2026 |
| stg_master | 83 | 0.1 | price versions from Jan 2023 to Oct 2026 |
| Whole database | | 403.3 | |

## 6. Assumptions

- Phase 1 uses only files 01, 05 and 06. The IoT streaming file belongs to Phase 3.
- Each refresh covers 3 months. One refresh runs every 30 minutes to speed up the demo. In a real company each refresh would arrive daily or monthly.
- No new medicines, hospitals or pharmacies are created, only new transactions and price changes.
- Quantity changes of ±10-15% are realistic month-to-month variation.
- Rejected rows are kept for review, not fixed automatically.
