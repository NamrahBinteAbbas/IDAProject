# Oversampled Dataset Data Dictionary — Phase 1 (SDI Mart)

## Files Included in `oversampled_data/`
* **Refresh 1 (`_R1_`):** `01_master_data_R1_20261122233614.csv`, `05_pharmacy_sales_data_R1_20261122233614.csv`, `06_hospital_demand_data_R1_20261122233614.csv`
* **Refresh 2 (`_R2_`):** `01_master_data_R2_20261122233623.csv`, `05_pharmacy_sales_data_R2_20261122233623.csv`, `06_hospital_demand_data_R2_20261122233623.csv`

---

## 1. Medicine Master (`01_master_data_R1_*.csv` / `01_master_data_R2_*.csv`)
* **Grain:** 1 row = 1 SKU (`MedicineID`)
* **Primary Key:** `MedicineID`
* **Columns:**
  * `MedicineID` (VARCHAR): Unique medicine identifier (e.g., `MED001`)
  * `InternalSKU` (VARCHAR): Internal warehouse SKU code
  * `GTIN14` (VARCHAR): 14-digit Global Trade Item Number
  * `GenericName` (VARCHAR): Active pharmaceutical ingredient / medicine name
  * `ICD10Category` (VARCHAR): ICD-10 clinical diagnosis category
  * `DiseaseCategory` (VARCHAR): Target disease group
  * `TherapeuticClass` (VARCHAR): Clinical therapeutic classification
  * `DosageForm` (VARCHAR): Formulation (Tablet, Capsule, Solution for injection, etc.)
  * `Strength` (VARCHAR): Dosage strength (e.g., `500mg`)
  * `RouteOfAdministration` (VARCHAR): Oral, Intravenous, Subcutaneous, Inhalation, etc.
  * `PackSize` (INTEGER): Number of units per pack
  * `BaseUnitOfMeasure` (VARCHAR): Standard unit of measure (`Pack`)
  * `PrescriptionClass` (VARCHAR): Prescription requirement class (Rx / OTC)
  * `ColdChainFlag` (VARCHAR/BOOLEAN): Indicates cold-chain temperature control requirement (`Y`/`N`)
  * `ShelfLifeMonths` (INTEGER): Product shelf life in months
  * `ProductStatus` (VARCHAR): Lifecycle status (`Active`, `Discontinued`, etc.)
  * `EffectiveFromDate` (DATE): Effective start date of SKU record
  * `UnitManufacturingCostUSD` (DECIMAL): Standard manufacturing cost per pack in USD
  * `WholesalePriceUSD` (DECIMAL): Trade list price per pack in USD
  * `RecommendedRetailPriceUSD` (DECIMAL): Maximum retail price (MRP) in USD

---

## 2. Pharmacy & E-Commerce Sales (`05_pharmacy_sales_data_R1_*.csv` / `05_pharmacy_sales_data_R2_*.csv`)
* **Grain:** 1 row = 1 Sales Transaction (`SalesTransactionID`)
* **Primary Key:** `SalesTransactionID`
* **Foreign Keys:** `MedicineID`, `PharmacyID`
* **Columns:**
  * `SalesTransactionID` (VARCHAR): Unique transaction identifier
  * `SalesDate` (DATE): Date of sale
  * `SalesChannel` (VARCHAR): Source channel (`Physical Pharmacy` or `Ecommerce`)
  * `PharmacyID` (VARCHAR): Unique pharmacy identifier (e.g., `PHR039`)
  * `PharmacyGLN` (VARCHAR): Global Location Number of the pharmacy
  * `PharmacyName` (VARCHAR): Name of the pharmacy
  * `PharmacyType` (VARCHAR): `Community Pharmacy`, `Hospital Pharmacy`, or `Independent Pharmacy`
  * `DeliveryOTIFFlag` (VARCHAR): On-Time In-Full delivery indicator
  * `MedicineID` (VARCHAR): Foreign key linking to Medicine Master
  * `PharmacyCity` (VARCHAR): City of pharmacy
  * `PharmacyState` (VARCHAR): State/province of pharmacy
  * `CountryCode` (VARCHAR): Country code
  * `CustomerSegment` (VARCHAR): Buyer segment
  * `QuantitySoldPacks` (INTEGER): Number of packs sold
  * `DaysToExpiryAtSale` (INTEGER): Remaining shelf life in days at point of sale
  * `GrossSalesAmountUSD` (DECIMAL): Gross sales value before discounts (USD)
  * `DiscountAmountUSD` (DECIMAL): Discount granted (USD)
  * `CostOfGoodsSoldUSD` (DECIMAL): Total cost of goods sold (USD)
  * `GrossMarginUSD` (DECIMAL): Net revenue minus COGS (USD)

---

## 3. Hospital Monthly Demand (`06_hospital_demand_data_R1_*.csv` / `06_hospital_demand_data_R2_*.csv`)
* **Grain:** 1 row = 1 Hospital–Medicine–Month (`HospitalDemandRecordID`)
* **Primary Key:** `HospitalDemandRecordID`
* **Foreign Keys:** `HospitalID`, `GTIN14`
* **Columns:**
  * `HospitalDemandRecordID` (VARCHAR): Unique monthly hospital demand log ID
  * `DemandMonth` (DATE): Reporting month
  * `HospitalID` (VARCHAR): Unique hospital identifier
  * `HospitalGLN` (VARCHAR): Global Location Number of the hospital
  * `HospitalName` (VARCHAR): Name of the hospital
  * `HospitalType` (VARCHAR): Facility classification (Teaching, General, Specialty, etc.)
  * `GTIN14` (VARCHAR): Foreign key linking to Medicine Master
  * `City` (VARCHAR): City of hospital
  * `State` (VARCHAR): State/province of hospital
  * `CountryCode` (VARCHAR): Country code
  * `EstimatedDiseaseCases` (INTEGER): Estimated regional disease cases
  * `DiseaseRelatedAdmissions` (INTEGER): Inpatient admissions linked to target condition
  * `OutpatientEncounters` (INTEGER): Outpatient visits
  * `ForecastDemandPacks` (INTEGER): Forecasted monthly demand in packs
  * `RequestedQuantityPacks` (INTEGER): Packs ordered by the hospital
  * `ApprovedQuantityPacks` (INTEGER): Packs approved for fulfillment
  * `ReceivedQuantityPacks` (INTEGER): Packs delivered to the hospital
  * `EmergencyRequestQuantityPacks` (INTEGER): Urgent replenishment packs requested
  * `OpeningStockPacks` (INTEGER): Beginning monthly inventory in packs
  * `DispensedQuantityPacks` (INTEGER): Packs dispensed internally
  * `ConsumedQuantityPacks` (INTEGER): Actual packs consumed
  * `WastageQuantityPacks` (INTEGER): Expired or spoiled packs
  * `ClosingStockPacks` (INTEGER): Ending monthly inventory in packs
  * `DemandTrendIndex` (DECIMAL): Seasonal/trend demand multiplier
  * `LicensedBeds` (INTEGER): Total licensed hospital beds
  * `ICUBeds` (INTEGER): Intensive care unit beds
  * `AverageOccupancyRatePct` (DECIMAL): Monthly bed occupancy percentage