-- ============================================================================
-- 06_demos/03_what_is_a_table.sql
-- What is a table? Rows on disk you populate explicitly. In this codebase
-- tables paired with v* and mv* (the t_<entity> pattern) are populated by
-- per-entity refresh procs that do INSERT OVERWRITE t SELECT * FROM v.
--
-- Compare to MV:
--   * MV: Databricks decides when/how to refresh (ROW_BASED, PARTITION_OVERWRITE,
--         COMPLETE_RECOMPUTE — Enzyme picks).
--   * t_:  YOU decide when to refresh — explicit `CALL <schema>.refresh_<entity>()`.
--
-- DECISIONS.md #5 has the operational comparison table. Both materialize the
-- same logical body; different control planes.
--
-- What to watch:
--   * Section 1 — table is just rows; no SELECT body.
--   * Section 2 — refresh proc runs INSERT OVERWRITE manually.
--   * Section 3 — querying the table is the fastest of the three (no view
--     execution, no MV cache lookup logic).
--   * Section 4 — table content is whatever was last INSERT-OVERWRITten.
--     Stale until you re-run the proc.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Table definition (DDL, not query) ──────────────────────────────────
-- The DDL declares column types + clustering + table properties. No SELECT body.
SHOW CREATE TABLE bronze.t_vsecurity;

-- ── 2. Show the refresh proc ──────────────────────────────────────────────
-- The proc is a 1-statement INSERT OVERWRITE. It's the explicit "populate"
-- step you control.
DESCRIBE PROCEDURE bronze.refresh_security;

-- ── 3. Run the proc — populate the table ──────────────────────────────────
-- This is the slow step (runs the view body + writes rows). On Free Edition
-- default seed: ~5–15 seconds for a single bronze entity.
CALL bronze.refresh_security();

-- ── 4. Query the table — fast (just scans Delta files) ────────────────────
SELECT count(*) AS t_row_count, 'bronze.t_vsecurity' AS source FROM bronze.t_vsecurity;

-- ── 5. Compare row count to v* and mv* ────────────────────────────────────
-- After refresh, all three should match for the same entity.
WITH triplet AS (
    SELECT 'v'  AS kind, count(*) AS n FROM bronze.vsecurity
    UNION ALL SELECT 'mv', count(*) FROM bronze.mvsecurity
    UNION ALL SELECT 't',  count(*) FROM bronze.t_vsecurity
)
SELECT * FROM triplet ORDER BY kind;

-- ── 6. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'table = rows on disk; you control population'              AS lesson_1,
    'refresh proc = explicit INSERT OVERWRITE — you decide cadence' AS lesson_2,
    'querying is fastest of the three (no view body, no MV cache logic)' AS lesson_3,
    'tradeoff: as stale as the last proc invocation'            AS tradeoff_1,
    'best for: nightly batch where source rarely changes'       AS use_case;
