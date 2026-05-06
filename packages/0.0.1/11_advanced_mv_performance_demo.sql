-- ============================================================================
-- BRIDGE FRAMEWORK — Heavy MV Performance Demo
--
-- Run after 10_advanced_materialized_views.sql.
--
-- =============================================================================
-- WHAT TO LOOK FOR
-- =============================================================================
-- Each demo runs the SAME query against the View (slow) and the MV (fast).
-- Watch the query duration in the SQL editor footer.
--
-- Expected results on Free Edition serverless against ~5M position rows:
--
--   DEMO 1  Top portfolios by AUM with windowed KPIs (full window)
--     vw_portfolio_kpi_daily          ~15–45s
--     mv_portfolio_kpi_daily          <1s
--     -> 30–50× speedup. Window functions are the killer in views.
--
--   DEMO 2  Top portfolios — single-day snapshot
--     vw_portfolio_kpi_daily          ~10–30s (still computes whole view)
--     mv_portfolio_kpi_daily          <1s
--     -> Predicate pushdown helps the MV more than the view, because
--        windows in the view definition force materialization of the
--        full result before filtering.
--
--   DEMO 3  Custodian reconciliation feed (1 month)
--     vw_position_with_external_keys  ~10–30s
--     mv_position_with_external_keys  ~2–5s
--     -> 5–10× speedup. Non-equi crosswalk joins eliminated.
--
--   DEMO 4  Full-window export (no date filter)
--     vw_position_with_external_keys  ~60–120s+
--     mv_position_with_external_keys  ~10–20s
--     -> 5–10×. MV still has to return ~5M rows; saves only the join cost.
--
--   DEMO 5  Refresh planning inspection — confirms COMPLETE_RECOMPUTE is
--           chosen for both, illustrating the trade-off.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- DEMO 1: Top portfolios by AUM today, with full KPI context
-- ============================================================================
-- "What are the 20 largest portfolios today, with their YoY change,
--  rank, and recent moving averages?"
--
-- This is a typical CFO-dashboard query. The view has to compute window
-- functions over the entire 5M-row history before applying the date and
-- LIMIT predicates.

-- ── 1A: Plain view (slow path) ────────────────────────────────────────────
SELECT
    portfolio_name,
    portfolio_type,
    aum,
    aum_year_ago,
    CASE WHEN aum_year_ago IS NULL OR aum_year_ago = 0 THEN NULL
         ELSE (aum - aum_year_ago) / aum_year_ago * 100
    END AS yoy_pct_change,
    aum_7day_ma,
    aum_30day_ma,
    aum_rank_on_date
FROM mart.vw_portfolio_kpi_daily
WHERE position_date = (SELECT MAX(position_date) FROM mart.vw_portfolio_kpi_daily)
ORDER BY aum DESC
LIMIT 20;

-- ── 1B: Materialized view (fast path) ─────────────────────────────────────
SELECT
    portfolio_name,
    portfolio_type,
    aum,
    aum_year_ago,
    CASE WHEN aum_year_ago IS NULL OR aum_year_ago = 0 THEN NULL
         ELSE (aum - aum_year_ago) / aum_year_ago * 100
    END AS yoy_pct_change,
    aum_7day_ma,
    aum_30day_ma,
    aum_rank_on_date
FROM mart.mv_portfolio_kpi_daily
WHERE position_date = (SELECT MAX(position_date) FROM mart.mv_portfolio_kpi_daily)
ORDER BY aum DESC
LIMIT 20;

-- ============================================================================
-- DEMO 2: KPI history for a specific portfolio — full timeline
-- ============================================================================
-- "Pull the full 20-year KPI timeline for portfolio_sk = 1."
-- This forces the view to materialize the entire windowed result.

-- ── 2A: Plain view (slow path) ────────────────────────────────────────────
SELECT
    position_date,
    aum,
    aum_7day_ma,
    aum_30day_ma,
    aum_year_ago,
    aum_rank_on_date,
    active_entity_count
FROM mart.vw_portfolio_kpi_daily
WHERE portfolio_sk = 1
ORDER BY position_date;

-- ── 2B: Materialized view (fast path) ─────────────────────────────────────
SELECT
    position_date,
    aum,
    aum_7day_ma,
    aum_30day_ma,
    aum_year_ago,
    aum_rank_on_date,
    active_entity_count
FROM mart.mv_portfolio_kpi_daily
WHERE portfolio_sk = 1
ORDER BY position_date;

-- ============================================================================
-- DEMO 3: Custodian reconciliation feed (1 month of position data)
-- ============================================================================
-- "Pull all positions with State Street entity IDs and Bloomberg security
--  IDs for January 2024." This is a regulatory-reporting-style query.
--
-- The non-equi crosswalk joins are what make the View slow.

-- ── 3A: Plain view (slow path) ────────────────────────────────────────────
SELECT
    position_date,
    portfolio_name,
    entity_name,
    security_name,
    state_street_entity_id,
    bloomberg_security_id,
    market_value
FROM mart.vw_position_with_external_keys
WHERE position_date BETWEEN DATE'2024-01-01' AND DATE'2024-01-31'
ORDER BY position_date, portfolio_name
LIMIT 1000;

-- ── 3B: Materialized view (fast path) ─────────────────────────────────────
SELECT
    position_date,
    portfolio_name,
    entity_name,
    security_name,
    state_street_entity_id,
    bloomberg_security_id,
    market_value
FROM mart.mv_position_with_external_keys
WHERE position_date BETWEEN DATE'2024-01-01' AND DATE'2024-01-31'
ORDER BY position_date, portfolio_name
LIMIT 1000;

-- ============================================================================
-- DEMO 4: Full-window aggregate over external-key-resolved positions
-- ============================================================================
-- "Total market value by country and source system, for the entire
--  20-year history." This forces a full scan with no date predicate.
-- Tests how each path handles the worst-case full-table operation.

-- ── 4A: Plain view (very slow path) ───────────────────────────────────────
SELECT
    country_code,
    COUNT(DISTINCT state_street_entity_id) AS distinct_ss_entities,
    COUNT(DISTINCT bloomberg_security_id)  AS distinct_bbg_securities,
    SUM(market_value)                      AS total_market_value,
    COUNT(*)                                AS row_count
FROM mart.vw_position_with_external_keys
GROUP BY country_code
ORDER BY total_market_value DESC;

-- ── 4B: Materialized view (much faster) ───────────────────────────────────
SELECT
    country_code,
    COUNT(DISTINCT state_street_entity_id) AS distinct_ss_entities,
    COUNT(DISTINCT bloomberg_security_id)  AS distinct_bbg_securities,
    SUM(market_value)                      AS total_market_value,
    COUNT(*)                                AS row_count
FROM mart.mv_position_with_external_keys
GROUP BY country_code
ORDER BY total_market_value DESC;

-- ============================================================================
-- DEMO 5: Refresh planning inspection
-- ============================================================================
-- Confirms what enzyme picked. For both of these MVs we expect
-- MAINTENANCE_TYPE_COMPLETE_RECOMPUTE — they're not incrementalizable
-- because of the window functions and non-equi joins.
--
-- This is the trade-off that's worth showing explicitly: these MVs give
-- huge READ speedups but every refresh costs a full recompute. Production
-- usage attaches a SCHEDULE so refreshes happen off-peak.

WITH parsed AS (
    SELECT
        timestamp,
        from_json(
            details:planning_information,
            'struct<
                technique_information: array<struct<
                    maintenance_type: string,
                    is_chosen: boolean,
                    is_applicable: boolean,
                    cost: double
                >>
            >'
        ) AS pi
    FROM event_log(TABLE(mart.mv_portfolio_kpi_daily))
    WHERE event_type = 'planning_information'
)
SELECT
    'mv_portfolio_kpi_daily' AS mv_name,
    timestamp,
    chosen.maintenance_type AS chosen_technique,
    chosen.cost             AS estimated_cost
FROM parsed
LATERAL VIEW explode(pi.technique_information) t AS chosen
WHERE chosen.is_chosen = TRUE
ORDER BY timestamp DESC
LIMIT 3;

WITH parsed AS (
    SELECT
        timestamp,
        from_json(
            details:planning_information,
            'struct<
                technique_information: array<struct<
                    maintenance_type: string,
                    is_chosen: boolean,
                    is_applicable: boolean,
                    cost: double
                >>
            >'
        ) AS pi
    FROM event_log(TABLE(mart.mv_position_with_external_keys))
    WHERE event_type = 'planning_information'
)
SELECT
    'mv_position_with_external_keys' AS mv_name,
    timestamp,
    chosen.maintenance_type AS chosen_technique,
    chosen.cost             AS estimated_cost
FROM parsed
LATERAL VIEW explode(pi.technique_information) t AS chosen
WHERE chosen.is_chosen = TRUE
ORDER BY timestamp DESC
LIMIT 3;

-- ============================================================================
-- WHAT THIS DEMO SHOWS
-- ============================================================================
-- Comparing 06/07/08 (simple) to 09/10/11 (complex):
--
-- |                          | Simple MV (08)         | Complex MV (11)         |
-- |--------------------------|------------------------|-------------------------|
-- | Read speedup vs view     | 2-5×                   | 10-50×                  |
-- | Refresh technique        | ROW_BASED              | COMPLETE_RECOMPUTE      |
-- | Refresh latency          | Sub-second per change  | Minutes (full rebuild)  |
-- | Storage cost             | Small                  | Same as view rowcount   |
-- | Best refresh schedule    | Continuous / on-write  | Off-peak / daily        |
--
-- The decision tree:
--
-- Q: Does my consumer need the data fresh-to-the-second?
--    Yes -> Either use the live View, or stick to ROW_BASED-incrementable
--           MV definitions (simple aggregations, equi-joins only).
--    No  -> Use a complex MV with SCHEDULE EVERY 1 HOUR / daily refresh.
--           Reads stay fast; refresh runs off-peak.
--
-- Q: Does my query include window functions, non-equi joins, OR DISTINCT
--    aggregates?
--    Yes -> The MV will recompute fully on refresh. Plan accordingly.
--    No  -> Enzyme can probably do incremental refresh. Verify with the
--           planning_information event log.
