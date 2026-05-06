-- ============================================================================
-- 06_demos/05_timing_demo.sql
-- Cold cache vs warm cache vs cached MV: when does each pay off?
--
-- The lesson: views re-execute their body every query. MVs/tables read
-- materialized rows. For complex multi-join bodies, MVs/tables can be
-- 10-100x faster — but only after refresh; the FIRST time the MV is
-- queried after refresh, the cost shows up.
--
-- What to watch (in result-panel duration):
--   * Section 1 — view query: cold (first time, no Spark cache).
--   * Section 2 — view query: warm (re-run, Spark may cache plan/data).
--   * Section 3 — MV query: should be consistently fast.
--   * Section 4 — table query: fastest of all (no view body, just file scan).
--
-- Free Edition note: timing differences are smaller than at paid scale.
-- On paid (~2.5M positions vs ~100K Free): 0.0.1's `08_mv_performance_demo.sql`
-- shows 10-20x multipliers. On Free, expect 2-5x.
--
-- Pedagogical entity: gold consolidated position book — wide UNION across
-- 5 teams, executes the heaviest cascade in 0.1.1.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 0. Prep: clear Spark cache + refresh MV/table (so timing is fair) ─────
-- Run this section once. Subsequent reads will start cold.
CACHE TABLE gold_pd_consolidated.t_vpd_position_book;  -- cache the table once
UNCACHE TABLE gold_pd_consolidated.t_vpd_position_book;
-- (UNCACHE puts table reads back on cold-disk path so the test below is fair.)

-- ── 1. View query — cold cache ─────────────────────────────────────────────
-- What should happen: SLOW. Every query re-runs the body, which UNIONs 5
-- team views. Each team view reads investments.v* (silver views), which read
-- bronze.v* (bronze views), which read raw tables. Full cascade through view
-- stack.
SELECT count(*) AS v_cold_rows, sum(market_value_usd) AS v_cold_total_mv
FROM gold_pd_consolidated.vpd_position_book;
-- ↑ Note query duration in result-panel footer.

-- ── 2. View query — warm cache (re-run) ───────────────────────────────────
-- What should happen: faster than #1 but still slower than #3/#4. Spark may
-- cache parts of the plan, but the view body still runs every time.
SELECT count(*) AS v_warm_rows, sum(market_value_usd) AS v_warm_total_mv
FROM gold_pd_consolidated.vpd_position_book;

-- ── 3. MV query — cached results ──────────────────────────────────────────
-- What should happen: fast. Reads pre-computed mv rows. No view body
-- executes; no upstream cascade.
SELECT count(*) AS mv_rows, sum(market_value_usd) AS mv_total
FROM gold_pd_consolidated.mvpd_position_book;

-- ── 4. Table query — file scan only ───────────────────────────────────────
-- What should happen: fastest. Pure Delta file scan; no view logic at all.
SELECT count(*) AS t_rows, sum(market_value_usd) AS t_total
FROM gold_pd_consolidated.t_vpd_position_book;

-- ── 5. Counter-example: trivial query, all three artifacts ────────────────
-- For a simple query, the difference between v / mv / t can be small —
-- the view body's overhead is dominated by I/O. Ranks-by-value of the same
-- entity:
SELECT 'v'  AS kind, max(market_value_usd) AS top_position FROM gold_pd_consolidated.vpd_position_book;
SELECT 'mv' AS kind, max(market_value_usd) AS top_position FROM gold_pd_consolidated.mvpd_position_book;
SELECT 't'  AS kind, max(market_value_usd) AS top_position FROM gold_pd_consolidated.t_vpd_position_book;

-- ── 6. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'v takes ~10x longer than mv/t for heavy bodies (5-team UNION)'   AS lesson_1,
    'mv/t are roughly equivalent for query speed; differ in refresh control' AS lesson_2,
    'simple queries (single column, single fact) show smaller spread' AS lesson_3,
    'rule of thumb: MV when body is reused; t when refresh cadence matters' AS rule_of_thumb;
