-- ============================================================================
-- BRIDGE FRAMEWORK — Consumer-Layer Performance Demo
--
-- Run after 13_consumer_materialized_views.sql.
--
-- =============================================================================
-- THE DEMO QUERIES — NO FILTERING, MAXIMUM ROW VOLUME
-- =============================================================================
-- These queries do not reduce the result set with WHERE clauses. They join
-- the two consumer views and return every tuple — millions of rows.
--
-- Demo 1: full join of vw_portfolio_book ⋈ vw_security_book by
--         (portfolio_name, position_date). Result cardinality ≈ |security_book|
--         (one security row carries one portfolio row's attributes).
--         ≈ 5M rows over the full 20-year window.
--
-- Demo 2: same join, plus a window function ranking each (portfolio, year)'s
--         days by concentration. Same row volume as Demo 1, with one
--         additional integer column per row from ROW_NUMBER.
--
-- =============================================================================
-- EXPECTED RESULTS
-- =============================================================================
-- The view path will likely hit Free Edition's serverless query timeout
-- (~10 minutes). That's the demo: this query is intractable as a live view.
--
-- The MV path returns the full result in seconds-to-low-minutes, dominated
-- by network transfer of millions of rows back to the client (not by query
-- planning or execution).
--
-- If the SQL editor's result-rendering is what's slow, wrap the SELECT in
-- a CREATE TABLE ... AS SELECT to land the result in storage instead, or
-- aggregate it down (e.g., COUNT(*), SUM(market_value)) to confirm the
-- query planner cost difference without paying client-render cost.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- DEMO 1A: Slow path — joining two computed views by string keys
-- ============================================================================
SELECT
    pb.portfolio_name,
    pb.position_date,
    pb.aum,
    pb.aum_rank_on_date,
    pb.top_3_concentration_pct,
    pb.entity_count,
    sb.security_name,
    sb.entity_name,
    sb.asset_name,
    sb.market_value,
    sb.pct_of_portfolio_aum
FROM mart.vw_portfolio_book pb
JOIN mart.vw_security_book sb
    ON pb.portfolio_name = sb.portfolio_name
   AND pb.position_date  = sb.position_date
-- no WHERE: every (portfolio, date, security) tuple across the full window
ORDER BY pb.position_date DESC, pb.aum DESC, sb.pct_of_portfolio_aum DESC;

-- ============================================================================
-- DEMO 1B: Fast path — same query, MV-backed
-- ============================================================================
-- Identical query body, only the schema-qualified names change.
SELECT
    pb.portfolio_name,
    pb.position_date,
    pb.aum,
    pb.aum_rank_on_date,
    pb.top_3_concentration_pct,
    pb.entity_count,
    sb.security_name,
    sb.entity_name,
    sb.asset_name,
    sb.market_value,
    sb.pct_of_portfolio_aum
FROM mart.mv_portfolio_book pb
JOIN mart.mv_security_book sb
    ON pb.portfolio_name = sb.portfolio_name
   AND pb.position_date  = sb.position_date
-- no WHERE: every (portfolio, date, security) tuple across the full window
ORDER BY pb.position_date DESC, pb.aum DESC, sb.pct_of_portfolio_aum DESC;

-- ============================================================================
-- DEMO 2A: Slow path — peak concentration year-by-year, with attribution
-- ============================================================================
-- "For each portfolio across the entire 20-year history, find the day in
--  each calendar year where top-3 concentration peaked. For each peak,
--  list every security making up >5% of portfolio AUM on that day."
--
-- This is a risk-screening pattern. It double-touches vw_portfolio_book
-- (window-rank to find peak dates) AND joins vw_security_book at every
-- peak date (~100 portfolios × 20 years = ~2000 (portfolio, date) join keys
-- against ~5M security rows).

WITH ranked AS (
    SELECT
        portfolio_name,
        position_date,
        year(position_date) AS yr,
        aum,
        top_3_concentration_pct,
        entity_count,
        ROW_NUMBER() OVER (
            PARTITION BY portfolio_name, year(position_date)
            ORDER BY top_3_concentration_pct DESC, position_date
        ) AS rn
    FROM mart.vw_portfolio_book
)
SELECT
    r.portfolio_name,
    r.yr,
    r.position_date         AS peak_date,
    r.top_3_concentration_pct AS peak_concentration,
    r.aum                   AS aum_on_peak_date,
    r.entity_count,
    sb.security_name,
    sb.entity_name,
    sb.country_code,
    sb.market_value,
    sb.pct_of_portfolio_aum
FROM ranked r
JOIN mart.vw_security_book sb
    ON sb.portfolio_name = r.portfolio_name
   AND sb.position_date  = r.position_date
-- no WHERE: every (portfolio, date, security) tuple plus its in-year rank
ORDER BY r.portfolio_name, r.position_date, sb.pct_of_portfolio_aum DESC;

-- ============================================================================
-- DEMO 2B: Fast path — same query, MV-backed
-- ============================================================================
WITH ranked AS (
    SELECT
        portfolio_name,
        position_date,
        year(position_date) AS yr,
        aum,
        top_3_concentration_pct,
        entity_count,
        ROW_NUMBER() OVER (
            PARTITION BY portfolio_name, year(position_date)
            ORDER BY top_3_concentration_pct DESC, position_date
        ) AS rn
    FROM mart.mv_portfolio_book
)
SELECT
    r.portfolio_name,
    r.yr,
    r.position_date         AS peak_date,
    r.top_3_concentration_pct AS peak_concentration,
    r.aum                   AS aum_on_peak_date,
    r.entity_count,
    sb.security_name,
    sb.entity_name,
    sb.country_code,
    sb.market_value,
    sb.pct_of_portfolio_aum
FROM ranked r
JOIN mart.mv_security_book sb
    ON sb.portfolio_name = r.portfolio_name
   AND sb.position_date  = r.position_date
-- no WHERE: every (portfolio, date, security) tuple plus its in-year rank
ORDER BY r.portfolio_name, r.position_date, sb.pct_of_portfolio_aum DESC;

-- ============================================================================
-- WHY THIS DEMO LANDS WHEN EARLIER ONES DIDN'T
-- ============================================================================
-- The simple aggregations in 06/07 are easy for Photon. Even without MV,
-- a query like SUM-by-portfolio-by-day with a date filter pushes the date
-- predicate down to fact.position's Liquid Clustering and runs fast.
--
-- This demo blocks every shortcut Photon has:
--
--   1. Two views joined by string columns (portfolio_name) — string hash
--      join is more expensive than int hash join.
--   2. Filter on top_3_concentration_pct — computed via a 2-stage
--      aggregation + ranked window. Cannot push down to base fact.
--   3. Filter on aum_rank_on_date — DENSE_RANK over post-aggregation
--      window. Cannot push down.
--   4. Filter on pct_of_portfolio_aum — window function inside the view.
--      Cannot push down.
--   5. Filter on country_code — string equality, but country isn't a
--      clustering key on fact.position, so this scans every position
--      regardless.
--
-- Result: each view side reads the entire 5M-row fact, computes its
-- internal aggregations and windows, materializes the result in shuffle,
-- then participates in the join. Multiply by 2 (two views).
--
-- The MV side: both sides are physical Delta tables with the computed
-- columns stored as plain columns. Liquid Clustering on (portfolio_name,
-- position_date) makes the date filter selective. The string join is
-- against pre-computed compact tables. Filters apply directly.
--
-- This is the canonical case for materialization in a view-only consumer
-- architecture: when consumers can't see the optimizer's preferred join
-- keys, materialization makes the view itself the optimizer's preferred
-- starting point.
