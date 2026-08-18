-- ============================================================
-- FILE 03: BUILD THE TRUTH TABLE (fact_stock_reconciliation)
-- ============================================================
-- The single most important table in the project.
-- For every distributor x SKU x day it computes the inventory
-- ledger:  closing = opening + primary_in - secondary_out
--
-- WHY IT EXPOSES FRAUD:
--   Primary sales are hard to fake (tax/revenue tied).
--   Secondary sales are easy to fake. But stock is PHYSICAL - if a
--   distributor "sells" stock that never arrived, the running
--   ledger drifts, goes negative, or balloons when hoarded.
--   This table makes the lie visible as a number.
--
-- THE TRICK: transactions are SPARSE (only days with activity have
-- rows) but a ledger must be DENSE (a row every day, even weekends
-- with zero movement, so opening/closing carry forward correctly).
-- We build a dense "date spine" first, then attach facts to it.
-- ============================================================

-- Idempotent: clear yesterday's build before rebuilding.
TRUNCATE fact_stock_reconciliation;

WITH
-- STEP 1: THE SPINE
-- CROSS JOIN = every combination of the three sets: 181 days x 20
-- distributors x 5 SKUs = 18,100 rows, one for every possible
-- (day, distributor, sku) slot that COULD hold inventory.
spine AS (
    SELECT d.date_id,
           dist.distributor_id,
           p.sku_id,
           p.units_per_case
    FROM dim_date d
    CROSS JOIN dim_distributor dist
    CROSS JOIN dim_product p
),

-- STEP 2: COLLAPSE TRANSACTIONS TO DAILY TOTALS
-- Facts can hold several shipments/deliveries per day; the ledger
-- only cares about the DAY total. GROUP BY does that collapse.
primary_daily AS (
    SELECT date_id, distributor_id, sku_id,
           SUM(qty_cases) AS qty_cases
    FROM fact_primary_sales
    GROUP BY date_id, distributor_id, sku_id
),
secondary_daily AS (
    SELECT date_id, distributor_id, sku_id,
           SUM(qty_units) AS qty_units
    FROM fact_secondary_sales
    GROUP BY date_id, distributor_id, sku_id
),

-- STEP 3: ATTACH FACTS TO THE SPINE
-- LEFT JOIN keeps every spine row even when nothing happened that
-- day; COALESCE turns the resulting NULLs into 0.
-- THIS is where the units mismatch is resolved: cases are multiplied
-- by units_per_case so inflow and outflow are finally comparable.
ledger AS (
    SELECT sp.date_id,
           sp.distributor_id,
           sp.sku_id,
           COALESCE(pr.qty_cases, 0) * sp.units_per_case AS primary_units,
           COALESCE(se.qty_units, 0)                    AS secondary_units
    FROM spine sp
    LEFT JOIN primary_daily pr
           ON pr.date_id        = sp.date_id
          AND pr.distributor_id = sp.distributor_id
          AND pr.sku_id         = sp.sku_id
    LEFT JOIN secondary_daily se
           ON se.date_id        = sp.date_id
          AND se.distributor_id = sp.distributor_id
          AND se.sku_id         = sp.sku_id
),

-- STEP 4: RUNNING TOTAL = THE WINDOW FUNCTION
-- SUM(...) OVER (PARTITION BY distributor+sku ORDER BY date
--                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
-- adds up all NET movement (in - out) of every EARLIER day for that
-- same distributor+SKU. That total IS today's opening stock.
-- The "1 PRECEDING" frame stop excludes today itself; the very first
-- day has no earlier rows -> SUM returns NULL -> COALESCE makes it 0.
running AS (
    SELECT date_id, distributor_id, sku_id,
           primary_units, secondary_units,
           COALESCE(
               SUM(primary_units - secondary_units) OVER (
                   PARTITION BY distributor_id, sku_id
                   ORDER BY date_id
                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
               ), 0) AS opening_units
    FROM ledger
)

-- STEP 5: MATERIALIZE
-- INSERT...SELECT writes the computed ledger into the physical table
-- so Phase 3 queries read it instantly instead of recomputing.
INSERT INTO fact_stock_reconciliation
    (date_id, distributor_id, sku_id,
     opening_units, primary_units, secondary_units, closing_units)
SELECT date_id, distributor_id, sku_id,
       opening_units,
       primary_units,
       secondary_units,
       opening_units + primary_units - secondary_units AS closing_units
FROM running;

-- Sanity check: expect exactly 181 x 20 x 5 = 18,100 rows.
SELECT COUNT(*) AS recon_rows,
       COUNT(DISTINCT distributor_id) AS distributors,
       COUNT(DISTINCT sku_id) AS skus
FROM fact_stock_reconciliation;
