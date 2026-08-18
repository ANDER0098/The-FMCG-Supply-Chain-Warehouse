-- ============================================================
-- FILE 01: SCHEMA (DDL = Data Definition Language)
-- ============================================================
-- WHAT THIS DOES:
--   Creates the empty tables (the "star schema") that model the
--   FMCG supply chain. Small DIMENSION tables describe who/what/when.
--   Large FACT tables record business events (transactions).
--
-- WHY DROP FIRST?
--   So the script is "idempotent" - you can re-run it any number
--   of times and always end up with a clean warehouse. Tables are
--   dropped in REVERSE dependency order (facts first) so we never
--   violate a foreign key while dropping.
-- ============================================================

DROP VIEW IF EXISTS vw_fraud_risk_score;
DROP TABLE IF EXISTS fact_stock_reconciliation;
DROP TABLE IF EXISTS fact_secondary_sales;
DROP TABLE IF EXISTS fact_primary_sales;
DROP TABLE IF EXISTS dim_promotion;
DROP TABLE IF EXISTS dim_kirana;
DROP TABLE IF EXISTS dim_distributor;
DROP TABLE IF EXISTS dim_sales_rep;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_date;

-- ------------------------------------------------------------
-- DIMENSION: dim_date
-- The "date spine". One row per calendar day. date_id is an
-- INTEGER in YYYYMMDD form (20230415) - human-readable AND sorts
-- chronologically as a number.
-- ------------------------------------------------------------
CREATE TABLE dim_date (
    date_id       INTEGER PRIMARY KEY,
    full_date     DATE    NOT NULL UNIQUE,
    year          SMALLINT NOT NULL,
    month         SMALLINT NOT NULL,
    day           SMALLINT NOT NULL,
    is_month_end  BOOLEAN NOT NULL
);

-- ------------------------------------------------------------
-- DIMENSION: dim_product
-- MRP (price) uses NUMERIC, never FLOAT - floating point maths
-- loses cents/rupees (0.1 + 0.2 != 0.3). NUMERIC is exact.
-- units_per_case is the key to converting Primary (cases) into
-- Secondary (units) - the unit mismatch is a classic real-world trap.
-- ------------------------------------------------------------
CREATE TABLE dim_product (
    sku_id          TEXT PRIMARY KEY,
    brand           TEXT NOT NULL,
    category        TEXT NOT NULL,
    mrp             NUMERIC(8,2) NOT NULL,
    units_per_case  INTEGER NOT NULL CHECK (units_per_case > 0)
);

-- ------------------------------------------------------------
-- DIMENSION: dim_sales_rep
-- Company employees who pressure/serve distributors.
-- ------------------------------------------------------------
CREATE TABLE dim_sales_rep (
    rep_id    TEXT PRIMARY KEY,
    rep_name  TEXT NOT NULL,
    region    TEXT NOT NULL
);

-- ------------------------------------------------------------
-- DIMENSION: dim_distributor
-- rep_id is a FOREIGN KEY: Postgres REFUSES any distributor whose
-- rep does not exist in dim_sales_rep. That is referential integrity
-- - garbage dimensions can never leak into the warehouse.
-- ------------------------------------------------------------
CREATE TABLE dim_distributor (
    distributor_id    TEXT PRIMARY KEY,
    distributor_name  TEXT NOT NULL,
    rep_id            TEXT NOT NULL REFERENCES dim_sales_rep(rep_id),
    region            TEXT NOT NULL
);

-- ------------------------------------------------------------
-- DIMENSION: dim_kirana
-- The tiny neighbourhood retail stores that buy from distributors.
-- ------------------------------------------------------------
CREATE TABLE dim_kirana (
    kirana_id       TEXT PRIMARY KEY,
    kirana_name     TEXT NOT NULL,
    distributor_id  TEXT NOT NULL REFERENCES dim_distributor(distributor_id),
    pin_code        INTEGER NOT NULL
);

-- ------------------------------------------------------------
-- DIMENSION: dim_promotion  (NEW - not in the Python generator)
-- The company's trade-promotion calendar: WHICH sku had a promo and
-- WHEN. This comes from the company side (truth), and Phase 3 joins
-- it against distributor behaviour to catch hoarding.
-- ------------------------------------------------------------
CREATE TABLE dim_promotion (
    promotion_id  TEXT PRIMARY KEY,
    promo_name    TEXT NOT NULL,
    sku_id        TEXT NOT NULL REFERENCES dim_product(sku_id),
    promo_start   DATE NOT NULL,
    promo_end     DATE NOT NULL,
    discount_pct  INTEGER NOT NULL CHECK (discount_pct BETWEEN 0 AND 100),
    CHECK (promo_end >= promo_start)
);

-- (The seed row for this table lives in 02_load_data.sql: it
-- references SKU001, so dim_product must be loaded first - the
-- foreign key enforces that ordering, as we learned the hard way.)

-- ------------------------------------------------------------
-- FACT: fact_primary_sales  (Company ERP -> Distributor)
-- GRAIN: one row = one shipment line of one SKU to one distributor.
-- BIGINT for the id: fact tables grow into billions of rows in real
-- companies; INTEGER caps at ~2.1 billion, BIGINT is future-proof.
-- CHECK (qty_cases >= 0): the database itself rejects nonsense data.
-- ------------------------------------------------------------
CREATE TABLE fact_primary_sales (
    primary_order_id  BIGINT PRIMARY KEY,
    date_id           INTEGER NOT NULL REFERENCES dim_date(date_id),
    distributor_id    TEXT    NOT NULL REFERENCES dim_distributor(distributor_id),
    sku_id            TEXT    NOT NULL REFERENCES dim_product(sku_id),
    rep_id            TEXT    NOT NULL REFERENCES dim_sales_rep(rep_id),
    qty_cases         INTEGER NOT NULL CHECK (qty_cases >= 0)
);

-- ------------------------------------------------------------
-- FACT: fact_secondary_sales  (Distributor -> Kirana store)
-- GRAIN: one row = one delivery of one SKU to one kirana on one day.
-- Note the UNIT difference vs primary: qty_units here, qty_cases there.
-- ------------------------------------------------------------
CREATE TABLE fact_secondary_sales (
    secondary_order_id  BIGINT PRIMARY KEY,
    date_id             INTEGER NOT NULL REFERENCES dim_date(date_id),
    kirana_id           TEXT    NOT NULL REFERENCES dim_kirana(kirana_id),
    distributor_id      TEXT    NOT NULL REFERENCES dim_distributor(distributor_id),
    sku_id              TEXT    NOT NULL REFERENCES dim_product(sku_id),
    qty_units           INTEGER NOT NULL CHECK (qty_units >= 0)
);

-- ------------------------------------------------------------
-- FACT: fact_stock_reconciliation  (THE TRUTH TABLE)
-- GRAIN: one row per (distributor, sku, DAY) - declared as a
-- composite PRIMARY KEY so a duplicate day is physically impossible.
-- Built by 03_stock_reconciliation.sql, not loaded from CSV.
-- The CHECK enforces the ledger identity at the database level:
--   opening + inflow - outflow = closing ... or the row is rejected.
-- ------------------------------------------------------------
CREATE TABLE fact_stock_reconciliation (
    date_id         INTEGER NOT NULL REFERENCES dim_date(date_id),
    distributor_id  TEXT    NOT NULL REFERENCES dim_distributor(distributor_id),
    sku_id          TEXT    NOT NULL REFERENCES dim_product(sku_id),
    opening_units   BIGINT  NOT NULL,
    primary_units   BIGINT  NOT NULL,
    secondary_units BIGINT  NOT NULL,
    closing_units   BIGINT  NOT NULL,
    PRIMARY KEY (distributor_id, sku_id, date_id),
    CHECK (closing_units = opening_units + primary_units - secondary_units)
);

-- ------------------------------------------------------------
-- INDEXES
-- A PRIMARY KEY is automatically indexed, but FOREIGN KEY columns
-- are NOT (a common surprise - MySQL does it, Postgres does not).
-- Every column we will JOIN or FILTER facts on gets an index, or
-- queries over millions of rows degrade from milliseconds to minutes.
-- ------------------------------------------------------------
CREATE INDEX idx_primary_date     ON fact_primary_sales (date_id);
CREATE INDEX idx_primary_dist     ON fact_primary_sales (distributor_id);
CREATE INDEX idx_primary_sku      ON fact_primary_sales (sku_id);
CREATE INDEX idx_secondary_date   ON fact_secondary_sales (date_id);
CREATE INDEX idx_secondary_dist   ON fact_secondary_sales (distributor_id);
CREATE INDEX idx_secondary_kirana ON fact_secondary_sales (kirana_id);
CREATE INDEX idx_secondary_sku    ON fact_secondary_sales (sku_id);
CREATE INDEX idx_kirana_dist      ON dim_kirana (distributor_id);
CREATE INDEX idx_recon_dist_sku   ON fact_stock_reconciliation (distributor_id, sku_id);
