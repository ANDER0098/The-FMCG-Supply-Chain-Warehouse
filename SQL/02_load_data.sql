-- ============================================================
-- FILE 02: BULK LOAD (COPY)
-- ============================================================
-- WHAT THIS DOES:
--   Loads the CSV files produced by generate_data.py into the
--   tables created by 01_schema.sql.
--
-- WHY COPY AND NOT INSERT?
--   COPY streams the file directly into Postgres in one command -
--   typically 10-100x faster than row-by-row INSERTs. It is THE
--   standard way to bulk-load CSV/Parquet into Postgres.
--
--   The column list after each table name maps the CSV's column
--   ORDER onto our (sometimes renamed) table columns - e.g. the
--   CSV's first column is called "date", our column is full_date.
--
--   WITH (FORMAT csv, HEADER true) = skip the header row, treat
--   commas as separators, handle quoted strings.
--
-- LOAD ORDER MATTERS: dimensions first, then facts - otherwise the
-- foreign keys reject fact rows that reference missing dimensions.
--
-- NOTE: Postgres only reads server-side files, so paths below point
-- at the CSVs using the full absolute path with forward slashes.
-- ============================================================

COPY dim_date (full_date, date_id, year, month, day, is_month_end)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/dim_date.csv'
WITH (FORMAT csv, HEADER true);

COPY dim_product (sku_id, brand, category, mrp, units_per_case)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/dim_product.csv'
WITH (FORMAT csv, HEADER true);

-- Seed the promotion calendar AFTER dim_product exists - its foreign
-- key on sku_id would reject the row otherwise (referential integrity
-- enforcing load order). This mirrors the promo the generator
-- simulated: 20% off CleanMax soap, 10-25 April 2023.
INSERT INTO dim_promotion VALUES
    ('PROMO001', 'CleanMax Spring Clean Sale', 'SKU001',
     DATE '2023-04-10', DATE '2023-04-25', 20);

COPY dim_sales_rep (rep_id, rep_name, region)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/dim_sales_rep.csv'
WITH (FORMAT csv, HEADER true);

COPY dim_distributor (distributor_id, distributor_name, rep_id, region)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/dim_distributor.csv'
WITH (FORMAT csv, HEADER true);

COPY dim_kirana (kirana_id, kirana_name, distributor_id, pin_code)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/dim_kirana.csv'
WITH (FORMAT csv, HEADER true);

COPY fact_primary_sales (primary_order_id, date_id, distributor_id, sku_id, rep_id, qty_cases)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/fact_primary_sales.csv'
WITH (FORMAT csv, HEADER true);

COPY fact_secondary_sales (secondary_order_id, date_id, kirana_id, distributor_id, sku_id, qty_units)
FROM 'C:/Users/SHASHANK/OneDrive/Documents/The FMCG Supply Chain Warehouse/data/fact_secondary_sales.csv'
WITH (FORMAT csv, HEADER true);

-- ANALYZE updates the query planner's statistics (row counts, value
-- distributions). Without it, Postgres plans queries blind and may
-- pick slow join strategies. Always ANALYZE after a bulk load.
ANALYZE;
