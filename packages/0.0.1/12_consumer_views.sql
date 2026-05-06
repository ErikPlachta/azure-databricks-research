-- ============================================================================
-- BRIDGE FRAMEWORK — Consumer-Facing Views (mart schema)
--
-- Run after 06_analytical_views.sql.
--
-- =============================================================================
-- DESIGN PRINCIPLE — VIEW-ONLY CONSUMER LAYER
-- =============================================================================
-- Mirrors a real enterprise constraint: consumers cannot see surrogate keys,
-- foreign keys, or any base tables. They have only views, and they join
-- those views by HUMAN-READABLE STRINGS (portfolio_name, entity_name) plus
-- dates.
--
-- This kills predicate pushdown. The optimizer can't push filters through
-- views with computed columns or window functions, and it can't recognize
-- string-equality joins as relationships it can rewrite. Every consumer
-- query forces full evaluation of every view it touches.
--
-- This is the workload where MVs earn their keep most dramatically.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- VIEW 1: vw_portfolio_book
--
-- Daily portfolio summary, exposed entirely through strings + dates.
-- Computed columns: aum, aum_rank_on_date, top_3_concentration_pct,
-- entity_count, country_count.
--
-- WHY EXPENSIVE
-- - DENSE_RANK over portfolio×day
-- - top_3_concentration_pct requires a sub-aggregation (entity-level SUM)
--   plus a RANK-and-SUM-top-3 inside a window
-- - COUNT DISTINCT for entities and countries
-- - All of these block predicate pushdown
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_portfolio_book AS
WITH
    -- Step 1: per (date, portfolio, entity, country), aggregate position MV.
    -- This is the granularity needed for entity-level concentration and
    -- country counts.
    by_entity AS (
        SELECT
            p.position_date,
            pf.portfolio_name,
            pf.portfolio_type,
            e.enterprise_entity_id,
            a.country_code,
            SUM(p.market_value) AS entity_mv
        FROM workspace.fact.position p
        JOIN workspace.dim.portfolio pf ON p.portfolio_sk = pf.portfolio_sk
        JOIN workspace.dim.entity    e  ON p.entity_sk    = e.entity_sk
        JOIN workspace.dim.security  s  ON p.security_sk  = s.security_sk
        JOIN workspace.dim.asset     a  ON s.asset_sk     = a.asset_sk
        GROUP BY p.position_date, pf.portfolio_name, pf.portfolio_type,
                 e.enterprise_entity_id, a.country_code
    ),
    -- Step 2: rank entities within each (date, portfolio) by MV, so the
    -- top-3 concentration calc can pick the largest three.
    ranked AS (
        SELECT
            position_date,
            portfolio_name,
            portfolio_type,
            enterprise_entity_id,
            country_code,
            entity_mv,
            ROW_NUMBER() OVER (
                PARTITION BY position_date, portfolio_name
                ORDER BY entity_mv DESC
            ) AS entity_rank_in_portfolio
        FROM by_entity
    )
SELECT
    position_date,
    portfolio_name,
    portfolio_type,
    SUM(entity_mv)                                         AS aum,
    SUM(CASE WHEN entity_rank_in_portfolio <= 3 THEN entity_mv ELSE 0 END)
        / NULLIF(SUM(entity_mv), 0)                        AS top_3_concentration_pct,
    COUNT(DISTINCT enterprise_entity_id)                   AS entity_count,
    COUNT(DISTINCT country_code)                           AS country_count,
    -- Rank this portfolio against every other portfolio on this date by AUM.
    -- This is computed AFTER the row aggregation, in an outer window:
    DENSE_RANK() OVER (
        PARTITION BY position_date
        ORDER BY SUM(entity_mv) DESC
    ) AS aum_rank_on_date
FROM ranked
GROUP BY position_date, portfolio_name, portfolio_type;

-- ============================================================================
-- VIEW 2: vw_security_book
--
-- Daily security-level detail, joined to vw_portfolio_book by
-- (portfolio_name, position_date).
--
-- Exposes pct_of_portfolio_aum, which requires per-portfolio totals as a
-- window — another optimizer-blocker.
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_security_book AS
WITH per_security AS (
    SELECT
        p.position_date,
        pf.portfolio_name,
        pf.portfolio_type,
        e.entity_name,
        a.asset_name,
        a.country_code,
        s.security_name,
        s.security_type,
        SUM(p.market_value)        AS market_value,
        SUM(p.unrealized_gain_loss) AS unrealized_pnl
    FROM workspace.fact.position p
    JOIN workspace.dim.portfolio pf ON p.portfolio_sk = pf.portfolio_sk
    JOIN workspace.dim.entity    e  ON p.entity_sk    = e.entity_sk
    JOIN workspace.dim.security  s  ON p.security_sk  = s.security_sk
    JOIN workspace.dim.asset     a  ON s.asset_sk     = a.asset_sk
    GROUP BY p.position_date, pf.portfolio_name, pf.portfolio_type,
             e.entity_name, a.asset_name, a.country_code,
             s.security_name, s.security_type
)
SELECT
    position_date,
    portfolio_name,
    portfolio_type,
    entity_name,
    asset_name,
    country_code,
    security_name,
    security_type,
    market_value,
    unrealized_pnl,
    -- Per-security share of the portfolio's total AUM that day.
    -- The window function computes the per-portfolio total as a side calc.
    market_value / NULLIF(
        SUM(market_value) OVER (PARTITION BY position_date, portfolio_name),
        0
    ) AS pct_of_portfolio_aum
FROM per_security;

SELECT 'Consumer-facing views created.' AS status;
