-- Runs automatically the first time the pharma-db container starts.
-- staging = raw-but-validated copies of the source files (the ODS)
-- ops     = pipeline monitoring tables (feed the DE dashboards later)
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS staging.stg_master (
    "MedicineID" VARCHAR(150),
    "InternalSKU" VARCHAR(150),
    "GTIN14" VARCHAR(20),
    "GenericName" VARCHAR(150),
    "FictionalBrandName" VARCHAR(150),
    "DiseaseCategory" VARCHAR(150),
    "ICD10Category" VARCHAR(150),
    "ATCCode" VARCHAR(150),
    "TherapeuticClass" VARCHAR(150),
    "DosageForm" VARCHAR(150),
    "Strength" VARCHAR(150),
    "RouteOfAdministration" VARCHAR(150),
    "PackSize" INTEGER,
    "BaseUnitOfMeasure" VARCHAR(150),
    "PrescriptionClass" VARCHAR(150),
    "ControlledMedicineFlag" VARCHAR(20),
    "ColdChainFlag" VARCHAR(20),
    "StorageMinTempC" INTEGER,
    "StorageMaxTempC" INTEGER,
    "MaxHumidityPct" INTEGER,
    "ShelfLifeMonths" INTEGER,
    "MinimumRemainingShelfLifeDays" INTEGER,
    "PrimarySupplierID" VARCHAR(150),
    "PrimaryPlantID" VARCHAR(150),
    "ManufacturingLeadTimeDays" INTEGER,
    "StandardBatchSizePacks" INTEGER,
    "SafetyStockDays" INTEGER,
    "ReorderReviewCycleDays" INTEGER,
    "UnitManufacturingCostUSD" NUMERIC(14,4),
    "WholesalePriceUSD" NUMERIC(14,4),
    "RecommendedRetailPriceUSD" NUMERIC(14,4),
    "ProductStatus" VARCHAR(150),
    "EffectiveFromDate" DATE,
    "SourceSystem" VARCHAR(150),
    batch_id VARCHAR(40) NOT NULL,
    source_file VARCHAR(200) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY ("MedicineID", "EffectiveFromDate")
);

CREATE TABLE IF NOT EXISTS staging.stg_sales (
    "SalesTransactionID" VARCHAR(150),
    "SalesDate" DATE,
    "SalesTimestampUTC" TIMESTAMPTZ,
    "SalesChannel" VARCHAR(150),
    "PharmacyID" VARCHAR(150),
    "PharmacyGLN" VARCHAR(20),
    "PharmacyName" VARCHAR(150),
    "PharmacyType" VARCHAR(150),
    "HospitalID" VARCHAR(150),
    "PharmacyCity" VARCHAR(150),
    "PharmacyState" VARCHAR(150),
    "CountryCode" VARCHAR(20),
    "PharmacyOrderID" VARCHAR(150),
    "PharmacyDeliveryID" VARCHAR(150),
    "PharmacyDeliveryDate" DATE,
    "DeliveryQuantityPacks" INTEGER,
    "DeliveryOTIFFlag" VARCHAR(20),
    "WarehouseLotID" VARCHAR(150),
    "SourceWarehouseID" VARCHAR(150),
    "ProductionBatchID" VARCHAR(150),
    "MedicineID" VARCHAR(150),
    "GTIN14" VARCHAR(20),
    "DiseaseCategory" VARCHAR(150),
    "GenericName" VARCHAR(150),
    "BatchExpiryDate" DATE,
    "DaysToExpiryAtSale" INTEGER,
    "QuantitySoldPacks" INTEGER,
    "UnitRetailPriceUSD" NUMERIC(14,4),
    "GrossSalesAmountUSD" NUMERIC(14,4),
    "DiscountAmountUSD" NUMERIC(14,4),
    "NetSalesAmountUSD" NUMERIC(14,4),
    "SalesTaxUSD" NUMERIC(14,4),
    "CostOfGoodsSoldUSD" NUMERIC(14,4),
    "GrossMarginUSD" NUMERIC(14,4),
    "PromotionCode" VARCHAR(150),
    "PrescriptionRequiredFlag" VARCHAR(20),
    "PrescriptionID" VARCHAR(150),
    "CustomerSegment" VARCHAR(150),
    "PayerType" VARCHAR(150),
    "PaymentMethod" VARCHAR(150),
    "EcommerceDeliveryStatus" VARCHAR(150),
    "ReturnFlag" VARCHAR(20),
    "ReturnedQuantityPacks" INTEGER,
    "SaleStatus" VARCHAR(150),
    "SourceSystem" VARCHAR(150),
    batch_id VARCHAR(40) NOT NULL,
    source_file VARCHAR(200) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY ("SalesTransactionID")
);

CREATE TABLE IF NOT EXISTS staging.stg_hospital_demand (
    "HospitalDemandRecordID" VARCHAR(150),
    "DemandMonth" DATE,
    "HospitalID" VARCHAR(150),
    "HospitalGLN" VARCHAR(20),
    "HospitalName" VARCHAR(150),
    "HospitalType" VARCHAR(150),
    "HospitalPharmacyID" VARCHAR(150),
    "City" VARCHAR(150),
    "State" VARCHAR(150),
    "CountryCode" VARCHAR(20),
    "LicensedBeds" INTEGER,
    "ICUBeds" INTEGER,
    "AverageOccupancyRatePct" INTEGER,
    "TraumaLevel" VARCHAR(150),
    "CatchmentPopulation" INTEGER,
    "MedicineID" VARCHAR(150),
    "GTIN14" VARCHAR(20),
    "GenericName" VARCHAR(150),
    "DiseaseCategory" VARCHAR(150),
    "ICD10Category" VARCHAR(150),
    "EstimatedDiseaseCases" INTEGER,
    "DiseaseRelatedAdmissions" INTEGER,
    "OutpatientEncounters" INTEGER,
    "ForecastDemandPacks" INTEGER,
    "RequestedQuantityPacks" INTEGER,
    "ApprovedQuantityPacks" INTEGER,
    "ReceivedQuantityPacks" INTEGER,
    "EmergencyRequestQuantityPacks" INTEGER,
    "OpeningStockPacks" INTEGER,
    "DispensedQuantityPacks" INTEGER,
    "ConsumedQuantityPacks" INTEGER,
    "WastageQuantityPacks" INTEGER,
    "ClosingStockPacks" INTEGER,
    "UnfulfilledDemandPacks" INTEGER,
    "StockoutDays" INTEGER,
    "ServiceLevelPct" NUMERIC(14,4),
    "MedicationRequestStatus" VARCHAR(150),
    "FormularyStatus" VARCHAR(150),
    "AverageLeadTimeDays" INTEGER,
    "DemandTrendIndex" NUMERIC(14,4),
    "SourceSystem" VARCHAR(150),
    batch_id VARCHAR(40) NOT NULL,
    source_file VARCHAR(200) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY ("HospitalDemandRecordID")
);

-- One row per file load (batch ingestion dashboard: duration, rows, success rate)
CREATE TABLE IF NOT EXISTS ops.batch_load_log (
    log_id          SERIAL PRIMARY KEY,
    batch_id        VARCHAR(40),
    source_name     VARCHAR(50),
    file_name       VARCHAR(200),
    started_at      TIMESTAMPTZ,
    ended_at        TIMESTAMPTZ,
    duration_sec    NUMERIC(10,3),
    rows_read       INTEGER,
    rows_loaded     INTEGER,
    rows_rejected   INTEGER,
    rows_duplicate  INTEGER,
    status          VARCHAR(10),   -- SUCCESS / FAILED
    error_message   TEXT
);

-- Rows that failed validation, with the reason (malformed/dropped record count)
CREATE TABLE IF NOT EXISTS ops.rejected_rows (
    reject_id    SERIAL PRIMARY KEY,
    batch_id     VARCHAR(40),
    source_name  VARCHAR(50),
    record_id    VARCHAR(60),
    reason       VARCHAR(200),
    rejected_at  TIMESTAMPTZ DEFAULT now()
);

-- One row per generator run (oversampling report statistics)
CREATE TABLE IF NOT EXISTS ops.generation_log (
    gen_id        SERIAL PRIMARY KEY,
    refresh_no    INTEGER,
    source_name   VARCHAR(50),
    period_start  DATE,
    period_end    DATE,
    rows_generated INTEGER,
    file_name     VARCHAR(200),
    generated_at  TIMESTAMPTZ DEFAULT now()
);

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

-- Storage layer monitoring (also created by the DAG if missing)
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
);
