-- ============================================================================
-- 06_demos/09_cascade_demo.sql
-- Decision #13 made visible: why cascading MVs (mv* reads upstream mv*)
-- cuts gold MV materialization from 2.5h+ → ~5–10 min.
--
-- The story: in 0.1.0 (pre-Decision #13), gold MVs read silver views, which
-- read bronze views, which read raw. Every gold MV refresh re-cascaded the
-- full view stack. With 5 teams × 10 entities × view-reads-per-entity, the
-- effective cost was ~50 silver-view-runs per gold refresh.
--
-- 0.1.1's fix: gold mv reads silver mv (cached); silver mv reads bronze mv
-- (cached). Each layer pays its own refresh cost ONCE; downstream layers
-- read materialized rows.
--
-- What to watch:
--   * Section 1 — refresh in cascading order (bronze → silver → gold).
--   * Section 2 — total elapsed time vs sum of per-layer times. With
--     cascading, total ≈ sum-of-layers (because each runs serially against
--     materialized upstream, no re-cascade). Without cascading, total >>
--     sum (because each gold MV refresh recursively recomputes silver).
--   * Section 3 — change one bronze row, refresh just bronze, observe how
--     little silver/gold need to re-do. (Decision #5 + Enzyme.)
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Capture baseline: refresh in cascading order, time each layer ──────
-- Bronze first (no upstream MV chain — reads raw)
SELECT current_timestamp() AS phase_start, 'bronze' AS phase;
REFRESH MATERIALIZED VIEW bronze.mvposition;
REFRESH MATERIALIZED VIEW bronze.mvsecurity;
REFRESH MATERIALIZED VIEW bronze.mvsecurity_price;
SELECT current_timestamp() AS phase_end_bronze;

-- Silver next (reads bronze.mv* — cached, fast)
SELECT current_timestamp() AS phase_start_silver;
REFRESH MATERIALIZED VIEW investments.mvposition_analytics_fact;
REFRESH MATERIALIZED VIEW investments.mvsecurity_dim;
SELECT current_timestamp() AS phase_end_silver;

-- Gold last (reads investments.mv* — cached, fast)
SELECT current_timestamp() AS phase_start_gold;
REFRESH MATERIALIZED VIEW team_pd_direct_lending.mvposition_analytics_fact;
REFRESH MATERIALIZED VIEW gold_pd_consolidated.mvpd_position_book;
SELECT current_timestamp() AS phase_end_gold;

-- ── 2. Read the timing summary from system.query.history ──────────────────
-- After ~30s–2m delay system.query.history will reflect the refreshes.
SELECT
    statement_text,
    start_time,
    timestampdiff(MILLISECOND, start_time, end_time) / 1000.0 AS duration_seconds
FROM system.query.history
WHERE start_time > current_timestamp() - INTERVAL 10 MINUTE
  AND statement_text LIKE 'REFRESH MATERIALIZED VIEW%'
ORDER BY start_time;

-- ── 3. Compare to the slow path (running silver via the v* path) ──────────
-- This query reads silver.vposition_analytics_fact (slow path) which cascades
-- through bronze.v* down to raw. Time it; observe it's much slower than
-- reading silver.mv*.
SELECT count(*) AS slow_path_rows
FROM investments.vposition_analytics_fact;
-- ↑ Note the duration in result panel. Compare to:
SELECT count(*) AS fast_path_rows
FROM investments.mvposition_analytics_fact;
-- ↑ Should be substantially faster.

-- ── 4. Cascade reach: change one raw row, time per-layer impact ───────────
-- (Optional. Skip if you don't want to mutate seed data.)
-- Insert one row into raw_aspen, then refresh each layer in turn — observe
-- which strategies Enzyme picked (event_log per MV; see demo 07).

-- ── 5. The 0.1.0 vs 0.1.1 comparison (Decision #13 made visible) ──────────
SELECT
    'pre-0.1.1: gold mv → silver v → bronze v → raw (full re-cascade per gold mv)' AS old_path,
    'sum of N gold refreshes × M silver-views-per-gold = O(N*M) re-execution'      AS old_cost,
    '0.1.1+: gold mv → silver mv → bronze mv → raw (each layer materialized once)' AS new_path,
    'O(N + M) — each layer pays once, downstream reads materialized rows'           AS new_cost,
    '2.5h+ → ~5-10 min observed reduction at default seed'                          AS observed;

-- ── 6. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'cascading MV bodies (mv reads mv) avoid re-cascade through view stack' AS lesson_1,
    'each layer is materialized once per refresh cycle'                     AS lesson_2,
    'mechanical-derivability via s/v/mv/g preserves logical equivalence'    AS lesson_3,
    'this single architectural change is the headline 0.1.1 win'            AS impact;
