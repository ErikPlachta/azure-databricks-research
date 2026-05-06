-- ============================================================================
-- BRIDGE FRAMEWORK — Heavy Analytical Views (mart schema)
--
-- Run after 06_analytical_views.sql.
--
-- =============================================================================
-- WHAT THIS FILE DOES
-- =============================================================================
-- The views in 06 are simple aggregations and joins. Modern Spark + Photon
-- handles those quickly enough that the live-vs-materialized comparison is
-- barely visible.
--
-- This file defines two views that exercise the query patterns where MVs
-- earn their keep. Both are realistic shapes that show up in enterprise
-- analytics workloads:
--
--   1. vw_portfolio_kpi_daily        — multi-window-function KPI dashboard
--   2. vw_position_with_external_keys — non-equi crosswalk SCD2 resolution
--
-- These deliberately stress the optimizer in ways that Photon's vectorized
-- scan can't compensate for.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- VIEW 1: vw_portfolio_kpi_daily
--
-- The KPI dashboard view: for each (date, portfolio), compute AUM plus
-- four time-windowed metrics:
--   - 7-day moving average AUM
--   - 30-day moving average AUM
--   - AUM 365 days ago (for YoY %)
--   - Rank among all portfolios on that date
--
-- WHY IT'S SLOW IN VIEW FORM
-- --------------------------
-- The base aggregation reduces 5M positions → ~730K (date × portfolio) rows.
-- Then 4 window functions execute over that result, each with PARTITION BY
-- portfolio (~100 partitions of ~7300 rows each) or PARTITION BY date
-- (~7300 partitions of ~100 rows each). Photon vectorizes the scan but
-- window evaluation is fundamentally per-partition sorted state — there's
-- no shortcut.
--
-- Expected View time on Free Edition serverless: 10–30s for a full-window
-- query, scaling roughly with output cardinality.
--
-- WHY MATERIALIZATION HELPS DRAMATICALLY HERE
-- -------------------------------------------
-- Materialized result is just ~730K rows. Reads are sub-second regardless
-- of query shape. Storage cost is negligible (a few MB).
--
-- TRADE-OFF: REFRESH IS FULL RECOMPUTE
-- ------------------------------------
-- Window functions like LAG and moving averages are NOT invertible — you
-- can't update a 30-day moving average from just the new row, you need
-- the surrounding 29 rows too. Enzyme will pick MAINTENANCE_TYPE_COMPLETE_-
-- RECOMPUTE on every refresh. For a daily-refresh dashboard this is fine;
-- for a real-time MV, this is a dealbreaker.
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_portfolio_kpi_daily AS
WITH daily_agg AS (
    SELECT
        p.position_date,
        p.portfolio_sk,
        SUM(p.market_value)            AS aum,
        SUM(p.unrealized_gain_loss)    AS unrealized_pnl,
        COUNT(DISTINCT p.entity_sk)    AS active_entity_count,
        COUNT(*)                       AS position_count
    FROM workspace.fact.position p
    GROUP BY p.position_date, p.portfolio_sk
)
SELECT
    da.position_date,
    pf.portfolio_sk,
    pf.portfolio_name,
    pf.portfolio_type,
    da.aum,
    da.unrealized_pnl,
    da.active_entity_count,
    da.position_count,

    -- 7-day moving average
    AVG(da.aum) OVER (
        PARTITION BY da.portfolio_sk
        ORDER BY da.position_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS aum_7day_ma,

    -- 30-day moving average
    AVG(da.aum) OVER (
        PARTITION BY da.portfolio_sk
        ORDER BY da.position_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS aum_30day_ma,

    -- AUM 365 days ago (NULL for first year of any portfolio's history)
    LAG(da.aum, 365) OVER (
        PARTITION BY da.portfolio_sk
        ORDER BY da.position_date
    ) AS aum_year_ago,

    -- Rank among portfolios on this date (1 = largest AUM that day)
    DENSE_RANK() OVER (
        PARTITION BY da.position_date
        ORDER BY da.aum DESC
    ) AS aum_rank_on_date

FROM daily_agg da
JOIN workspace.dim.portfolio pf ON da.portfolio_sk = pf.portfolio_sk;

-- ============================================================================
-- VIEW 2: vw_position_with_external_keys
--
-- Position records resolved through bridge.key_crosswalk to attach the
-- external system identifiers (State Street entity ID, Bloomberg security
-- ID) that were valid on each position's date.
--
-- This is what a regulatory-reporting feed or a custodian-reconciliation
-- query looks like. The downstream consumer needs the external IDs that
-- match what the source system thought at the position's effective date.
--
-- WHY IT'S SLOW IN VIEW FORM
-- --------------------------
-- Each crosswalk join is a NON-EQUI JOIN: the date predicate
--     kc.effective_start_date <= p.position_date
--     AND (kc.effective_end_date IS NULL OR kc.effective_end_date >= p.position_date)
-- can't use hash join. Spark broadcasts the small key_crosswalk table to
-- every partition of fact.position, then scans it linearly per row to find
-- the matching SCD2 version. With 5M positions × 2 non-equi crosswalk
-- joins, this is several seconds of pure CPU work that Photon can't help
-- with — it's the join algorithm itself that's expensive.
--
-- Expected View time: 30–90s for a full-window scan; 5–15s for a
-- single-month filter.
--
-- WHY MATERIALIZATION HELPS DRAMATICALLY HERE
-- -------------------------------------------
-- The materialized result is ~5M rows but already has the external IDs
-- attached. No more non-equi joins. Storage cost is real (~500MB+) but
-- query latency drops to seconds.
--
-- TRADE-OFF: REFRESH IS FULL RECOMPUTE
-- ------------------------------------
-- Non-equi joins are not incrementalizable. Enzyme picks COMPLETE_-
-- RECOMPUTE every refresh. This is the canonical case where you'd attach
-- a SCHEDULE EVERY 4 HOURS or so to the MV — accepting stale data for
-- some hours in exchange for fast reads.
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_position_with_external_keys AS
WITH
    domain_entity AS (
        SELECT domain_id FROM workspace.bridge.key_domain WHERE domain_code = 'ENTITY'
    ),
    domain_security AS (
        SELECT domain_id FROM workspace.bridge.key_domain WHERE domain_code = 'SECURITY'
    ),
    src_state_street AS (
        SELECT source_id FROM workspace.bridge.source_registry WHERE source_code = 'STATE_STREET'
    ),
    src_bloomberg AS (
        SELECT source_id FROM workspace.bridge.source_registry WHERE source_code = 'BLOOMBERG'
    )
SELECT
    p.position_id,
    p.position_date,
    pf.portfolio_name,
    e.entity_name,
    s.security_name,
    a.asset_name,
    a.country_code,
    p.quantity,
    p.market_value,
    ss_xwalk.source_key  AS state_street_entity_id,
    bbg_xwalk.source_key AS bloomberg_security_id
FROM workspace.fact.position p
JOIN workspace.dim.portfolio pf ON p.portfolio_sk = pf.portfolio_sk
JOIN workspace.dim.entity    e  ON p.entity_sk    = e.entity_sk
JOIN workspace.dim.security  s  ON p.security_sk  = s.security_sk
JOIN workspace.dim.asset     a  ON s.asset_sk     = a.asset_sk
-- Non-equi: temporal SCD2 resolution against State Street entity crosswalk
LEFT JOIN workspace.bridge.key_crosswalk ss_xwalk
    ON ss_xwalk.target_key         = e.enterprise_entity_id
   AND ss_xwalk.relationship_type  = 'ONE_TO_ONE'
   AND ss_xwalk.domain_id          = (SELECT domain_id FROM domain_entity)
   AND ss_xwalk.source_system_id   = (SELECT source_id FROM src_state_street)
   AND ss_xwalk.effective_start_date <= p.position_date
   AND (ss_xwalk.effective_end_date IS NULL OR ss_xwalk.effective_end_date >= p.position_date)
-- Non-equi: temporal SCD2 resolution against Bloomberg security crosswalk
LEFT JOIN workspace.bridge.key_crosswalk bbg_xwalk
    ON bbg_xwalk.target_key        = s.enterprise_security_id
   AND bbg_xwalk.relationship_type = 'ONE_TO_ONE'
   AND bbg_xwalk.domain_id         = (SELECT domain_id FROM domain_security)
   AND bbg_xwalk.source_system_id  = (SELECT source_id FROM src_bloomberg)
   AND bbg_xwalk.effective_start_date <= p.position_date
   AND (bbg_xwalk.effective_end_date IS NULL OR bbg_xwalk.effective_end_date >= p.position_date);

SELECT 'Heavy analytical views created.' AS status;
