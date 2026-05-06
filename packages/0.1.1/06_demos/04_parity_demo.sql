-- ============================================================================
-- 06_demos/04_parity_demo.sql
-- Parity check: v* / mv* / t_* return the same rows after a fresh refresh.
-- This is the foundation of the artifact triplet pattern — they're three
-- materializations of the same logical body, swapped for operational reasons,
-- not different data.
--
-- DECISIONS.md #6 + #13 govern the body equivalence: byte-identical for
-- bronze (no upstream MV split); mechanically derivable via s/v/mv/g for
-- silver and gold (cascading mv* path).
--
-- What to watch:
--   * Section 1 — refresh all three artifact types for one entity.
--   * Section 2 — row counts match exactly.
--   * Section 3 — sample rows match.
--   * Section 4 — set difference is empty either direction.
--
-- If section 4 returns rows: derivability is broken. Check SHOW CREATE
-- output for both v and mv side-by-side and look for an upstream FROM/JOIN
-- ref that wasn't substituted.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Pre-flight: refresh all three (in dependency order) ────────────────
-- Bronze must be refreshed first because silver views read upstream bronze.
CALL bronze.refresh_security();
REFRESH MATERIALIZED VIEW bronze.mvsecurity;
-- (v doesn't need refresh — it's a stored query.)

-- ── 2. Row count parity ───────────────────────────────────────────────────
-- What should happen: all three counts identical.
WITH parity AS (
    SELECT 'v'  AS kind, count(*) AS n FROM bronze.vsecurity
    UNION ALL SELECT 'mv', count(*) FROM bronze.mvsecurity
    UNION ALL SELECT 't',  count(*) FROM bronze.t_vsecurity
), pivot AS (
    SELECT
        max(CASE WHEN kind = 'v'  THEN n END) AS v_rows,
        max(CASE WHEN kind = 'mv' THEN n END) AS mv_rows,
        max(CASE WHEN kind = 't'  THEN n END) AS t_rows
    FROM parity
)
SELECT
    CASE WHEN v_rows = mv_rows AND mv_rows = t_rows THEN 'PASS' ELSE 'FAIL' END AS status,
    v_rows, mv_rows, t_rows
FROM pivot;

-- ── 3. Sample row equality (first 5 by enterprise_key) ────────────────────
-- What should happen: same 5 rows in the same order from all three.
SELECT 'v'  AS kind, enterprise_key FROM bronze.vsecurity   ORDER BY enterprise_key LIMIT 5;
SELECT 'mv' AS kind, enterprise_key FROM bronze.mvsecurity  ORDER BY enterprise_key LIMIT 5;
SELECT 't'  AS kind, enterprise_key FROM bronze.t_vsecurity ORDER BY enterprise_key LIMIT 5;

-- ── 4. Set differences (should be empty either direction) ─────────────────
-- v - mv should be empty
SELECT count(*) AS rows_in_v_not_mv FROM (
    SELECT enterprise_key FROM bronze.vsecurity
    EXCEPT
    SELECT enterprise_key FROM bronze.mvsecurity
);

-- mv - v should be empty
SELECT count(*) AS rows_in_mv_not_v FROM (
    SELECT enterprise_key FROM bronze.mvsecurity
    EXCEPT
    SELECT enterprise_key FROM bronze.vsecurity
);

-- ── 5. Silver layer parity (cascading test — Decision #13) ────────────────
-- Silver mv reads bronze.mv (cascading); silver v reads bronze.v (slow path).
-- After refresh of all upstream MVs, silver v and silver mv should match.
-- Skipping refresh here because silver MV refresh is heavier — assume the
-- last full deploy refreshed everything.

WITH silver_parity AS (
    SELECT 'v'  AS kind, count(*) AS n FROM investments.vposition_analytics_fact
    UNION ALL SELECT 'mv', count(*) FROM investments.mvposition_analytics_fact
)
SELECT * FROM silver_parity ORDER BY kind;

-- ── 6. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'v/mv/t are 3 materializations of the same body'           AS lesson_1,
    'after refresh, they return identical rows'                 AS lesson_2,
    'pick which one to query based on cost/freshness tradeoff' AS lesson_3;
