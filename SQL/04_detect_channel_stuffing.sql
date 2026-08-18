-- ============================================================
-- FILE 04: DETECTOR 1 - CHANNEL STUFFING
-- ============================================================
-- THE FRAUD SIGNATURE:
--   A sales rep forces a distributor to buy massive stock on the
--   last day(s) of a month so the REP hits his quarterly target.
--   The distributor's warehouse silently chokes on inventory.
--   Symptom: primary purchases spike at month-end while secondary
--   sales to kiranas stay flat - goods moved on PAPER only.
--
-- THE DETECTION IDEA:
--   Compare each day's primary purchases against the distributor's
--   own trailing 28-day average (his "normal"). A genuine demand
--   surge lifts secondary sales too; stuffing does not. We flag
--   month-end days where primary >= 4x the trailing average.
--
-- KEY SQL CONCEPT - THE WINDOW FUNCTION:
--   AVG() OVER (PARTITION BY ... ORDER BY date
--               ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING)
--   A normal AVG() collapses rows; AVG() OVER keeps every row and
--   attaches a "neighbourhood statistic" to it. The frame
--   "28 PRECEDING AND 1 PRECEDING" = the 28 days BEFORE today.
--   (This only equals 28 calendar days BECAUSE our reconciliation
--   table is dense - one row per day. On sparse data a "row" is
--   not a "day". That is why Phase 2 built the date spine.)
-- ============================================================

-- GRAIN LESSON (a bug we hit live): fact_stock_reconciliation has
-- one row per distributor x SKU x day, and SKUs ship in wildly
-- different case sizes (40 to 200 units/case). Comparing a single
-- SKU-day against a trail averaged across ALL SKUs produces phantom
-- "spikes" - and "28 PRECEDING rows" stops meaning 28 days. Rule:
-- AGGREGATE TO THE GRAIN YOU COMPARE AT. So first we roll the five
-- SKU rows up into one distributor-day total, then window over that.
WITH dist_day AS (
    SELECT date_id,
           distributor_id,
           SUM(primary_units)   AS primary_units,
           SUM(secondary_units) AS secondary_units
    FROM fact_stock_reconciliation
    GROUP BY date_id, distributor_id          -- now 1 row per dist-day
),
daily AS (
    SELECT r.distributor_id,
           r.date_id,
           r.primary_units,
           r.secondary_units,
           AVG(r.primary_units) OVER w AS trail_primary_avg,
           AVG(r.secondary_units) OVER w AS trail_secondary_avg
    FROM dist_day r
    -- Named WINDOW clause: define the frame once, use it twice.
    WINDOW w AS (
        PARTITION BY r.distributor_id
        ORDER BY r.date_id
        ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
    )
)
SELECT d.distributor_id,
       dist.distributor_name,
       dd.full_date      AS spike_date,
       d.primary_units,
       ROUND(d.trail_primary_avg)                        AS trail_28d_avg,
       ROUND((d.primary_units
              / NULLIF(d.trail_primary_avg, 0))::numeric, 1) AS spike_ratio,
       d.secondary_units,
       ROUND(d.trail_secondary_avg)                      AS trail_sec_avg
FROM daily d
JOIN dim_date dd         ON dd.date_id = d.date_id
JOIN dim_distributor dist ON dist.distributor_id = d.distributor_id
WHERE dd.is_month_end                        -- stuffing is a month-end disease
  AND d.trail_primary_avg >= 500             -- ignore noise from tiny histories
  AND d.primary_units >= 4 * d.trail_primary_avg  -- the spike test: 4x normal
ORDER BY spike_ratio DESC;
