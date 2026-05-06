-- ============================================================================
-- 05_validate/03_view_mv_derivability.sql
-- Decision #13: v* and mv* SELECT projections are mechanically derivable via
-- `s/v/mv/g` substitution at upstream FROM/JOIN/IN refs. Body-text parsing
-- isn't practical from SQL alone — this file uses row-count + key-aggregate
-- equivalence as a proxy. If row counts and a salient sum match for the v*
-- and mv* of the same entity, derivability is empirically holding.
--
-- For a full body-derivation check, eyeball SHOW CREATE VIEW v.<entity> and
-- SHOW CREATE MATERIALIZED VIEW mv.<entity> side-by-side; planned as a
-- programmatic 0.1.7 CI lint.
--
-- PASS criteria (per sampled entity):
--   * row_count(v*) == row_count(mv*)
--   * sum(salient numeric column)(v*) == sum(...)(mv*)
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Bronze sample: vsecurity vs mvsecurity ──────────────────────────────
WITH v_stats AS (SELECT count(*) AS rows FROM bronze.vsecurity),
     mv_stats AS (SELECT count(*) AS rows FROM bronze.mvsecurity)
SELECT CASE WHEN v.rows = mv.rows THEN 'PASS' ELSE 'FAIL' END AS status,
       'bronze.vsecurity vs mvsecurity' AS sample,
       v.rows AS v_rows, mv.rows AS mv_rows
FROM v_stats v CROSS JOIN mv_stats mv;

-- ── 2. Silver sample: vposition_analytics_fact vs mvposition_analytics_fact ─
WITH v_stats AS (
    SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
    FROM investments.vposition_analytics_fact
), mv_stats AS (
    SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
    FROM investments.mvposition_analytics_fact
)
SELECT CASE WHEN v.rows = mv.rows AND v.mv_sum = mv.mv_sum THEN 'PASS' ELSE 'FAIL' END AS status,
       'investments.vposition_analytics_fact vs mv*' AS sample,
       v.rows AS v_rows, mv.rows AS mv_rows,
       v.mv_sum AS v_market_value_sum, mv.mv_sum AS mv_market_value_sum
FROM v_stats v CROSS JOIN mv_stats mv;

-- ── 3. Gold team sample: team_pd_direct_lending position fact ──────────────
WITH v_stats AS (
    SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
    FROM team_pd_direct_lending.vposition_analytics_fact
), mv_stats AS (
    SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
    FROM team_pd_direct_lending.mvposition_analytics_fact
)
SELECT CASE WHEN v.rows = mv.rows AND v.mv_sum = mv.mv_sum THEN 'PASS' ELSE 'FAIL' END AS status,
       'team_pd_direct_lending v vs mv (position)' AS sample,
       v.rows AS v_rows, mv.rows AS mv_rows,
       v.mv_sum AS v_sum, mv.mv_sum AS mv_sum
FROM v_stats v CROSS JOIN mv_stats mv;

-- ── 4. Gold consolidated sample: vpd_position_book ─────────────────────────
WITH v_stats AS (
    SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
    FROM gold_pd_consolidated.vpd_position_book
), mv_stats AS (
    SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
    FROM gold_pd_consolidated.mvpd_position_book
)
SELECT CASE WHEN v.rows = mv.rows AND v.mv_sum = mv.mv_sum THEN 'PASS' ELSE 'FAIL' END AS status,
       'gold_pd_consolidated vpd_position_book vs mv*' AS sample,
       v.rows AS v_rows, mv.rows AS mv_rows,
       v.mv_sum AS v_sum, mv.mv_sum AS mv_sum
FROM v_stats v CROSS JOIN mv_stats mv;

-- Note: PASS here is necessary but not sufficient. A v/mv body could differ
-- in projection (e.g. swapped column order) and still match on count+sum.
-- For a full check: SHOW CREATE VIEW <entity>; SHOW CREATE MATERIALIZED VIEW <entity>.
SELECT 'view_mv_derivability complete (4 samples checked; 0.1.7 CI will lint all entities)' AS phase;
