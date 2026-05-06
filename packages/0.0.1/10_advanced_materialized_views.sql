-- ============================================================================
-- BRIDGE FRAMEWORK — Heavy Materialized Views (mart schema)
--
-- Run after 09_advanced_views.sql.
--
-- =============================================================================
-- WHAT TO EXPECT WHEN RUNNING THIS FILE
-- =============================================================================
-- Both MVs trigger an initial materialization on CREATE. Initial cost on
-- Free Edition serverless against ~5M position rows:
--
--   mv_portfolio_kpi_daily          ~60–180s
--                                   (5M → 730K agg + 4 window functions)
--
--   mv_position_with_external_keys  ~120–360s
--                                   (5M × 2 non-equi crosswalk joins)
--
-- These are one-time costs. Subsequent reads are sub-second.
--
-- =============================================================================
-- REFRESH PROFILE — IMPORTANT TRADE-OFF
-- =============================================================================
-- Both of these MVs will pick MAINTENANCE_TYPE_COMPLETE_RECOMPUTE on every
-- refresh. The reasons:
--
--   mv_portfolio_kpi_daily: window functions (LAG, moving averages,
--                           DENSE_RANK) are not invertible. You can't
--                           update a 30-day MA from one new row.
--
--   mv_position_with_external_keys: non-equi joins (date range predicates
--                                   in the crosswalk lookup) are not
--                                   incrementalizable.
--
-- Production deployment pattern for these would be:
--   CREATE OR REPLACE MATERIALIZED VIEW ...
--   SCHEDULE CRON '0 0 6 * * ?' AT TIME ZONE 'UTC'  -- every day at 6am UTC
--   AS SELECT ...
--
-- The refresh runs once a day off-peak; consumers query a fresh-as-of-6am
-- snapshot all day. For dashboards this is usually fine; for real-time
-- reporting it's not.
--
-- We omit SCHEDULE here so refreshes are manual and predictable for the
-- demo. File 11 has a refresh-planning inspection cell that shows the
-- chosen technique.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- MV 1: mv_portfolio_kpi_daily
-- IDENTICAL body to mart.vw_portfolio_kpi_daily.
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_portfolio_kpi_daily
COMMENT 'Daily portfolio KPIs with windowed metrics. Refreshes via COMPLETE_RECOMPUTE.'
AS
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
    AVG(da.aum) OVER (
        PARTITION BY da.portfolio_sk
        ORDER BY da.position_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS aum_7day_ma,
    AVG(da.aum) OVER (
        PARTITION BY da.portfolio_sk
        ORDER BY da.position_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS aum_30day_ma,
    LAG(da.aum, 365) OVER (
        PARTITION BY da.portfolio_sk
        ORDER BY da.position_date
    ) AS aum_year_ago,
    DENSE_RANK() OVER (
        PARTITION BY da.position_date
        ORDER BY da.aum DESC
    ) AS aum_rank_on_date
FROM daily_agg da
JOIN workspace.dim.portfolio pf ON da.portfolio_sk = pf.portfolio_sk;

-- ============================================================================
-- MV 2: mv_position_with_external_keys
-- IDENTICAL body to mart.vw_position_with_external_keys.
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_position_with_external_keys
COMMENT 'Positions with crosswalk-resolved external IDs. Refreshes via COMPLETE_RECOMPUTE.'
AS
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
LEFT JOIN workspace.bridge.key_crosswalk ss_xwalk
    ON ss_xwalk.target_key         = e.enterprise_entity_id
   AND ss_xwalk.relationship_type  = 'ONE_TO_ONE'
   AND ss_xwalk.domain_id          = (SELECT domain_id FROM domain_entity)
   AND ss_xwalk.source_system_id   = (SELECT source_id FROM src_state_street)
   AND ss_xwalk.effective_start_date <= p.position_date
   AND (ss_xwalk.effective_end_date IS NULL OR ss_xwalk.effective_end_date >= p.position_date)
LEFT JOIN workspace.bridge.key_crosswalk bbg_xwalk
    ON bbg_xwalk.target_key        = s.enterprise_security_id
   AND bbg_xwalk.relationship_type = 'ONE_TO_ONE'
   AND bbg_xwalk.domain_id         = (SELECT domain_id FROM domain_security)
   AND bbg_xwalk.source_system_id  = (SELECT source_id FROM src_bloomberg)
   AND bbg_xwalk.effective_start_date <= p.position_date
   AND (bbg_xwalk.effective_end_date IS NULL OR bbg_xwalk.effective_end_date >= p.position_date);

SELECT 'Heavy materialized views created. Initial materialization complete.' AS status;
