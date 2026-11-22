import pathlib
import duckdb

db_file = "dwh.duckdb" if pathlib.Path("dwh.duckdb").exists() else "../dwh.duckdb"
con = duckdb.connect(db_file, read_only=True)

sql = """
WITH monthly_channel_sales AS (
    SELECT 
        dd.YearMonth,
        f.ReportingChannel,
        round(sum(f.NetSalesAmountUSD), 2) AS net_sales_usd,
        round(100.0 * sum(f.GrossMarginUSD) / nullif(sum(f.NetSalesAmountUSD), 0), 2) AS gross_margin_pct,
        round(100.0 * sum(f.DiscountAmountUSD) / nullif(sum(f.GrossSalesAmountUSD), 0), 2) AS discount_rate_pct
    FROM Fact_Sales f
    JOIN DimDate dd ON dd.DateKey = f.SaleDateKey
    GROUP BY dd.YearMonth, f.ReportingChannel
)
SELECT 
    YearMonth,
    ReportingChannel,
    net_sales_usd,
    gross_margin_pct,
    discount_rate_pct,
    round(100.0 * (net_sales_usd - lag(net_sales_usd) OVER (PARTITION BY ReportingChannel ORDER BY YearMonth)) 
          / nullif(lag(net_sales_usd) OVER (PARTITION BY ReportingChannel ORDER BY YearMonth), 0), 2) AS mom_growth_pct
FROM monthly_channel_sales
ORDER BY YearMonth DESC, ReportingChannel
LIMIT 12;
"""

con.sql(sql).show()
con.close()
