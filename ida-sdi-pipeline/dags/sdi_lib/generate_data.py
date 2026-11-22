"""
Data Oversampling Layer - Phase 1 (Sales & Demand Intelligence)

Makes NEW rows for the 3 Phase-1 source files, so the warehouse can be
refreshed with data from a new time period. New data is ADDED to the old
data, never replaces it.

How it works (simple version):
  * Each refresh covers one new 3-month period after the original data
    (original data ends Dec 2025):
        refresh 1 -> Jan-Mar 2026
        refresh 2 -> Apr-Jun 2026
  * Sales: take the real sales from the SAME months one year earlier
    (keeps seasonality), shift them forward by one year, change quantities
    by a small random amount (+/-15%) and recalculate the money columns.
  * Hospital demand: same idea, one row per hospital x medicine x month,
    numbers changed by +/-10%.
  * Master data: no new medicines, but a few medicines get a price change
    (a new row with a new EffectiveFromDate). This lets the team show a
    Slowly Changing Dimension (Type 2) in Dim_Medicine.
  * A few bad rows are added on purpose (about 0.2%) so the validation step
    and the "rejected rows" metric have something to catch.

Usage:
    python generate_data.py --refresh 1 --source-dir data/source --out-dir data/incoming
"""
import argparse
import os
from datetime import datetime

import numpy as np
import pandas as pd

MASTER_FILE = "01_master_data.csv"
SALES_FILE = "05_pharmacy_sales_data.csv"
HOSP_FILE = "06_hospital_demand_data.csv"

# Refresh n covers the n-th quarter after the original data:
#   1 = Jan-Mar 2026, 2 = Apr-Jun 2026, 3 = Jul-Sep 2026, 4 = Oct-Dec 2026
MAX_REFRESH = 4                # one full year of new data
BAD_ROW_SHARE = 0.002          # 0.2% deliberately broken rows
PRICE_CHANGE_MEDICINES = 5     # medicines that get a new price per refresh


def _period(refresh_no):
    if not 1 <= refresh_no <= MAX_REFRESH:
        raise ValueError(f"refresh must be between 1 and {MAX_REFRESH}")
    start = pd.Timestamp("2026-01-01") + pd.DateOffset(months=3 * (refresh_no - 1))
    end = start + pd.DateOffset(months=3) - pd.Timedelta(days=1)
    return start, end


def _years_back(start):
    """How many years to go back so the base months exist in the 2023-2025 data."""
    return max(1, start.year - 2025)


def _money(x):
    return np.round(x.astype(float), 2)


# ---------------------------------------------------------------- sales
def generate_sales(sales, start, end, refresh_no, rng):
    years = _years_back(start)
    base_start = start - pd.DateOffset(years=years)
    base_end = end - pd.DateOffset(years=years)
    dates = pd.to_datetime(sales["SalesDate"])
    base = sales[(dates >= base_start) & (dates <= base_end)].copy()

    # +/-5% on the number of transactions, so each period is a bit different
    n = int(len(base) * rng.uniform(0.95, 1.05))
    new = base.sample(n=n, replace=n > len(base), random_state=rng.integers(1e9)).copy()
    new = new.reset_index(drop=True)

    shift = pd.DateOffset(years=years)
    for col in ["SalesDate", "PharmacyDeliveryDate", "BatchExpiryDate"]:
        new[col] = (pd.to_datetime(new[col]) + shift).dt.strftime("%Y-%m-%d")
    new["SalesTimestampUTC"] = (
        pd.to_datetime(new["SalesTimestampUTC"]) + shift
    ).dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    # quantity +/-15%, never below 1
    qty = new["QuantitySoldPacks"].astype(int)
    qty = np.maximum(1, np.round(qty * rng.uniform(0.85, 1.15, len(new)))).astype(int)
    old_qty = new["QuantitySoldPacks"].astype(int)
    new["QuantitySoldPacks"] = qty

    # recalculate money columns from the unit price, keeping the same rates
    price = new["UnitRetailPriceUSD"].astype(float)
    gross_old = new["GrossSalesAmountUSD"].astype(float).replace(0, np.nan)
    disc_rate = (new["DiscountAmountUSD"].astype(float) / gross_old).fillna(0)
    net_old = new["NetSalesAmountUSD"].astype(float).replace(0, np.nan)
    tax_rate = (new["SalesTaxUSD"].astype(float) / net_old).fillna(0)
    unit_cogs = new["CostOfGoodsSoldUSD"].astype(float) / old_qty

    gross = _money(price * qty)
    disc = _money(gross * disc_rate)
    net = _money(gross - disc)
    new["GrossSalesAmountUSD"] = gross
    new["DiscountAmountUSD"] = disc
    new["NetSalesAmountUSD"] = net
    new["SalesTaxUSD"] = _money(net * tax_rate)
    new["CostOfGoodsSoldUSD"] = _money(unit_cogs * qty)
    new["GrossMarginUSD"] = _money(net - new["CostOfGoodsSoldUSD"])
    new["ReturnedQuantityPacks"] = np.minimum(
        new["ReturnedQuantityPacks"].astype(int), qty
    )

    # new unique IDs: SALE-R1-00000001 ...
    new["SalesTransactionID"] = [f"SALE-R{refresh_no}-{i:08d}" for i in range(1, n + 1)]
    has_rx = new["PrescriptionID"].notna()
    new.loc[has_rx, "PrescriptionID"] = [
        f"RX-R{refresh_no}-{i:08d}" for i in range(1, has_rx.sum() + 1)
    ]
    new["SourceSystem"] = "PHARMACY_POS_SIMULATED"
    return _add_bad_rows(new, rng, kind="sales")


# ------------------------------------------------------- hospital demand
def generate_hospital(hosp, start, end, refresh_no, rng):
    years = _years_back(start)
    months = pd.to_datetime(hosp["DemandMonth"])
    base = hosp[
        (months >= start - pd.DateOffset(years=years))
        & (months <= end - pd.DateOffset(years=years))
    ].copy().reset_index(drop=True)

    base["DemandMonth"] = (
        pd.to_datetime(base["DemandMonth"]) + pd.DateOffset(years=years)
    ).dt.strftime("%Y-%m-%d")

    qty_cols = [
        "EstimatedDiseaseCases", "DiseaseRelatedAdmissions", "OutpatientEncounters",
        "ForecastDemandPacks", "RequestedQuantityPacks", "ApprovedQuantityPacks",
        "ReceivedQuantityPacks", "EmergencyRequestQuantityPacks", "OpeningStockPacks",
        "DispensedQuantityPacks", "ConsumedQuantityPacks", "WastageQuantityPacks",
        "ClosingStockPacks", "UnfulfilledDemandPacks",
    ]
    factor = rng.uniform(0.9, 1.1, len(base))
    for c in qty_cols:
        base[c] = np.round(base[c].astype(float) * factor).astype(int)
    # keep the basic rules true: approved <= requested, received <= approved
    base["ApprovedQuantityPacks"] = np.minimum(base["ApprovedQuantityPacks"], base["RequestedQuantityPacks"])
    base["ReceivedQuantityPacks"] = np.minimum(base["ReceivedQuantityPacks"], base["ApprovedQuantityPacks"])
    base["DemandTrendIndex"] = np.round(base["DemandTrendIndex"].astype(float) * factor, 3)

    base["HospitalDemandRecordID"] = [
        f"HDEM-R{refresh_no}-{i:06d}" for i in range(1, len(base) + 1)
    ]
    base["SourceSystem"] = "HOSPITAL_ERP_SIMULATED"
    return _add_bad_rows(base, rng, kind="hospital")


# ---------------------------------------------------------------- master
def generate_master(master, start, refresh_no, rng):
    """A few medicines get a new price from the start of the period (SCD Type 2)."""
    current = master.sort_values("EffectiveFromDate").groupby("MedicineID").tail(1)
    picked = current.sample(n=PRICE_CHANGE_MEDICINES, random_state=rng.integers(1e9)).copy()
    pct = rng.uniform(1.03, 1.10, len(picked))  # 3-10% price increase
    for c in ["UnitManufacturingCostUSD", "WholesalePriceUSD", "RecommendedRetailPriceUSD"]:
        picked[c] = np.round(picked[c].astype(float) * pct, 2)
    picked["EffectiveFromDate"] = start.strftime("%Y-%m-%d")
    picked["SourceSystem"] = "ERP_PRODUCT_MASTER_SIMULATED"
    return picked


# -------------------------------------------------------------- bad rows
def _add_bad_rows(df, rng, kind):
    """Break ~0.2% of rows on purpose so validation has something to reject."""
    df = df.astype(object)  # lets us put any value in any column
    n_bad = max(1, int(len(df) * BAD_ROW_SHARE))
    idx = rng.choice(df.index, size=n_bad, replace=False)
    for k, i in enumerate(idx):
        problem = k % 3
        if problem == 0:
            df.at[i, "MedicineID"] = None                       # missing SKU
        elif problem == 1:
            date_col = "SalesDate" if kind == "sales" else "DemandMonth"
            df.at[i, date_col] = "2026-13-45"                   # invalid date
        else:
            if kind == "sales":
                df.at[i, "UnitRetailPriceUSD"] = "-1"            # price <= 0
            else:
                df.at[i, "RequestedQuantityPacks"] = "-5"        # negative quantity
    return df


# ------------------------------------------------------------------ main
def run(refresh_no, source_dir, out_dir, seed=None):
    rng = np.random.default_rng(seed if seed is not None else 1000 + refresh_no)
    start, end = _period(refresh_no)
    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d%H%M%S")

    master = pd.read_csv(os.path.join(source_dir, MASTER_FILE), dtype=str)
    sales = pd.read_csv(os.path.join(source_dir, SALES_FILE), dtype=str)
    hosp = pd.read_csv(os.path.join(source_dir, HOSP_FILE), dtype=str)

    outputs = {
        "master": (generate_master(master, start, refresh_no, rng), "01_master_data"),
        "sales": (generate_sales(sales, start, end, refresh_no, rng), "05_pharmacy_sales_data"),
        "hospital_demand": (generate_hospital(hosp, start, end, refresh_no, rng), "06_hospital_demand_data"),
    }
    stats = []
    for source, (df, prefix) in outputs.items():
        name = f"{prefix}_R{refresh_no}_{stamp}.csv"
        # write to a temp name first, then rename, so the file watcher never
        # picks up a half-written file
        tmp = os.path.join(out_dir, name + ".tmp")
        df.to_csv(tmp, index=False)
        os.replace(tmp, os.path.join(out_dir, name))
        stats.append({
            "refresh_no": refresh_no, "source_name": source,
            "period_start": start.date(), "period_end": end.date(),
            "rows_generated": len(df), "file_name": name,
        })
        print(f"[generator] {source:16s} {len(df):>7,} rows -> {name}")
    return stats


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--refresh", type=int, required=True)
    p.add_argument("--source-dir", default="data/source")
    p.add_argument("--out-dir", default="data/incoming")
    p.add_argument("--seed", type=int, default=None)
    a = p.parse_args()
    run(a.refresh, a.source_dir, a.out_dir, a.seed)
