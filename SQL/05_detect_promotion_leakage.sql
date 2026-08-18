-- ============================================================
-- FILE 05: DETECTOR 2 - PROMOTION LEAKAGE (HOARD & DUMP)
-- ============================================================
-- THE FRAUD SIGNATURE:
--   During a promo the company sells to the distributor at a
--   discount. A dishonest distributor HOARDS the cheap stock
--   (reports zero secondary sales during the window), then DUMPS
--   it at full margin right after the promo ends. The company
--   paid for a promotion that never reached a single consumer.
--
-- THE DETECTION IDEA:
--   For every distributor x promoted SKU, compare average daily
--   secondary sales across three windows:
--     BASELINE: 14 days before the promo
--     PROMO:    during the promo
--     POST:     15 days after the promo
--   Leakage = promo sales collapse to ~zero while the distributor
--   demonstrably HAS stock, then sales bounce ABOVE baseline.
--
-- KEY SQL CONCEPT - FILTER (THE MODERN CONDITIONAL AGGREGATE):
--   AVG(x) FILTER (WHERE condition) averages only matching rows -
--   same result as three separate CASE-WHEN SUMs, but readable.
--   One scan of the table computes all three windows at once.
-- ============================================================

-- ---------- PART A: the detector ----------
WITH windowed AS (
    SELECT r.distributor_id,
           r.sku_id,
           AVG(r.secondary_units) FILTER (
               WHERE dd.full_date >= pr.promo_start - INTERVAL '14 days'
                 AND dd.full_date <  pr.promo_start)                AS baseline_daily,
           AVG(r.secondary_units) FILTER (
               WHERE dd.full_date BETWEEN pr.promo_start AND pr.promo_end
           )                                                        AS promo_daily,
           AVG(r.secondary_units) FILTER (
               WHERE dd.full_date >  pr.promo_end
                 AND dd.full_date <= pr.promo_end + INTERVAL '15 days'
           )                                                        AS post_promo_daily,
           -- Proof the "zero sales" was hoarding, not out-of-stock:
           MAX(r.closing_units) FILTER (
               WHERE dd.full_date = pr.promo_end)                   AS stock_at_promo_end
    FROM dim_promotion pr
    JOIN fact_stock_reconciliation r ON r.sku_id = pr.sku_id
    JOIN dim_date dd                 ON dd.date_id = r.date_id
    WHERE dd.full_date BETWEEN pr.promo_start - INTERVAL '14 days'
                            AND pr.promo_end   + INTERVAL '15 days'
    GROUP BY r.distributor_id, r.sku_id
)
SELECT distributor_id,
       sku_id,
       ROUND(baseline_daily, 1)   AS baseline_daily_units,
       ROUND(promo_daily, 1)      AS promo_daily_units,
       ROUND(post_promo_daily, 1) AS post_promo_units,
       stock_at_promo_end,
       CASE
           WHEN promo_daily    <= 0.1 * baseline_daily   -- sold ~nothing in the window
            AND baseline_daily >= 50                     -- was genuinely active before
            AND post_promo_daily >= 1.5 * baseline_daily -- then dumped above normal
           THEN 'LEAKAGE - HOARD & DUMP'
           ELSE 'OK'
       END AS verdict
FROM windowed
ORDER BY verdict, distributor_id;

-- ---------- PART B: pinpoint the dump day (LAG + DISTINCT ON) ----------
-- LAG() looks one row back in time; DISTINCT ON keeps the first row
-- per group - together they answer "on which exact day did the
-- hoarder switch the tap back on?"
WITH leaked AS (
    SELECT r.distributor_id, r.sku_id, pr.promo_end
    FROM dim_promotion pr
    JOIN fact_stock_reconciliation r ON r.sku_id = pr.sku_id
    JOIN dim_date dd ON dd.date_id = r.date_id
    GROUP BY r.distributor_id, r.sku_id, pr.promo_end
    HAVING AVG(r.secondary_units) FILTER (
                WHERE dd.full_date BETWEEN pr.promo_start AND pr.promo_end)
           <= 0.1 * AVG(r.secondary_units) FILTER (
                WHERE dd.full_date < pr.promo_start)
       AND AVG(r.secondary_units) FILTER (
                WHERE dd.full_date < pr.promo_start) >= 50
),
daily AS (
    SELECT l.distributor_id,
           l.sku_id,
           l.promo_end,
           dd.full_date,
           r.secondary_units,
           LAG(r.secondary_units) OVER (
               PARTITION BY l.distributor_id, l.sku_id
               ORDER BY dd.full_date) AS prev_day_units
    FROM leaked l
    JOIN fact_stock_reconciliation r
         ON r.distributor_id = l.distributor_id AND r.sku_id = l.sku_id
    JOIN dim_date dd ON dd.date_id = r.date_id
)
SELECT DISTINCT ON (distributor_id, sku_id)
       distributor_id,
       sku_id,
       full_date        AS resumed_selling_on,
       secondary_units  AS units_sold_that_day
FROM daily
WHERE prev_day_units = 0      -- yesterday: hoarding
  AND secondary_units > 0     -- today: selling again
  AND full_date > promo_end   -- only interested in the post-promo dump
ORDER BY distributor_id, sku_id, full_date;
