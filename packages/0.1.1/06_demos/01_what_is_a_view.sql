-- ============================================================================
-- 06_demos/01_what_is_a_view.sql
-- What is a view? A stored SELECT statement. Nothing is materialized; every
-- time you query the view, Databricks executes the underlying SELECT body
-- against upstream tables (or upstream views, recursively). No data lives
-- in the view itself.
--
-- Compare to a table: a table holds rows. A view is a saved query.
--
-- What to watch:
--   * Section 1 — view body is a query against raw tables.
--   * Section 2 — running the view re-executes that query.
--   * Section 3 — the view's row count matches what the body would produce
--     if you copy-pasted it inline.
--
-- Pedagogical entity: bronze.vsecurity (cleanest example — no SCD2 chains,
-- single-output dim from one bronze layer).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. View definition (read-only — already exists from deploy) ───────────
-- This shows the SELECT body that runs every time bronze.vsecurity is queried.
SHOW CREATE TABLE bronze.vsecurity;

-- ── 2. Run the view (executes the body fresh against upstream raw tables) ─
-- What should happen: returns rows as if the SELECT body ran inline.
SELECT *
FROM bronze.vsecurity
LIMIT 10;

-- ── 3. Row count — same body, same rows ───────────────────────────────────
-- What should happen: stable count across multiple runs (assuming raw_aspen
-- doesn't change between runs).
SELECT count(*) AS view_row_count, 'bronze.vsecurity' AS source FROM bronze.vsecurity;

-- ── 4. Demonstrate "view = stored query" with an inline equivalent ────────
-- This query body MIRRORS what bronze.vsecurity does internally (simplified).
-- Both should return the same row count → view is just a saved query.
WITH inline_view AS (
    SELECT enterprise_key
    FROM raw_aspen.security_master_raw
)
SELECT count(*) AS inline_count FROM inline_view;
-- ↑ count won't exactly match bronze.vsecurity (which adds bronze fields like
-- _source_pref) but the ORDER OF MAGNITUDE will. Run both — they're both
-- queries the engine evaluates fresh.

-- ── 5. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'view = stored query; no data materialized'                   AS lesson_1,
    'every query re-executes the body against upstream'            AS lesson_2,
    'changes to upstream tables are visible immediately to the view' AS lesson_3,
    'cost: the body runs every time the view is queried'           AS tradeoff;
