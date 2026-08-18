-- ============================================================
-- FILE 06: DETECTOR 3 - ROUTE / BEAT FALSIFICATION
-- ============================================================
-- THE FRAUD SIGNATURE:
--   A distributor is contractually required to visit ~10 kirana
--   shops per route per day. To save fuel and time he instead
--   DUMPS the entire route's stock on one single shop (one big
--   invoice, full route "covered"). The company pays route
--   allowances for beats that never happened.
--
-- THE DETECTION IDEA:
--   Look at the size distribution of individual drops (one
--   secondary_sales row = one drop at one kirana). Honest
--   replenishment for a tiny shop is single-digit-to-20 units.
--   A drop of 100+ units to ONE shop in ONE day is physically
--   implausible - no kirana can shelve it. We count such "bulk
--   dumps" per distributor and add classic outlier statistics
--   (z-score of the biggest drop) as supporting evidence.
--
-- KEY SQL CONCEPT - THE Z-SCORE:
--   z = (value - mean) / standard_deviation
--   "How many standard deviations above normal is this value?"
--   Rule of thumb: |z| > 3 = statistically remarkable;
--   z > 7-8 on the max drop = deliberate behaviour, not luck.
-- ============================================================

WITH drop_stats AS (
    SELECT distributor_id,
           COUNT(*)                    AS total_drops,
           ROUND(AVG(qty_units), 1)    AS avg_drop_units,
           ROUND(STDDEV_SAMP(qty_units), 1) AS std_drop_units,
           MAX(qty_units)              AS max_drop_units,
           -- z-score of the single biggest drop this distributor ever made
           ROUND((MAX(qty_units) - AVG(qty_units))
                 / NULLIF(STDDEV_SAMP(qty_units), 0), 1) AS max_drop_z_score,
           COUNT(*) FILTER (WHERE qty_units >= 100)      AS bulk_dumps,
           COUNT(DISTINCT kirana_id)
                FILTER (WHERE qty_units >= 100)          AS kiranas_hit_by_dumps,
           ROUND(100.0 * COALESCE(SUM(qty_units)
                    FILTER (WHERE qty_units >= 100), 0)
                 / SUM(qty_units), 1)                    AS bulk_volume_pct
    FROM fact_secondary_sales
    GROUP BY distributor_id
)
SELECT s.distributor_id,
       d.distributor_name,
       s.total_drops,
       s.avg_drop_units,
       s.max_drop_units,
       s.max_drop_z_score,
       s.bulk_dumps,
       s.kiranas_hit_by_dumps,
       s.bulk_volume_pct,
       CASE
           WHEN s.bulk_dumps >= 5          THEN 'FALSIFIED - BULK DUMPING'
           WHEN s.bulk_dumps > 0           THEN 'SUSPECT - INVESTIGATE'
           ELSE 'OK'
       END AS verdict
FROM drop_stats s
JOIN dim_distributor d USING (distributor_id)
ORDER BY s.bulk_dumps DESC, s.max_drop_units DESC;
