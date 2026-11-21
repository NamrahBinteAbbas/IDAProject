# Plan Your Data Warehouse (Corrected & Synchronized DWH Template)
*Aligned with DuckDB Implementation, Kimball Dimensional Modeling Standards, and Fall 2026 Project Specification.*

---

## Step 1: X-Ray of Business Requirements to Build the DWH

- **Business Domain:** Pharmaceutical Supply Chain
- **Business Process:** Sales and Demand Intelligence Process
- **How Does This Process Run:**
  1. Hospitals forecast monthly demand for medicines and submit purchase requests.
  2. Warehouses fulfill and deliver inventory to pharmacies (chain, independent, hospital).
  3. Patients purchase medicines in-store or online (e-commerce). POS records pricing, discounts, prescriptions, payer, and payment methods.
  4. Returns, wastage, and unfulfilled demands occur across channels.
  5. *Core Problem:* Sales POS, e-commerce, and hospital ERP data reside in siloed systems at different grains (transaction-level vs. monthly snapshot), preventing a unified 360-degree view of demand.
  6. *Scope:* 63 medicines, 7 therapeutic classes, 60 pharmacies, 12 hospitals, 500,000 sales transactions, 27,216 monthly hospital demand logs (2023–2025).

- **Stakeholders:**
  - *Top Management:* CEO (growth, market share), CFO (revenue, margins, gross-to-net discount leakages), Chief Commercial Officer (channel & regional performance), COO/Supply Chain Head (demand vs. supply, stockout elimination).
  - *Operational / Tactical Planners:* Demand Planners (hospital forecast vs. actual consumption, MAPE), Production Planners (batch scheduling, fast vs. slow movers), Product Managers (disease category performance), Regional Pharmacy Network Managers, Hospital Procurement Managers (unfulfilled demand, emergency orders).

- **Competitor Benchmarking & Case Studies:**
  - *Walgreens (USA):* Unified store, pharmacy, and supply data onto Databricks; cut store data readiness lag from 48 hours to near real-time, reducing supply-chain costs and improving planning productivity by 20%.
  - *Pfizer:* Migrated legacy 20-year DWH to Snowflake, dropping processing times from hours to minutes.
  - *Adamed Pharma:* Implemented Azure DWH + Power BI, maintaining forecast error below 5%.
  - *Martin Dow (Pakistan):* Centralized over 80% of enterprise operations on SAP BW/4HANA ("Genesis") powering executive dashboards.

- **Analytical Requirements (OLAP):**
  1. *Channel Revenue & Margin Split:* Net sales, COGS, gross margin %, and discount rate % across Retail, Hospital, and E-commerce channels with MoM growth.
  2. *Hospital Forecast vs. Consumption & Loss Tracking:* Forecast vs. actual consumption ratio, forecast error (MAPE %, bias), and unfulfilled demand packs (Requested $-$ Received).
  3. *Cross-Fact Demand Intelligence:* Drill-across total demand (pharmacy sales + hospital consumption) to identify top 10 fast-moving and slow-moving cold chain medicines by therapeutic class.

- **KPI Framework:**
  - *Base Measures:* Gross Sales USD, Discount USD, Net Sales USD, COGS USD, Gross Margin USD, Quantity Sold Packs, Forecast Demand Packs, Requested Quantity Packs, Received Quantity Packs, Consumed Quantity Packs, Wastage Quantity Packs, Unfulfilled Demand Packs, Closing Stock Packs, Licensed Beds, ICU Beds.
  - *Derived KPIs:* Gross Margin %, Discount Rate %, MoM Net Sales Growth %, Consumption-to-Forecast Ratio %, MAPE %, Forecast Bias, Wastage Rate %, Unfulfilled Demand Rate %.

---

## Step 2: X-Ray of OLTP Tables to Identify Data for DWH

| OLTP Source Table | Destination Dimension / Fact | Attributes / Fields Exported | Facts / Measures Exported | Transformation Notes |
| :--- | :--- | :--- | :--- | :--- |
| `01_master_data` | `DimMedicine` | `MedicineID` (NK), `InternalSKU`, `GTIN14`, `GenericName`, `ICD10Category`, `DiseaseCategory`, `TherapeuticClass`, `DosageForm`, `Strength`, `RouteOfAdministration`, `PackSize`, `BaseUnitOfMeasure`, `PrescriptionClass`, `ColdChainFlag`, `ShelfLifeMonths`, `ProductStatus` | `UnitManufacturingCostUSD` (StandardCost), `WholesalePriceUSD` (ListTradePrice), `RecommendedRetailPriceUSD` (MRP) | Clean whitespace; pad GTIN14 to 14 digits; abbreviate dosage form via lookup table; classify PackSizeBand (>15 = Large); track SCD Type 2 on `ProductStatus`. Export price baselines to `Fact_Sales`. |
| `06_hospital_demand_data` | `DimHospital`, `DimLocation`, `Fact_Hospital_Demand` | `HospitalID` (NK), `HospitalGLN`, `HospitalName`, `HospitalType`, `City`, `State`, `CountryCode`, `DemandMonth`, `GTIN14` | `EstimatedDiseaseCases`, `DiseaseRelatedAdmissions`, `OutpatientEncounters`, `ForecastDemandPacks`, `RequestedQuantityPacks`, `ApprovedQuantityPacks`, `ReceivedQuantityPacks`, `EmergencyRequestQuantityPacks`, `OpeningStockPacks`, `DispensedQuantityPacks`, `ConsumedQuantityPacks`, `WastageQuantityPacks`, `ClosingStockPacks`, `DemandTrendIndex`, `LicensedBeds`, `ICUBeds`, `AverageOccupancyRatePct` | Extract distinct hospitals for `DimHospital` (SCD Type 2 on HospitalType). Geographies flow to conformed `DimLocation`. Fact captures monthly periodic snapshots; derive `UnfulfilledDemandPacks = GREATEST(Requested - Received, 0)`. |
| `05_pharmacy_sales_data` | `DimPharmacy`, `DimLocation`, `Fact_Sales` | `PharmacyID` (NK), `PharmacyGLN`, `PharmacyName`, `PharmacyType`, `SalesTransactionID` (Degenerate), `SalesDate`, `MedicineID`, `CustomerSegment`, `SalesChannel`, `DeliveryOTIFFlag`, `PharmacyCity`, `PharmacyState`, `CountryCode` | `QuantitySoldPacks`, `DaysToExpiryAtSale`, `GrossSalesAmountUSD`, `DiscountAmountUSD`, `CostOfGoodsSoldUSD`, `GrossMarginUSD` | Extract distinct pharmacies for `DimPharmacy` (SCD Type 2 on PharmacyType). Geographies flow to conformed `DimLocation`. `SalesChannel` and `DeliveryOTIFFlag` vary per sale, so they export to `Fact_Sales`. Derive `ReportingChannel` (Retail / Hospital / E-commerce). |
| `02_manufacturing_data` | `DimBatch`, `DimPlant`, `DimMfgProfile`, `Fact_Manufacturing` | `ProductionBatchID`, `PlantID`, 7 workflow dates, 8 status/delay reason columns | Planned, Actual, Rejected, Released Quantities; Yield %; Lead Time; Setup/Run/Downtime Hours; Costs | Planned for Phase 2/3 constellation. |
| `03_manufacturer_delivery_data` | `DimShipment`, `DimCarrier`, `DimShipmentFlags`, `Fact_Shipment` | `ShipmentID`, `SSCC18`, `CarrierID`, origin/destination keys | Shipped, Received, Damaged, Short Quantities; Mileage; Transit Hours; Freight Costs; Delay Days | Planned for Phase 2/3 constellation. |
| `04_warehouse_data` | `DimWarehouse`, `DimStorageZone`, `DimInventoryStatus`, `Fact_Inventory_Snapshot` | `WarehouseID`, `StorageZoneID`, `SnapshotDate`, status flags | Opening, Received, Available, Reserved, Closing Quantities; Dock-to-Stock Hours; Accuracy % | Planned for Phase 2 constellation. |
| `07_iot_streaming_data` | `DimDevice`, `DimTimeOfDay`, `Fact_Sensor_Reading` | `DeviceID`, `EventTimestampUTC`, sensor metadata | Temperature (°C), Humidity %, Shock G, Battery %, Latency, Lat/Long | Planned for Phase 3 constellation. |

---

## Step 3: Transformation Actions

### Dimension Attribute Transformations
1. `MedicineID`: Trim, uppercase, primary natural key.
2. `GTIN14`: Read as text, left-pad with zero to 14 digits (`09506000000015`).
3. `GenericName` $\rightarrow$ `MedName`: Trim, standardize multiple spaces, Title Case.
4. `DosageForm` + `Strength` $\rightarrow$ `DosageStrength`: Exact lookup mapping for all 13 source forms (`Modified-release tablet` $\rightarrow$ `MR Tab`, `Gastro-resistant capsule` $\rightarrow$ `GR Cap`, `Pre-filled pen` $\rightarrow$ `Pen`, `Metered-dose inhaler` $\rightarrow$ `MDI`, `Dry-powder inhaler` $\rightarrow$ `DPI`, etc.) concatenated with space-trimmed strength (e.g., `MR Tab 60mg`, `Pen 1mg/dose`).
5. `PackSize` $\rightarrow$ `PackSizeBand`: `CASE WHEN PackSize > 15 THEN 'Large' ELSE 'Small' END`.
6. `BaseUnitOfMeasure` $\rightarrow$ `BaseUOM`: Capitalize first letter (`Pack` / `Device`).
7. `ColdChainFlag`: Standardize `'Y'`, `'YES'`, `'TRUE'`, `'1'` to Boolean `TRUE`, else `FALSE`.
8. `ShelfLifeMonths` $\rightarrow$ `ShelfLifeBand`: $\le 24 \rightarrow$ `'Short'`, $\ge 36 \rightarrow$ `'Long'`, else `'Medium'`.
9. `ProductStatus`, `EffectiveFrom`, `EffectiveTo`, `IsCurrent`: SCD Type 2 tracking; initial load sets `EffectiveFrom = 2023-01-01`, `EffectiveTo = 9999-12-31`, `IsCurrent = TRUE`.
10. `HospitalID`, `HospitalGLN`, `HospitalName`, `HospitalType`: Trim; GLN 13-digit text; SCD Type 2 on `HospitalType`.
11. `PharmacyID`, `PharmacyGLN`, `PharmacyName`, `PharmacyType`: Trim; GLN 13-digit text; standardize name spacing; abbreviate type with dots (e.g., `C.P.`, `I.P.`, `H.P.`); SCD Type 2 on `PharmacyType`.
12. `City`, `State`, `Country` $\rightarrow$ `DimLocation`: Distinct combination across sales, hospital demand, and delivery destinations; surrogate key `LocationKey`.
13. `DimDate`: Role-playing dimension pre-populated from `2023-01-01` to `2029-12-31` (surrogate key format `YYYYMMDD`).

### Fact Attribute & Measure Transformations
1. `SalesTransactionID`: Degenerate dimension in `Fact_Sales`.
2. `SalesChannel`: Kept in `Fact_Sales` representing transaction origin (`Physical Pharmacy`, `Ecommerce`).
3. `ReportingChannel`: Derived in `Fact_Sales`:
   - `Ecommerce` $\rightarrow$ `'E-commerce'`
   - `Physical Pharmacy` AND `Hospital Pharmacy` $\rightarrow$ `'Hospital'`
   - `Physical Pharmacy` AND `Chain/Independent Pharmacy` $\rightarrow$ `'Retail'`
4. `DeliveryOTIFFlag`: Kept in `Fact_Sales` representing whether the transaction delivery met OTIF criteria.
5. `NetSalesAmountUSD`: Calculated as `GrossSalesAmountUSD - COALESCE(DiscountAmountUSD, 0)`.
6. `GrossMarginUSD`: Validated against `NetSalesAmountUSD - CostOfGoodsSoldUSD`.
7. `HospitalDemandRecordID`: Degenerate dimension in `Fact_Hospital_Demand`.
8. `DemandMonth` $\rightarrow$ `DemandMonthKey`: Truncated to first day of month, mapped to `YYYYMMDD` in `DimDate`.
9. `UnfulfilledDemandPacks`: Calculated as `GREATEST(RequestedQuantityPacks - ReceivedQuantityPacks, 0)`.
10. `AverageOccupancyRatePct`: Verified and scaled to 0–100 range.
11. Incremental Load Rule: Insert only records where `SalesTransactionID` or `HospitalDemandRecordID` does not exist in target fact table (`WHERE NOT EXISTS`); never truncate historical facts.

---

## Step 4: Fully Specified Dimension Tables

### DimMedicine
- **Primary / Surrogate Key:** `MedicineKey` (INTEGER, sequence generated)
- **Natural Key:** `MedicineID` (Secondary: `GTIN14`, `InternalSKU`)
- **Attributes:**
  - `MedicineKey` (PK)
  - `MedicineID` (VARCHAR, Type 0)
  - `InternalSKU` (VARCHAR, Type 0)
  - `GTIN14` (VARCHAR(14), Type 0)
  - `MedName` (VARCHAR, Type 1)
  - `ICD10Category` (VARCHAR, Type 1)
  - `DiseaseCategory` (VARCHAR, Type 1, Hierarchy Level 1)
  - `TherapeuticClass` (VARCHAR, Type 1, Hierarchy Level 2)
  - `DosageStrength` (VARCHAR, Type 1)
  - `Route` (VARCHAR, Type 1)
  - `PackSizeBand` (VARCHAR, Type 1)
  - `BaseUOM` (VARCHAR, Type 1)
  - `PrescriptionClass` (VARCHAR, Type 1)
  - `ColdChainFlag` (BOOLEAN, Type 1)
  - `ShelfLifeBand` (VARCHAR, Type 1)
  - `ProductStatus` (VARCHAR, Type 2)
  - `EffectiveFrom` (DATE, SCD housekeeping)
  - `EffectiveTo` (DATE, SCD housekeeping)
  - `IsCurrent` (BOOLEAN, SCD housekeeping)

### DimHospital
- **Primary / Surrogate Key:** `HospitalKey` (INTEGER, sequence generated)
- **Natural Key:** `HospitalID` (Secondary: `HospitalGLN`)
- **Attributes:**
  - `HospitalKey` (PK)
  - `HospitalID` (VARCHAR, Type 0)
  - `HospitalGLN` (VARCHAR(13), Type 0)
  - `HospitalName` (VARCHAR, Type 1)
  - `HospitalType` (VARCHAR, Type 2)
  - `EffectiveFrom` (DATE, SCD housekeeping)
  - `EffectiveTo` (DATE, SCD housekeeping)
  - `IsCurrent` (BOOLEAN, SCD housekeeping)

### DimPharmacy
- **Primary / Surrogate Key:** `PharmacyKey` (INTEGER, sequence generated)
- **Natural Key:** `PharmacyID` (Secondary: `PharmacyGLN`)
- **Attributes:**
  - `PharmacyKey` (PK)
  - `PharmacyID` (VARCHAR, Type 0)
  - `PharmacyGLN` (VARCHAR(13), Type 0)
  - `PharmacyName` (VARCHAR, Type 1)
  - `PharmacyType` (VARCHAR, Type 2)
  - `EffectiveFrom` (DATE, SCD housekeeping)
  - `EffectiveTo` (DATE, SCD housekeeping)
  - `IsCurrent` (BOOLEAN, SCD housekeeping)
  *(Note: SalesChannel and DeliveryOTIFFlag are transaction-level and modeled in Fact_Sales).*

### DimLocation (Conformed / Role-Playing)
- **Primary / Surrogate Key:** `LocationKey` (INTEGER, sequence generated)
- **Natural Key:** `City` + `State` + `Country`
- **Attributes:**
  - `LocationKey` (PK)
  - `Country` (VARCHAR, Type 1, Level 1)
  - `State` (VARCHAR, Type 1, Level 2)
  - `City` (VARCHAR, Type 1, Level 3)

### DimDate (Role-Playing Calendar)
- **Primary / Smart Key:** `DateKey` (INTEGER, `YYYYMMDD`)
- **Natural Key:** `FullDate` (DATE, 2023-01-01 to 2029-12-31)
- **Attributes:**
  - `DateKey` (PK)
  - `FullDate` (DATE)
  - `DayOfMonth` (SMALLINT)
  - `DayName` (VARCHAR)
  - `IsWeekend` (BOOLEAN)
  - `WeekOfYear` (SMALLINT)
  - `MonthNum` (SMALLINT)
  - `MonthName` (VARCHAR)
  - `YearMonth` (VARCHAR(7), e.g., '2024-03')
  - `Quarter` (VARCHAR(2), e.g., 'Q1')
  - `Year` (SMALLINT)
  - `Season` (VARCHAR: Winter, Spring, Summer, Autumn)

---

## Step 5: Fully Specified Fact Tables

### Fact_Sales
- **Grain:** One row per individual sales transaction (`SalesTransactionID`).
- **Fact Table Type:** Transactional.
- **Surrogate Key:** `SalesKey` (BIGINT).
- **Columns & Measures:**
  1. `SalesKey` (BIGINT, PK)
  2. `SaleDateKey` (INTEGER, FK $\rightarrow$ `DimDate`)
  3. `MedicineKey` (INTEGER, FK $\rightarrow$ `DimMedicine`)
  4. `PharmacyKey` (INTEGER, FK $\rightarrow$ `DimPharmacy`)
  5. `PharmacyLocationKey` (INTEGER, FK $\rightarrow$ `DimLocation`)
  6. `SalesTransactionID` (VARCHAR, Degenerate Dimension)
  7. `CustomerSegment` (VARCHAR, Degenerate Attribute)
  8. `SalesChannel` (VARCHAR, Transaction Channel: Physical Pharmacy / Ecommerce)
  9. `ReportingChannel` (VARCHAR, Derived: Retail / Hospital / E-commerce)
  10. `DeliveryOTIFFlag` (VARCHAR, Transaction Flag: Y / N)
  11. `QuantitySoldPacks` (INTEGER, Fully Additive)
  12. `GrossSalesAmountUSD` (DECIMAL(12,2), Fully Additive)
  13. `DiscountAmountUSD` (DECIMAL(12,2), Fully Additive)
  14. `NetSalesAmountUSD` (DECIMAL(12,2), Fully Additive)
  15. `CostOfGoodsSoldUSD` (DECIMAL(12,2), Fully Additive)
  16. `GrossMarginUSD` (DECIMAL(12,2), Fully Additive)
  17. `DaysToExpiryAtSale` (INTEGER, Non-Additive)
  18. `StandardCost` (DECIMAL(10,2), Non-Additive baseline)
  19. `ListTradePrice` (DECIMAL(10,2), Non-Additive baseline)
  20. `MRP` (DECIMAL(10,2), Non-Additive baseline)

### Fact_Hospital_Demand
- **Grain:** One row per hospital, medicine, and demand month.
- **Fact Table Type:** Periodic Snapshot.
- **Surrogate Key:** `DemandKey` (BIGINT).
- **Columns & Measures:**
  1. `DemandKey` (BIGINT, PK)
  2. `DemandMonthKey` (INTEGER, FK $\rightarrow$ `DimDate`, 1st of month)
  3. `MedicineKey` (INTEGER, FK $\rightarrow$ `DimMedicine`)
  4. `HospitalKey` (INTEGER, FK $\rightarrow$ `DimHospital`)
  5. `HospitalLocationKey` (INTEGER, FK $\rightarrow$ `DimLocation`)
  6. `HospitalDemandRecordID` (VARCHAR, Degenerate Dimension)
  7. `EstimatedDiseaseCases` (INTEGER, Semi-Additive across time/location, non-additive across medicines of same disease)
  8. `DiseaseRelatedAdmissions` (INTEGER, Semi-Additive)
  9. `OutpatientEncounters` (INTEGER, Semi-Additive)
  10. `ForecastDemandPacks` (INTEGER, Fully Additive)
  11. `RequestedQuantityPacks` (INTEGER, Fully Additive)
  12. `ApprovedQuantityPacks` (INTEGER, Fully Additive)
  13. `ReceivedQuantityPacks` (INTEGER, Fully Additive)
  14. `EmergencyRequestQuantityPacks` (INTEGER, Fully Additive)
  15. `UnfulfilledDemandPacks` (INTEGER, Fully Additive, Derived: Requested $-$ Received)
  16. `OpeningStockPacks` (INTEGER, Semi-Additive stock snapshot)
  17. `DispensedQuantityPacks` (INTEGER, Fully Additive)
  18. `ConsumedQuantityPacks` (INTEGER, Fully Additive)
  19. `WastageQuantityPacks` (INTEGER, Fully Additive)
  20. `ClosingStockPacks` (INTEGER, Semi-Additive stock snapshot)
  21. `DemandTrendIndex` (DECIMAL(8,3), Non-Additive index)
  22. `LicensedBeds` (INTEGER, Secondary Fact / Hospital level)
  23. `ICUBeds` (INTEGER, Secondary Fact / Hospital level)
  24. `AverageOccupancyRatePct` (DECIMAL(5,2), Non-Additive percentage)

---

## Step 6: Star Schema & Solvable Dimensional Queries

### Enterprise Bus Matrix (Phase 1 Focused)

| Conformed Dimension | `Fact_Sales` | `Fact_Hospital_Demand` |
| :--- | :---: | :---: |
| `DimDate` | Role: Sale Date | Role: Demand Month |
| `DimMedicine` | $\checkmark$ | $\checkmark$ |
| `DimLocation` | Role: Pharmacy Location | Role: Hospital Location |
| `DimPharmacy` | $\checkmark$ | |
| `DimHospital` | | $\checkmark$ |

### 3 Solvable Dimensional Queries (Directly Mapping to Required BI Dashboards)

1. **Query 1: Channel Revenue Split & Gross Margin Comparison (Dashboard 2)**
   - *Business Question:* Show net sales, gross margin %, discount rate %, and MoM net sales growth across the three channels (Retail, Hospital, E-commerce) by month and therapeutic class.
   - *Business Value:* Allows CFO and Commercial Head to evaluate channel profitability and identify discount leakage.

2. **Query 2: Hospital Forecast vs. Actual Consumption Ratio & Unfulfilled Demand (Dashboard 1)**
   - *Business Question:* For each hospital and medicine, calculate forecast vs. consumed ratio, forecast error (MAPE %, bias), and rank top hospital-medicine pairs by unfulfilled demand packs.
   - *Business Value:* Solves the hospital stockout problem by uncovering systemic under-supply and inaccurate hospital forecasts.

3. **Query 3: Cross-Fact Total Cold Chain Demand & Fast/Slow Movers (Dashboard 3)**
   - *Business Question:* Drill across `Fact_Sales` and `Fact_Hospital_Demand` to compute total cold chain medicine demand (Pharmacy Sold Packs + Hospital Consumed Packs) and rank top 10 fast-moving and slow-moving medicines partitioned by therapeutic class.
   - *Business Value:* Provides the single 360-degree view of market demand, allowing production and warehouse planners to balance inventory.
