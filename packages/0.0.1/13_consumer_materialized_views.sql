-- ============================================================================
-- BRIDGE FRAMEWORK — Consumer-Facing Materialized Views (mart schema)
--
-- Run after 12_consumer_views.sql.
--
-- =============================================================================
-- INITIAL MATERIALIZATION COST
-- =============================================================================
-- mv_portfolio_book        ~90–240s (5M agg + nested windows)
-- mv_security_book         ~120–300s (5M agg + window)
--
-- Both will refresh via MAINTENANCE_TYPE_COMPLETE_RECOMPUTE — window
-- functions are not invertible. Production usage attaches SCHEDULE for
-- off-peak refresh.
--
-- =============================================================================
-- WHY THIS PAIRING SHOWS A LARGER PERF DELTA THAN 06/07 OR 09/10
-- =============================================================================
-- The demo in 14 joins these two MVs by (portfolio_name, position_date).
-- Against the views, each side has to compute window functions over the
-- entire base fact, then the join happens, then post-join filters apply.
-- Predicate pushdown is largely defeated.
--
-- Against the MVs, both sides are pre-computed Delta tables. The query is
-- a straight equi-join + simple WHERE. Liquid Clustering on (portfolio_name,
-- position_date) makes the date filter extremely selective. Computed
-- columns are physical now — filtering on them is fast.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- MV 1: mv_portfolio_book — identical body to vw_portfolio_book
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_portfolio_book
COMMENT 'Daily portfolio book with concentration + rank metrics. Refresh = COMPLETE_RECOMPUTE.'
AS
WITH
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
    DENSE_RANK() OVER (
        PARTITION BY position_date
        ORDER BY SUM(entity_mv) DESC
    ) AS aum_rank_on_date
FROM ranked
GROUP BY position_date, portfolio_name, portfolio_type;

-- ============================================================================
-- MV 2: mv_security_book — identical body to vw_security_book
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_security_book
COMMENT 'Daily security-level book with pct-of-portfolio metric. Refresh = COMPLETE_RECOMPUTE.'
AS
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
    market_value / NULLIF(
        SUM(market_value) OVER (PARTITION BY position_date, portfolio_name),
        0
    ) AS pct_of_portfolio_aum
FROM per_security;

SELECT 'Consumer-facing materialized views created.' AS status;
