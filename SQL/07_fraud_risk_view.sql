-- ============================================================
-- FILE 07: THE FRAUD RISK SCORE VIEW
-- ============================================================
-- One query to rule them all: fuse the three detectors into a
-- single ranked risk list per distributor.
--
-- KEY SQL CONCEPT - THE VIEW:
--   CREATE VIEW stores a query in the database under a name.
--   Every future SELECT * FROM vw_fraud_risk_score re-runs the
--   logic live - always fresh, never stale, no maintenance job.
--   BI tools (Power BI etc.) connect to views, not giant queries.
--
-- THE SCORING MODEL (transparent by design - auditors hate black boxes):
--   Channel Stuffing : 10 pts per flagged month-end spike, cap 40
--   Promo Leakage    : 30 pts if any hoard-&-dump pattern found
--   Route Falsif.    : 30 pts if bulk dumps >= 20% of volume,
--                      12 pts if repeated dumps exist at all
--   Tiers: >= 60 CRITICAL | >= 25 HIGH | > 0 MEDIUM | 0 CLEAN
-- ============================================================

CREATE OR REPLACE VIEW vw_fraud_risk_score AS
WITH
-- --- Detector 1 recap: month-end primary spikes >= 4x trailing avg
-- (aggregated to distributor-DAY grain first - see file 04 for why)
stuffing AS (
    SELECT distributor_id, COUNT(*) AS spike_days
    FROM (
        SELECT win.date_id,
               win.distributor_id,
               win.primary_units,
               win.trail_avg,
               dd.is_month_end
        FROM (
            SELECT a.date_id,
                   a.distributor_id,
                   a.primary_units,
                   AVG(a.primary_units) OVER (
                       PARTITION BY a.distributor_id
                       ORDER BY a.date_id
                       ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
                   ) AS trail_avg
            FROM (
                SELECT date_id, distributor_id,
                       SUM(primary_units) AS primary_units
                FROM fact_stock_reconciliation
                GROUP BY date_id, distributor_id
            ) a
        ) win
        JOIN dim_date dd ON dd.date_id = win.date_id
        WHERE dd.is_month_end
          AND win.trail_avg >= 500
          AND win.primary_units >= 4 * win.trail_avg
    ) flagged
    GROUP BY distributor_id
),
-- --- Detector 2 recap: SKU hoarded through a promo then dumped after
promo_leak AS (
    SELECT distributor_id, COUNT(*) AS leaked_skus
    FROM (
        SELECT r.distributor_id, r.sku_id
        FROM dim_promotion pr
        JOIN fact_stock_reconciliation r ON r.sku_id = pr.sku_id
        JOIN dim_date dd ON dd.date_id = r.date_id
        -- Restrict to baseline + promo + 15-day post window. Without
        -- this, the post-promo average stretches to end of data and
        -- dilutes the dump signal below the threshold (bug we hit live:
        -- DIST018 silently vanished from the risk list).
        WHERE dd.full_date BETWEEN pr.promo_start - INTERVAL '14 days'
                              AND pr.promo_end   + INTERVAL '15 days'
        GROUP BY r.distributor_id, r.sku_id
        HAVING AVG(r.secondary_units) FILTER (
                    WHERE dd.full_date BETWEEN pr.promo_start AND pr.promo_end)
               <= 0.1 * AVG(r.secondary_units) FILTER (
                    WHERE dd.full_date < pr.promo_start)
           AND AVG(r.secondary_units) FILTER (
                    WHERE dd.full_date < pr.promo_start) >= 50
           AND AVG(r.secondary_units) FILTER (
                    WHERE dd.full_date > pr.promo_end)
               >= 1.5 * AVG(r.secondary_units) FILTER (
                    WHERE dd.full_date < pr.promo_start)
    ) leaked_skus_list
    GROUP BY distributor_id
),
-- --- Detector 3 recap: bulk dumps (>=100 units to one kirana in a day)
route AS (
    SELECT distributor_id,
           COUNT(*) FILTER (WHERE qty_units >= 100) AS bulk_dumps,
           100.0 * COALESCE(SUM(qty_units) FILTER (WHERE qty_units >= 100), 0)
               / SUM(qty_units)                     AS bulk_share
    FROM fact_secondary_sales
    GROUP BY distributor_id
)
-- SQL cannot reference a column alias elsewhere in the SAME SELECT
-- list, so points are computed in an inner query and the total +
-- tier (which DO depend on the points) in a clean outer query.
SELECT distributor_id,
       distributor_name,
       region,
       stuffing_flags,
       promo_leak_flags,
       route_dump_events,
       bulk_volume_pct,
       stuffing_pts,
       promo_pts,
       route_pts,
       stuffing_pts + promo_pts + route_pts AS risk_score,
       CASE WHEN stuffing_pts + promo_pts + route_pts >= 60 THEN 'CRITICAL'
            WHEN stuffing_pts + promo_pts + route_pts >= 25 THEN 'HIGH'
            WHEN stuffing_pts + promo_pts + route_pts >  0  THEN 'MEDIUM'
            ELSE 'CLEAN'
       END AS risk_tier
FROM (
    SELECT d.distributor_id,
           d.distributor_name,
           d.region,
           COALESCE(st.spike_days, 0)                   AS stuffing_flags,
           COALESCE(pl.leaked_skus, 0)                  AS promo_leak_flags,
           COALESCE(rt.bulk_dumps, 0)                   AS route_dump_events,
           ROUND(COALESCE(rt.bulk_share, 0), 1)         AS bulk_volume_pct,
           LEAST(40, COALESCE(st.spike_days, 0) * 10)   AS stuffing_pts,
           CASE WHEN COALESCE(pl.leaked_skus, 0) > 0
                THEN 30 ELSE 0 END                      AS promo_pts,
           CASE WHEN COALESCE(rt.bulk_share, 0) >= 0.20 THEN 30
                WHEN COALESCE(rt.bulk_dumps, 0) >= 5     THEN 12
                ELSE 0 END                              AS route_pts
    FROM dim_distributor d
    LEFT JOIN stuffing   st ON st.distributor_id = d.distributor_id
    LEFT JOIN promo_leak pl ON pl.distributor_id = d.distributor_id
    LEFT JOIN route      rt ON rt.distributor_id = d.distributor_id
) scored;

-- Ranked risk list: the Regional Sales Manager's daily read.
SELECT distributor_id, distributor_name, region,
       stuffing_flags, promo_leak_flags, route_dump_events,
       stuffing_pts, promo_pts, route_pts,
       risk_score, risk_tier
FROM vw_fraud_risk_score
ORDER BY risk_score DESC, distributor_id
LIMIT 10;
