-- =====================================================================
-- Phase 1: Sales & Demand Intelligence (SDI) Data Mart, DuckDB
-- Enterprise-Grade Dimensional Model & ETL Script
-- Builds: DimDate, DimLocation, DimMedicine, DimHospital, DimPharmacy,
--         Fact_Sales, Fact_Hospital_Demand, etl_rejects,
--         and Analytical BI Views (Query Layer)
-- =====================================================================

-- =====================================================================
-- SECTION 0: Raw Data Staging Sources
-- =====================================================================
CREATE OR REPLACE VIEW raw_master AS
  SELECT * FROM read_csv('data/01_master_data.csv', header = true, all_varchar = true);
CREATE OR REPLACE VIEW raw_sales AS
  SELECT * FROM read_csv('data/05_pharmacy_sales_data.csv', header = true, all_varchar = true);
CREATE OR REPLACE VIEW raw_demand AS
  SELECT * FROM read_csv('data/06_hospital_demand_data.csv', header = true, all_varchar = true);

CREATE OR REPLACE TABLE etl_params AS SELECT current_date AS load_date;

-- =====================================================================
-- SECTION 1: Sequences & Dimension/Fact DDL
-- =====================================================================
CREATE SEQUENCE IF NOT EXISTS seq_location START 1;
CREATE SEQUENCE IF NOT EXISTS seq_medicine START 1;
CREATE SEQUENCE IF NOT EXISTS seq_hospital START 1;
CREATE SEQUENCE IF NOT EXISTS seq_pharmacy START 1;
CREATE SEQUENCE IF NOT EXISTS seq_sales START 1;
CREATE SEQUENCE IF NOT EXISTS seq_demand START 1;

CREATE TABLE IF NOT EXISTS DimDate (
  DateKey      INTEGER PRIMARY KEY,
  FullDate     DATE NOT NULL,
  DayOfMonth   SMALLINT,
  DayName      VARCHAR,
  IsWeekend    BOOLEAN,
  WeekOfYear   SMALLINT,
  MonthNum     SMALLINT,
  MonthName    VARCHAR,
  YearMonth    VARCHAR,
  Quarter      VARCHAR,
  Year         SMALLINT,
  Season       VARCHAR
);

CREATE TABLE IF NOT EXISTS DimLocation (
  LocationKey  INTEGER PRIMARY KEY DEFAULT nextval('seq_location'),
  City         VARCHAR,
  State        VARCHAR,
  Country      VARCHAR
);

CREATE TABLE IF NOT EXISTS DimMedicine (
  MedicineKey       INTEGER PRIMARY KEY DEFAULT nextval('seq_medicine'),
  MedicineID        VARCHAR NOT NULL,
  InternalSKU       VARCHAR,
  GTIN14            VARCHAR,
  MedName           VARCHAR,
  ICD10Category     VARCHAR,
  DiseaseCategory   VARCHAR,
  TherapeuticClass  VARCHAR,
  DosageStrength    VARCHAR,
  Route             VARCHAR,
  PackSizeBand      VARCHAR,
  BaseUOM           VARCHAR,
  PrescriptionClass VARCHAR,
  ColdChainFlag     BOOLEAN,
  ShelfLifeBand     VARCHAR,
  ProductStatus     VARCHAR,
  EffectiveFrom     DATE,
  EffectiveTo       DATE,
  IsCurrent         BOOLEAN
);

CREATE TABLE IF NOT EXISTS DimHospital (
  HospitalKey   INTEGER PRIMARY KEY DEFAULT nextval('seq_hospital'),
  HospitalID    VARCHAR NOT NULL,
  HospitalGLN   VARCHAR,
  HospitalName  VARCHAR,
  HospitalType  VARCHAR,
  EffectiveFrom DATE,
  EffectiveTo   DATE,
  IsCurrent     BOOLEAN
);

-- Note: SalesChannel is removed from DimPharmacy because individual pharmacies
-- sell via both Physical Pharmacy (in-store) and E-commerce channels.
CREATE TABLE IF NOT EXISTS DimPharmacy (
  PharmacyKey   INTEGER PRIMARY KEY DEFAULT nextval('seq_pharmacy'),
  PharmacyID    VARCHAR NOT NULL,
  PharmacyGLN   VARCHAR,
  PharmacyName  VARCHAR,
  PharmacyType  VARCHAR,
  EffectiveFrom DATE,
  EffectiveTo   DATE,
  IsCurrent     BOOLEAN
);

CREATE TABLE IF NOT EXISTS Fact_Sales (
  SalesKey             BIGINT PRIMARY KEY DEFAULT nextval('seq_sales'),
  SaleDateKey          INTEGER,
  MedicineKey          INTEGER,
  PharmacyKey          INTEGER,
  PharmacyLocationKey  INTEGER,
  SalesTransactionID   VARCHAR,
  CustomerSegment      VARCHAR,
  SalesChannel         VARCHAR,          -- Raw channel from source: Physical Pharmacy / Ecommerce
  ReportingChannel     VARCHAR,          -- Standardized 3 channels: Retail / Hospital / E-commerce
  DeliveryOTIFFlag     VARCHAR,          -- Per-sale delivery OTIF flag
  QuantitySoldPacks    INTEGER,
  GrossSalesAmountUSD  DECIMAL(12,2),
  DiscountAmountUSD    DECIMAL(12,2),
  NetSalesAmountUSD    DECIMAL(12,2),
  CostOfGoodsSoldUSD   DECIMAL(12,2),
  GrossMarginUSD       DECIMAL(12,2),
  DaysToExpiryAtSale   INTEGER,
  StandardCost         DECIMAL(10,2),
  ListTradePrice       DECIMAL(10,2),
  MRP                  DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS Fact_Hospital_Demand (
  DemandKey                      BIGINT PRIMARY KEY DEFAULT nextval('seq_demand'),
  DemandMonthKey                 INTEGER,
  MedicineKey                    INTEGER,
  HospitalKey                    INTEGER,
  HospitalLocationKey            INTEGER,
  HospitalDemandRecordID         VARCHAR,
  EstimatedDiseaseCases          INTEGER,
  DiseaseRelatedAdmissions       INTEGER,
  OutpatientEncounters           INTEGER,
  ForecastDemandPacks            INTEGER,
  RequestedQuantityPacks         INTEGER,
  ApprovedQuantityPacks          INTEGER,
  ReceivedQuantityPacks          INTEGER,
  EmergencyRequestQuantityPacks  INTEGER,
  UnfulfilledDemandPacks         INTEGER, -- Calculated: GREATEST(Requested - Received, 0)
  OpeningStockPacks              INTEGER,
  DispensedQuantityPacks         INTEGER,
  ConsumedQuantityPacks          INTEGER,
  WastageQuantityPacks           INTEGER,
  ClosingStockPacks              INTEGER,
  DemandTrendIndex               DECIMAL(8,3),
  LicensedBeds                   INTEGER,
  ICUBeds                        INTEGER,
  AverageOccupancyRatePct        DECIMAL(5,2)
);

CREATE TABLE IF NOT EXISTS etl_rejects (
  source_table VARCHAR,
  record_id    VARCHAR,
  reason       VARCHAR,
  logged_at    TIMESTAMP
);

-- Analytical Query Observability Logging Table (Phase 1 DE Rubric requirement: 2%)
CREATE TABLE IF NOT EXISTS query_performance_log (
  log_id           BIGINT PRIMARY KEY DEFAULT nextval('seq_sales'),
  query_id         VARCHAR,
  query_name       VARCHAR,
  execution_ms     DOUBLE,
  rows_returned    INTEGER,
  status           VARCHAR,
  executed_at      TIMESTAMP DEFAULT current_timestamp
);

-- Complete mapping for all 13 distinct dosage forms in 01_master_data.csv
CREATE OR REPLACE TABLE map_dosage_form (raw_form VARCHAR, abbr VARCHAR);
INSERT INTO map_dosage_form VALUES
  ('Tablet', 'Tab'),
  ('Capsule', 'Cap'),
  ('Modified-release tablet', 'MR Tab'),
  ('Gastro-resistant tablet', 'GR Tab'),
  ('Gastro-resistant capsule', 'GR Cap'),
  ('Effervescent tablet', 'Eff Tab'),
  ('Solution for injection', 'Inj Sol'),
  ('Pre-filled pen', 'Pen'),
  ('Metered-dose inhaler', 'MDI'),
  ('Dry-powder inhaler', 'DPI'),
  ('Inhalation capsule', 'Inh Cap'),
  ('Oral solution', 'Oral Sol'),
  ('Nebulizer solution', 'Neb Sol');

CREATE TABLE IF NOT EXISTS map_pharmacy_name (raw_name VARCHAR, std_name VARCHAR);

-- =====================================================================
-- SECTION 2: Staging Views (Data Cleansing & Transformation)
-- =====================================================================
CREATE OR REPLACE VIEW stg_medicine AS
SELECT
  upper(trim(MedicineID))                                    AS MedicineID,
  upper(trim(InternalSKU))                                   AS InternalSKU,
  lpad(trim(GTIN14), 14, '0')                                AS GTIN14,
  regexp_replace(trim(GenericName), '\s+', ' ', 'g')         AS MedName,
  upper(trim(ICD10Category))                                 AS ICD10Category,
  trim(DiseaseCategory)                                      AS DiseaseCategory,
  trim(TherapeuticClass)                                     AS TherapeuticClass,
  COALESCE(m.abbr, left(trim(DosageForm), 3)) || ' ' || replace(trim(Strength), ' ', '') AS DosageStrength,
  trim(RouteOfAdministration)                                AS Route,
  CASE WHEN TRY_CAST(PackSize AS INTEGER) > 15 THEN 'Large' ELSE 'Small' END AS PackSizeBand,
  upper(left(trim(BaseUnitOfMeasure), 1)) || lower(substr(trim(BaseUnitOfMeasure), 2)) AS BaseUOM,
  trim(PrescriptionClass)                                    AS PrescriptionClass,
  COALESCE(upper(trim(ColdChainFlag)) IN ('Y','YES','TRUE','1'), FALSE) AS ColdChainFlag,
  CASE WHEN TRY_CAST(ShelfLifeMonths AS INTEGER) <= 24 THEN 'Short'
       WHEN TRY_CAST(ShelfLifeMonths AS INTEGER) >= 36 THEN 'Long'
       ELSE 'Medium' END                                     AS ShelfLifeBand,
  trim(ProductStatus)                                        AS ProductStatus,
  TRY_CAST(EffectiveFromDate AS DATE)                        AS EffectiveFromDate,
  TRY_CAST(UnitManufacturingCostUSD  AS DECIMAL(10,2))       AS StandardCost,
  TRY_CAST(WholesalePriceUSD         AS DECIMAL(10,2))       AS ListTradePrice,
  TRY_CAST(RecommendedRetailPriceUSD AS DECIMAL(10,2))       AS MRP
FROM raw_master r
LEFT JOIN map_dosage_form m ON lower(trim(r.DosageForm)) = lower(m.raw_form);

CREATE OR REPLACE VIEW stg_sales AS
SELECT
  trim(s.SalesTransactionID)                                 AS SalesTransactionID,
  COALESCE(TRY_CAST(s.SalesDate AS DATE), CAST(TRY_STRPTIME(s.SalesDate, '%m/%d/%Y') AS DATE)) AS SaleDate,
  trim(s.SalesChannel)                                       AS SalesChannel,
  -- Reconcile 3 business reporting channels: Retail vs Hospital vs E-commerce
  CASE 
    WHEN trim(s.SalesChannel) = 'Ecommerce' THEN 'E-commerce'
    WHEN trim(s.PharmacyType) = 'Hospital Pharmacy' THEN 'Hospital'
    ELSE 'Retail'
  END                                                        AS ReportingChannel,
  upper(trim(s.PharmacyID))                                  AS PharmacyID,
  trim(s.PharmacyGLN)                                        AS PharmacyGLN,
  COALESCE(pn.std_name, regexp_replace(trim(s.PharmacyName), '\s+', ' ', 'g')) AS PharmacyName,
  list_aggr(regexp_extract_all(upper(trim(s.PharmacyType)), '\b([A-Z])', 1), 'string_agg', '.') || '.' AS PharmacyType,
  trim(s.DeliveryOTIFFlag)                                   AS DeliveryOTIFFlag,
  upper(trim(s.MedicineID))                                  AS MedicineID,
  trim(s.PharmacyCity)                                       AS City,
  trim(s.PharmacyState)                                      AS State,
  trim(s.CountryCode)                                        AS Country,
  trim(s.CustomerSegment)                                    AS CustomerSegment,
  TRY_CAST(s.QuantitySoldPacks   AS INTEGER)                 AS QuantitySoldPacks,
  TRY_CAST(s.DaysToExpiryAtSale  AS INTEGER)                 AS DaysToExpiryAtSale,
  TRY_CAST(s.GrossSalesAmountUSD AS DECIMAL(12,2))           AS GrossSalesAmountUSD,
  TRY_CAST(s.DiscountAmountUSD   AS DECIMAL(12,2))           AS DiscountAmountUSD,
  TRY_CAST(s.CostOfGoodsSoldUSD  AS DECIMAL(12,2))           AS CostOfGoodsSoldUSD,
  TRY_CAST(s.GrossMarginUSD      AS DECIMAL(12,2))           AS GrossMarginUSD
FROM raw_sales s
LEFT JOIN map_pharmacy_name pn ON pn.raw_name = trim(s.PharmacyName);

CREATE OR REPLACE VIEW stg_demand AS
SELECT
  trim(HospitalDemandRecordID)                               AS HospitalDemandRecordID,
  CAST(date_trunc('month', TRY_CAST(DemandMonth AS DATE)) AS DATE) AS DemandMonth,
  upper(trim(HospitalID))                                    AS HospitalID,
  trim(HospitalGLN)                                          AS HospitalGLN,
  regexp_replace(trim(HospitalName), '\s+', ' ', 'g')        AS HospitalName,
  trim(HospitalType)                                         AS HospitalType,
  lpad(trim(GTIN14), 14, '0')                                AS GTIN14,
  trim(City)                                                 AS City,
  trim(State)                                                AS State,
  trim(CountryCode)                                          AS Country,
  TRY_CAST(EstimatedDiseaseCases         AS INTEGER)         AS EstimatedDiseaseCases,
  TRY_CAST(DiseaseRelatedAdmissions      AS INTEGER)         AS DiseaseRelatedAdmissions,
  TRY_CAST(OutpatientEncounters          AS INTEGER)         AS OutpatientEncounters,
  TRY_CAST(ForecastDemandPacks           AS INTEGER)         AS ForecastDemandPacks,
  TRY_CAST(RequestedQuantityPacks        AS INTEGER)         AS RequestedQuantityPacks,
  TRY_CAST(ApprovedQuantityPacks         AS INTEGER)         AS ApprovedQuantityPacks,
  TRY_CAST(ReceivedQuantityPacks         AS INTEGER)         AS ReceivedQuantityPacks,
  TRY_CAST(EmergencyRequestQuantityPacks AS INTEGER)         AS EmergencyRequestQuantityPacks,
  GREATEST(COALESCE(TRY_CAST(RequestedQuantityPacks AS INTEGER), 0) - COALESCE(TRY_CAST(ReceivedQuantityPacks AS INTEGER), 0), 0) AS UnfulfilledDemandPacks,
  TRY_CAST(OpeningStockPacks             AS INTEGER)         AS OpeningStockPacks,
  TRY_CAST(DispensedQuantityPacks        AS INTEGER)         AS DispensedQuantityPacks,
  TRY_CAST(ConsumedQuantityPacks         AS INTEGER)         AS ConsumedQuantityPacks,
  TRY_CAST(WastageQuantityPacks          AS INTEGER)         AS WastageQuantityPacks,
  TRY_CAST(ClosingStockPacks             AS INTEGER)         AS ClosingStockPacks,
  TRY_CAST(DemandTrendIndex              AS DECIMAL(8,3))    AS DemandTrendIndex,
  TRY_CAST(LicensedBeds                  AS INTEGER)         AS LicensedBeds,
  TRY_CAST(ICUBeds                       AS INTEGER)         AS ICUBeds,
  CASE WHEN max(TRY_CAST(AverageOccupancyRatePct AS DOUBLE)) OVER () <= 1
       THEN TRY_CAST(AverageOccupancyRatePct AS DOUBLE) * 100
       ELSE TRY_CAST(AverageOccupancyRatePct AS DOUBLE) END  AS AverageOccupancyRatePct
FROM raw_demand;

CREATE OR REPLACE VIEW stg_pharmacy AS
SELECT PharmacyID,
       arg_max(PharmacyGLN,  SaleDate) AS PharmacyGLN,
       arg_max(PharmacyName, SaleDate) AS PharmacyName,
       arg_max(PharmacyType, SaleDate) AS PharmacyType
FROM stg_sales
WHERE PharmacyID IS NOT NULL
GROUP BY PharmacyID;

CREATE OR REPLACE VIEW stg_hospital AS
SELECT HospitalID,
       arg_max(HospitalGLN,  DemandMonth) AS HospitalGLN,
       arg_max(HospitalName, DemandMonth) AS HospitalName,
       arg_max(HospitalType, DemandMonth) AS HospitalType
FROM stg_demand
WHERE HospitalID IS NOT NULL
GROUP BY HospitalID;

-- =====================================================================
-- SECTION 3: Dimension Loads and Slowly Changing Dimensions (SCD)
-- =====================================================================

-- DimDate (2023-01-01 to 2029-12-31 to cover medicine batch expiry dates)
INSERT INTO DimDate
SELECT CAST(strftime(d, '%Y%m%d') AS INTEGER),
       d, day(d), dayname(d), isodow(d) >= 6, weekofyear(d), month(d), monthname(d),
       strftime(d, '%Y-%m'), 'Q' || quarter(d), year(d),
       CASE WHEN month(d) IN (12, 1, 2) THEN 'Winter'
            WHEN month(d) IN (3, 4, 5)  THEN 'Spring'
            WHEN month(d) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Autumn' END
FROM (SELECT CAST(ts AS DATE) AS d
      FROM generate_series(DATE '2023-01-01', DATE '2029-12-31', INTERVAL 1 DAY) AS t(ts))
WHERE NOT EXISTS (SELECT 1 FROM DimDate);

-- DimLocation (Hospital + Pharmacy geographies)
INSERT INTO DimLocation (City, State, Country)
SELECT u.City, u.State, u.Country
FROM (SELECT City, State, Country FROM stg_sales
      UNION
      SELECT City, State, Country FROM stg_demand) u
WHERE u.City IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DimLocation l
                  WHERE l.City = u.City AND l.State = u.State AND l.Country = u.Country);

-- DimMedicine: Type 1 overwrite & Type 2 tracking on ProductStatus
UPDATE DimMedicine SET
  MedName = s.MedName, ICD10Category = s.ICD10Category, DiseaseCategory = s.DiseaseCategory,
  TherapeuticClass = s.TherapeuticClass, DosageStrength = s.DosageStrength, Route = s.Route,
  PackSizeBand = s.PackSizeBand, BaseUOM = s.BaseUOM, PrescriptionClass = s.PrescriptionClass,
  ColdChainFlag = s.ColdChainFlag, ShelfLifeBand = s.ShelfLifeBand
FROM stg_medicine s
WHERE DimMedicine.MedicineID = s.MedicineID AND DimMedicine.IsCurrent
  AND (DimMedicine.MedName          IS DISTINCT FROM s.MedName
    OR DimMedicine.ICD10Category    IS DISTINCT FROM s.ICD10Category
    OR DimMedicine.DiseaseCategory  IS DISTINCT FROM s.DiseaseCategory
    OR DimMedicine.TherapeuticClass IS DISTINCT FROM s.TherapeuticClass
    OR DimMedicine.DosageStrength   IS DISTINCT FROM s.DosageStrength
    OR DimMedicine.Route            IS DISTINCT FROM s.Route
    OR DimMedicine.PackSizeBand     IS DISTINCT FROM s.PackSizeBand
    OR DimMedicine.BaseUOM          IS DISTINCT FROM s.BaseUOM
    OR DimMedicine.PrescriptionClass IS DISTINCT FROM s.PrescriptionClass
    OR DimMedicine.ColdChainFlag    IS DISTINCT FROM s.ColdChainFlag
    OR DimMedicine.ShelfLifeBand    IS DISTINCT FROM s.ShelfLifeBand);

UPDATE DimMedicine SET
  EffectiveTo = CAST((SELECT load_date FROM etl_params) - INTERVAL 1 DAY AS DATE), IsCurrent = FALSE
FROM stg_medicine s
WHERE DimMedicine.MedicineID = s.MedicineID AND DimMedicine.IsCurrent
  AND DimMedicine.ProductStatus IS DISTINCT FROM s.ProductStatus;

INSERT INTO DimMedicine (MedicineID, InternalSKU, GTIN14, MedName, ICD10Category, DiseaseCategory,
  TherapeuticClass, DosageStrength, Route, PackSizeBand, BaseUOM, PrescriptionClass, ColdChainFlag,
  ShelfLifeBand, ProductStatus, EffectiveFrom, EffectiveTo, IsCurrent)
SELECT s.MedicineID, s.InternalSKU, s.GTIN14, s.MedName, s.ICD10Category, s.DiseaseCategory,
  s.TherapeuticClass, s.DosageStrength, s.Route, s.PackSizeBand, s.BaseUOM, s.PrescriptionClass,
  s.ColdChainFlag, s.ShelfLifeBand, s.ProductStatus,
  CASE WHEN (SELECT count(*) FROM DimMedicine) = 0 THEN COALESCE(s.EffectiveFromDate, DATE '2023-01-01')
       ELSE (SELECT load_date FROM etl_params) END,
  DATE '9999-12-31', TRUE
FROM stg_medicine s
WHERE s.MedicineID IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DimMedicine d WHERE d.MedicineID = s.MedicineID AND d.IsCurrent);

-- DimHospital: Type 1 overwrite & Type 2 tracking on HospitalType
UPDATE DimHospital SET HospitalName = s.HospitalName, HospitalGLN = s.HospitalGLN
FROM stg_hospital s
WHERE DimHospital.HospitalID = s.HospitalID AND DimHospital.IsCurrent
  AND (DimHospital.HospitalName IS DISTINCT FROM s.HospitalName
    OR DimHospital.HospitalGLN  IS DISTINCT FROM s.HospitalGLN);

UPDATE DimHospital SET
  EffectiveTo = CAST((SELECT load_date FROM etl_params) - INTERVAL 1 DAY AS DATE), IsCurrent = FALSE
FROM stg_hospital s
WHERE DimHospital.HospitalID = s.HospitalID AND DimHospital.IsCurrent
  AND DimHospital.HospitalType IS DISTINCT FROM s.HospitalType;

INSERT INTO DimHospital (HospitalID, HospitalGLN, HospitalName, HospitalType, EffectiveFrom, EffectiveTo, IsCurrent)
SELECT s.HospitalID, s.HospitalGLN, s.HospitalName, s.HospitalType,
  CASE WHEN (SELECT count(*) FROM DimHospital) = 0 THEN DATE '2023-01-01'
       ELSE (SELECT load_date FROM etl_params) END,
  DATE '9999-12-31', TRUE
FROM stg_hospital s
WHERE NOT EXISTS (SELECT 1 FROM DimHospital d WHERE d.HospitalID = s.HospitalID AND d.IsCurrent);

-- DimPharmacy: Type 1 overwrite & Type 2 tracking on PharmacyType
UPDATE DimPharmacy SET PharmacyName = s.PharmacyName, PharmacyGLN = s.PharmacyGLN
FROM stg_pharmacy s
WHERE DimPharmacy.PharmacyID = s.PharmacyID AND DimPharmacy.IsCurrent
  AND (DimPharmacy.PharmacyName IS DISTINCT FROM s.PharmacyName
    OR DimPharmacy.PharmacyGLN  IS DISTINCT FROM s.PharmacyGLN);

UPDATE DimPharmacy SET
  EffectiveTo = CAST((SELECT load_date FROM etl_params) - INTERVAL 1 DAY AS DATE), IsCurrent = FALSE
FROM stg_pharmacy s
WHERE DimPharmacy.PharmacyID = s.PharmacyID AND DimPharmacy.IsCurrent
  AND DimPharmacy.PharmacyType IS DISTINCT FROM s.PharmacyType;

INSERT INTO DimPharmacy (PharmacyID, PharmacyGLN, PharmacyName, PharmacyType, EffectiveFrom, EffectiveTo, IsCurrent)
SELECT s.PharmacyID, s.PharmacyGLN, s.PharmacyName, s.PharmacyType,
  CASE WHEN (SELECT count(*) FROM DimPharmacy) = 0 THEN DATE '2023-01-01'
       ELSE (SELECT load_date FROM etl_params) END,
  DATE '9999-12-31', TRUE
FROM stg_pharmacy s
WHERE NOT EXISTS (SELECT 1 FROM DimPharmacy d WHERE d.PharmacyID = s.PharmacyID AND d.IsCurrent);

-- =====================================================================
-- SECTION 4: Data Quality Validation & Error Logging
-- =====================================================================
DELETE FROM etl_rejects;

CREATE OR REPLACE VIEW stg_sales_checked AS
SELECT *,
  COALESCE(SalesTransactionID IS NOT NULL AND SaleDate IS NOT NULL AND MedicineID IS NOT NULL
           AND PharmacyID IS NOT NULL
           AND QuantitySoldPacks >= 0
           AND GrossSalesAmountUSD > 0
           AND COALESCE(DiscountAmountUSD, 0) <= GrossSalesAmountUSD
           AND CostOfGoodsSoldUSD >= 0, FALSE) AS is_valid
FROM stg_sales;

CREATE OR REPLACE VIEW stg_demand_checked AS
SELECT *,
  COALESCE(HospitalDemandRecordID IS NOT NULL AND DemandMonth IS NOT NULL AND GTIN14 IS NOT NULL
           AND HospitalID IS NOT NULL
           AND COALESCE(RequestedQuantityPacks >= 0, TRUE) AND COALESCE(ConsumedQuantityPacks >= 0, TRUE)
           AND COALESCE(ICUBeds <= LicensedBeds, TRUE), FALSE) AS is_valid
FROM stg_demand;

INSERT INTO etl_rejects
SELECT 'Fact_Sales', SalesTransactionID,
       'failed validation rule (date, key, quantity >= 0, price > 0, discount <= gross, cost >= 0)', now()
FROM stg_sales_checked WHERE NOT is_valid;

INSERT INTO etl_rejects
SELECT 'Fact_Hospital_Demand', HospitalDemandRecordID,
       'failed validation rule (month, key, quantities >= 0, ICU beds <= licensed beds)', now()
FROM stg_demand_checked WHERE NOT is_valid;

-- =====================================================================
-- SECTION 5: Incremental Fact Loading
-- =====================================================================
INSERT INTO Fact_Sales (SaleDateKey, MedicineKey, PharmacyKey, PharmacyLocationKey, SalesTransactionID,
  CustomerSegment, SalesChannel, ReportingChannel, DeliveryOTIFFlag, QuantitySoldPacks,
  GrossSalesAmountUSD, DiscountAmountUSD, NetSalesAmountUSD, CostOfGoodsSoldUSD,
  GrossMarginUSD, DaysToExpiryAtSale, StandardCost, ListTradePrice, MRP)
SELECT d.DateKey, m.MedicineKey, p.PharmacyKey, l.LocationKey, s.SalesTransactionID,
  s.CustomerSegment, s.SalesChannel, s.ReportingChannel, s.DeliveryOTIFFlag, s.QuantitySoldPacks,
  s.GrossSalesAmountUSD, COALESCE(s.DiscountAmountUSD, 0),
  s.GrossSalesAmountUSD - COALESCE(s.DiscountAmountUSD, 0),
  s.CostOfGoodsSoldUSD, s.GrossMarginUSD, s.DaysToExpiryAtSale,
  pr.StandardCost, pr.ListTradePrice, pr.MRP
FROM stg_sales_checked s
JOIN DimDate d      ON d.FullDate = s.SaleDate
JOIN DimMedicine m  ON m.MedicineID = s.MedicineID AND s.SaleDate BETWEEN m.EffectiveFrom AND m.EffectiveTo
JOIN DimPharmacy p  ON p.PharmacyID = s.PharmacyID AND s.SaleDate BETWEEN p.EffectiveFrom AND p.EffectiveTo
JOIN DimLocation l  ON l.City = s.City AND l.State = s.State AND l.Country = s.Country
LEFT JOIN stg_medicine pr ON pr.MedicineID = s.MedicineID
WHERE s.is_valid
  AND NOT EXISTS (SELECT 1 FROM Fact_Sales f WHERE f.SalesTransactionID = s.SalesTransactionID);

INSERT INTO Fact_Hospital_Demand (DemandMonthKey, MedicineKey, HospitalKey, HospitalLocationKey,
  HospitalDemandRecordID, EstimatedDiseaseCases, DiseaseRelatedAdmissions, OutpatientEncounters,
  ForecastDemandPacks, RequestedQuantityPacks, ApprovedQuantityPacks, ReceivedQuantityPacks,
  EmergencyRequestQuantityPacks, UnfulfilledDemandPacks, OpeningStockPacks, DispensedQuantityPacks,
  ConsumedQuantityPacks, WastageQuantityPacks, ClosingStockPacks, DemandTrendIndex,
  LicensedBeds, ICUBeds, AverageOccupancyRatePct)
SELECT d.DateKey, m.MedicineKey, h.HospitalKey, l.LocationKey,
  s.HospitalDemandRecordID, COALESCE(s.EstimatedDiseaseCases, 0), COALESCE(s.DiseaseRelatedAdmissions, 0),
  COALESCE(s.OutpatientEncounters, 0), COALESCE(s.ForecastDemandPacks, 0), COALESCE(s.RequestedQuantityPacks, 0),
  COALESCE(s.ApprovedQuantityPacks, 0), COALESCE(s.ReceivedQuantityPacks, 0),
  COALESCE(s.EmergencyRequestQuantityPacks, 0), s.UnfulfilledDemandPacks,
  COALESCE(s.OpeningStockPacks, 0), COALESCE(s.DispensedQuantityPacks, 0),
  COALESCE(s.ConsumedQuantityPacks, 0), COALESCE(s.WastageQuantityPacks, 0),
  COALESCE(s.ClosingStockPacks, 0), s.DemandTrendIndex,
  s.LicensedBeds, s.ICUBeds, CAST(s.AverageOccupancyRatePct AS DECIMAL(5,2))
FROM stg_demand_checked s
JOIN DimDate d      ON d.FullDate = s.DemandMonth
JOIN DimMedicine m  ON m.GTIN14 = s.GTIN14 AND s.DemandMonth BETWEEN m.EffectiveFrom AND m.EffectiveTo
JOIN DimHospital h  ON h.HospitalID = s.HospitalID AND s.DemandMonth BETWEEN h.EffectiveFrom AND h.EffectiveTo
JOIN DimLocation l  ON l.City = s.City AND l.State = s.State AND l.Country = s.Country
WHERE s.is_valid
  AND NOT EXISTS (SELECT 1 FROM Fact_Hospital_Demand f WHERE f.HospitalDemandRecordID = s.HospitalDemandRecordID);

-- Log orphan rejects
INSERT INTO etl_rejects
SELECT 'Fact_Sales', s.SalesTransactionID, 'no matching dimension row (medicine, pharmacy, location or date)', now()
FROM stg_sales_checked s
WHERE s.is_valid AND NOT EXISTS (SELECT 1 FROM Fact_Sales f WHERE f.SalesTransactionID = s.SalesTransactionID);

INSERT INTO etl_rejects
SELECT 'Fact_Hospital_Demand', s.HospitalDemandRecordID, 'no matching dimension row (medicine by GTIN14, hospital, location or month)', now()
FROM stg_demand_checked s
WHERE s.is_valid AND NOT EXISTS (SELECT 1 FROM Fact_Hospital_Demand f WHERE f.HospitalDemandRecordID = s.HospitalDemandRecordID);

-- =====================================================================
-- SECTION 6: Analytical Query Layer (Pre-Optimized BI Views)
-- =====================================================================

-- BI View 1: Channel Revenue Split & Gross Margin Comparison + MoM Growth
CREATE OR REPLACE VIEW vw_bi_channel_performance AS
WITH monthly_sales AS (
    SELECT 
        dd.YearMonth,
        dd.Year,
        dd.Quarter,
        f.ReportingChannel,
        m.TherapeuticClass,
        sum(f.QuantitySoldPacks) AS total_packs_sold,
        sum(f.GrossSalesAmountUSD) AS gross_sales_usd,
        sum(f.DiscountAmountUSD) AS discount_usd,
        sum(f.NetSalesAmountUSD) AS net_sales_usd,
        sum(f.CostOfGoodsSoldUSD) AS cogs_usd,
        sum(f.GrossMarginUSD) AS gross_margin_usd,
        round(100.0 * sum(f.GrossMarginUSD) / nullif(sum(f.NetSalesAmountUSD), 0), 2) AS gross_margin_pct,
        round(100.0 * sum(f.DiscountAmountUSD) / nullif(sum(f.GrossSalesAmountUSD), 0), 2) AS discount_rate_pct
    FROM Fact_Sales f
    JOIN DimDate dd ON dd.DateKey = f.SaleDateKey
    JOIN DimMedicine m ON m.MedicineKey = f.MedicineKey
    GROUP BY dd.YearMonth, dd.Year, dd.Quarter, f.ReportingChannel, m.TherapeuticClass
)
SELECT 
    *,
    round(100.0 * (net_sales_usd - lag(net_sales_usd) OVER (PARTITION BY ReportingChannel, TherapeuticClass ORDER BY YearMonth)) 
          / nullif(lag(net_sales_usd) OVER (PARTITION BY ReportingChannel, TherapeuticClass ORDER BY YearMonth), 0), 2) AS mom_growth_pct
FROM monthly_sales;

-- BI View 2: Hospital Forecast vs Actual Consumption & Unfulfilled Demand Analysis
CREATE OR REPLACE VIEW vw_bi_hospital_forecast_accuracy AS
SELECT 
    dd.YearMonth,
    dd.Quarter,
    dd.Year,
    h.HospitalID,
    h.HospitalName,
    h.HospitalType,
    loc.City AS HospitalCity,
    loc.State AS HospitalState,
    m.MedicineID,
    m.MedName,
    m.TherapeuticClass,
    m.DiseaseCategory,
    sum(f.EstimatedDiseaseCases) AS estimated_disease_cases,
    sum(f.ForecastDemandPacks) AS forecast_packs,
    sum(f.RequestedQuantityPacks) AS requested_packs,
    sum(f.ApprovedQuantityPacks) AS approved_packs,
    sum(f.ReceivedQuantityPacks) AS received_packs,
    sum(f.ConsumedQuantityPacks) AS consumed_packs,
    sum(f.WastageQuantityPacks) AS wastage_packs,
    sum(f.UnfulfilledDemandPacks) AS unfulfilled_packs,
    round(sum(f.ConsumedQuantityPacks) * 100.0 / nullif(sum(f.ForecastDemandPacks), 0), 2) AS consumption_to_forecast_pct,
    round(avg(abs(f.ForecastDemandPacks - f.ConsumedQuantityPacks) * 100.0 / nullif(f.ConsumedQuantityPacks, 0)), 2) AS mape_pct,
    round(avg(f.ForecastDemandPacks - f.ConsumedQuantityPacks), 2) AS forecast_bias_packs
FROM Fact_Hospital_Demand f
JOIN DimDate dd ON dd.DateKey = f.DemandMonthKey
JOIN DimHospital h ON h.HospitalKey = f.HospitalKey
JOIN DimLocation loc ON loc.LocationKey = f.HospitalLocationKey
JOIN DimMedicine m ON m.MedicineKey = f.MedicineKey
GROUP BY dd.YearMonth, dd.Quarter, dd.Year, h.HospitalID, h.HospitalName, h.HospitalType,
         loc.City, loc.State, m.MedicineID, m.MedName, m.TherapeuticClass, m.DiseaseCategory;

-- BI View 3: Multi-Fact Drill-Across Fast vs Slow Moving Cold Chain Medicines
CREATE OR REPLACE VIEW vw_bi_fast_slow_moving_cold_chain AS
WITH sales_packs AS (
    SELECT 
        m.MedicineKey,
        m.MedicineID,
        m.MedName,
        m.TherapeuticClass,
        m.ColdChainFlag,
        sum(f.QuantitySoldPacks) AS pharmacy_sold_packs,
        sum(f.NetSalesAmountUSD) AS pharmacy_net_sales_usd
    FROM Fact_Sales f
    JOIN DimMedicine m ON f.MedicineKey = m.MedicineKey
    WHERE m.ColdChainFlag = TRUE
    GROUP BY m.MedicineKey, m.MedicineID, m.MedName, m.TherapeuticClass, m.ColdChainFlag
),
hospital_packs AS (
    SELECT 
        m.MedicineKey,
        sum(f.ConsumedQuantityPacks) AS hospital_consumed_packs,
        sum(f.UnfulfilledDemandPacks) AS hospital_unfulfilled_packs
    FROM Fact_Hospital_Demand f
    JOIN DimMedicine m ON f.MedicineKey = m.MedicineKey
    WHERE m.ColdChainFlag = TRUE
    GROUP BY m.MedicineKey
)
SELECT 
    s.MedicineID,
    s.MedName,
    s.TherapeuticClass,
    s.ColdChainFlag,
    s.pharmacy_sold_packs,
    coalesce(h.hospital_consumed_packs, 0) AS hospital_consumed_packs,
    (s.pharmacy_sold_packs + coalesce(h.hospital_consumed_packs, 0)) AS total_cold_chain_demand_packs,
    s.pharmacy_net_sales_usd,
    coalesce(h.hospital_unfulfilled_packs, 0) AS hospital_unfulfilled_packs,
    rank() OVER (PARTITION BY s.TherapeuticClass ORDER BY (s.pharmacy_sold_packs + coalesce(h.hospital_consumed_packs, 0)) DESC) AS rank_fast_mover,
    rank() OVER (PARTITION BY s.TherapeuticClass ORDER BY (s.pharmacy_sold_packs + coalesce(h.hospital_consumed_packs, 0)) ASC) AS rank_slow_mover
FROM sales_packs s
LEFT JOIN hospital_packs h ON s.MedicineKey = h.MedicineKey;
