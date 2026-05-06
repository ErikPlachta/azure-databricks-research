-- ============================================================================
-- 06_demos/02_what_is_an_mv.sql
-- What is a materialized view (MV)? A view whose results are pre-computed
-- and cached on disk. Querying the MV reads the cached rows; the underlying
-- SELECT body only runs at refresh time.
--
-- Compare to a view: a view runs the body on every query. An MV ran the body
-- once at refresh and stored the result; subsequent queries hit storage.
--
-- Compare to a table: structurally identical (rows on disk), but Databricks
-- manages MV refresh; tables you populate explicitly with INSERT/refresh procs.
--
-- What to watch:
--   * Section 1 — MV body looks like a view body, plus CREATE MATERIALIZED VIEW.
--   * Section 2 — querying an MV is fast (just reads cached rows).
--   * Section 3 — REFRESH MATERIALIZED VIEW recomputes the cache.
--   * Section 4 — out-of-date MV (raw mutated since last refresh) returns
--     stale rows.
--
-- Pedagogical entity: bronze.mvsecurity (paired with vsecurity in demo 01).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. MV definition ──────────────────────────────────────────────────────
-- Notice the body is the same as bronze.vsecurity (Decision #6: byte-identical
-- for bronze layer because raw has no v/mv split). The CREATE MATERIALIZED
-- VIEW prefix is the only diff.
SHOW CREATE TABLE bronze.mvsecurity;

-- ── 2. Run the MV (reads cached rows — fast) ──────────────────────────────
-- What should happen: same rows as bronze.vsecurity, but typically faster
-- because no body re-execution. (On Free Edition's small seed, the timing
-- difference may be small; on paid scale it's dramatic — see demo 05.)
SELECT count(*) AS mv_row_count, 'bronze.mvsecurity' AS source FROM bronze.mvsecurity;

-- ── 3. Trigger an MV refresh ──────────────────────────────────────────────
-- This recomputes the cache. Watch the result panel for refresh duration.
-- On Free Edition default seed: <30 seconds for a single bronze MV.
REFRESH MATERIALIZED VIEW bronze.mvsecurity;

-- ── 4. Confirm rows post-refresh ──────────────────────────────────────────
SELECT count(*) AS mv_row_count_post_refresh FROM bronze.mvsecurity;

-- ── 5. Demonstrate staleness vs view ──────────────────────────────────────
-- Insert a fake row into raw, query both v and mv, then refresh the mv.
-- v immediately reflects the new row; mv reflects it only after refresh.
-- (See demo 06_freshness_demo.sql for the full freshness story.)

-- ── 6. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'MV = view + cached results'                                  AS lesson_1,
    'querying an MV reads storage (fast); querying a view re-runs the body' AS lesson_2,
    'REFRESH MATERIALIZED VIEW recomputes the cache'              AS lesson_3,
    'tradeoff: MVs are stale between refreshes — speed vs freshness' AS tradeoff;

-- ── 7. Refresh strategies (Decision #5 + Databricks docs) ─────────────────
-- Databricks chooses one of three refresh strategies per MV:
--   * ROW_BASED            — incremental row-level updates (Enzyme decides)
--   * PARTITION_OVERWRITE  — recompute affected partitions only
--   * COMPLETE_RECOMPUTE   — full rebuild
-- See demo 07_refresh_cost_demo.sql for how to inspect which one fired.
SELECT 'mv strategy depends on body shape + upstream change' AS detail;
