-- ============================================================
-- FILE 08: DASHBOARD DATASET EXPORTS
-- ============================================================
-- Feeds build_dashboard.py. Each \copy runs a query and writes the
-- result straight to a CSV on the CLIENT side (psql's \copy, as
-- opposed to the server-side COPY we used for loading in file 02).
--
-- Notice the pattern: the DASHBOARD does not re-derive anything.
-- All business logic already lives in the warehouse / the fraud
-- view; this layer only shapes data for presentation. In BI terms
-- these are "extracts" - the same idea as a Power BI dataset.
--
-- Drop-size buckets are pre-aggregated IN SQL: shipping 179k rows
-- to Python to count them there would be wasteful; shipping 16
-- summary rows is free. Aggregate where the data lives.
-- ============================================================

-- 1) The ranked risk list (from the Phase 3 view)
\copy (SELECT * FROM vw_fraud_risk_score ORDER BY risk_score DESC, distributor_id) TO 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/reports/csv/risk_list.csv' WITH (FORMAT csv, HEADER true)

-- 2) Channel stuffing evidence: DIST005's full purchase history
\copy (SELECT dd.full_date, SUM(r.primary_units) AS primary_units FROM fact_stock_reconciliation r JOIN dim_date dd ON dd.date_id = r.date_id WHERE r.distributor_id = 'DIST005' GROUP BY dd.full_date ORDER BY dd.full_date) TO 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/reports/csv/dist005_daily.csv' WITH (FORMAT csv, HEADER true)

-- 3) Promo leakage evidence: DIST018's SKU001 sales around the promo
\copy (SELECT dd.full_date, r.secondary_units FROM fact_stock_reconciliation r JOIN dim_date dd ON dd.date_id = r.date_id WHERE r.distributor_id = 'DIST018' AND r.sku_id = 'SKU001' AND dd.full_date BETWEEN DATE '2023-03-20' AND DATE '2023-05-31' ORDER BY dd.full_date) TO 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/reports/csv/dist018_sku001_daily.csv' WITH (FORMAT csv, HEADER true)

-- 4) Route falsification evidence: drop-size distribution, bucketed in SQL
\copy (SELECT CASE WHEN qty_units <= 20 THEN '1-20' WHEN qty_units <= 60 THEN '21-60' WHEN qty_units <= 100 THEN '61-100' WHEN qty_units <= 150 THEN '101-150' WHEN qty_units <= 200 THEN '151-200' WHEN qty_units <= 250 THEN '201-250' WHEN qty_units <= 300 THEN '251-300' ELSE '300+' END AS bucket, CASE WHEN distributor_id = 'DIST012' THEN 'DIST012 (falsifier)' ELSE 'All other distributors' END AS cohort, COUNT(*) AS drop_count FROM fact_secondary_sales GROUP BY 1, 2) TO 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/reports/csv/drop_size_buckets.csv' WITH (FORMAT csv, HEADER true)
