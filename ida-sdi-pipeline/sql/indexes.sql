-- Indexes on the staging tables (storage-layer optimisation).
-- They speed up the columns the transformation step filters/joins on:
--   dates (load one period at a time), MedicineID/HospitalID (dimension lookups),
--   batch_id (pick up only rows from the newest refresh).
CREATE INDEX IF NOT EXISTS ix_stg_sales_date      ON staging.stg_sales ("SalesDate");
CREATE INDEX IF NOT EXISTS ix_stg_sales_medicine  ON staging.stg_sales ("MedicineID");
CREATE INDEX IF NOT EXISTS ix_stg_sales_pharmacy  ON staging.stg_sales ("PharmacyID");
CREATE INDEX IF NOT EXISTS ix_stg_sales_batch     ON staging.stg_sales (batch_id);
CREATE INDEX IF NOT EXISTS ix_stg_hosp_month      ON staging.stg_hospital_demand ("DemandMonth");
CREATE INDEX IF NOT EXISTS ix_stg_hosp_hosp_med   ON staging.stg_hospital_demand ("HospitalID", "MedicineID");
CREATE INDEX IF NOT EXISTS ix_stg_hosp_batch      ON staging.stg_hospital_demand (batch_id);
CREATE INDEX IF NOT EXISTS ix_load_log_started    ON ops.batch_load_log (started_at);
