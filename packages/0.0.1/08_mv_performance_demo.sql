-- ============================================================================
-- BRIDGE FRAMEWORK — MV Performance Demo
--
-- Run after 07_materialized_views.sql. Each section below runs the SAME
-- query against the plain view (slow) and then against the materialized
-- view (fast). Run each cell individually in the SQL editor and watch the
-- per-cell duration in the result panel.
--
-- =============================================================================
-- WHAT TO LOOK AT
-- =============================================================================
-- The Databricks SQL editor shows query duration in the result tab footer
-- ("X seconds"). Compare that number between the View cell and the MV cell.
--
-- Expected results on Free Edition serverless against ~5M position rows:
--
--   DEMO 1  AUM aggregation
--     vw_aum_daily_by_portfolio    ~5–15s
--     mv_aum_daily_by_portfolio    <1s
--     -> 10–20× speedup. Strong MV win on pure aggregation.
--
--   DEMO 2  Denormalized position
--     vw_position_enriched         ~10–30s
--     mv_position_enriched         ~3–8s
--     -> 3–5× speedup. Smaller multiplier because the MV still has to
--        return ~5M rows of data; you save the join, not the data volume.
--
--   DEMO 3  Counter-example: point lookup
--     fact.position direct          <1s
--     mv_position_enriched          <1s
--     -> Comparable. Liquid Clustering on (security_sk, position_date)
--        already makes selective lookups fast. MV is no help here.
--
--   DEMO 4  Refresh planning inspection — diagnostic, no perf comparison.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- DEMO 1: AUM aggregation
-- ============================================================================
-- Question: "Show me daily AUM per portfolio for 2024, top 100 by AUM."
-- This is the canonical CFO-dashboard query. Aggregation against 5M rows.

-- ── 1A: Plain view (slow path) ────────────────────────────────────────────
SELECT
    position_date,
    portfolio_name,
    portfolio_type,
    aum,
    position_count
FROM mart.vw_aum_daily_by_portfolio
WHERE position_date BETWEEN DATE'2024-01-01' AND DATE'2024-12-31'
ORDER BY position_date DESC, aum DESC
LIMIT 100;

-- ── 1B: Materialized view (fast path) ─────────────────────────────────────
-- Identical query body, only the source name changed.
SELECT
    position_date,
    portfolio_name,
    portfolio_type,
    aum,
    position_count
FROM mart.mv_aum_daily_by_portfolio
WHERE position_date BETWEEN DATE'2024-01-01' AND DATE'2024-12-31'
ORDER BY position_date DESC, aum DESC
LIMIT 100;

-- ============================================================================
-- DEMO 2: Denormalized position lookup over a date range
-- ============================================================================
-- Question: "Pull all positions for portfolios named like 'CORE Fund 2020%'
-- in Q1 2024, with full asset/entity/security context."
-- This exercises the four-way join.

-- ── 2A: Plain view (slow path) ────────────────────────────────────────────
SELECT
    position_date,
    portfolio_name,
    entity_name,
    asset_name,
    asset_city,
    security_name,
    security_type,
    market_value,
    unrealized_gain_loss
FROM mart.vw_position_enriched
WHERE portfolio_name LIKE 'CORE Fund 2020%'
  AND position_date BETWEEN DATE'2024-01-01' AND DATE'2024-03-31'
ORDER BY position_date, portfolio_name, asset_name
LIMIT 1000;

-- ── 2B: Materialized view (fast path) ─────────────────────────────────────
SELECT
    position_date,
    portfolio_name,
    entity_name,
    asset_name,
    asset_city,
    security_name,
    security_type,
    market_value,
    unrealized_gain_loss
FROM mart.mv_position_enriched
WHERE portfolio_name LIKE 'CORE Fund 2020%'
  AND position_date BETWEEN DATE'2024-01-01' AND DATE'2024-03-31'
ORDER BY position_date, portfolio_name, asset_name
LIMIT 1000;

-- ============================================================================
-- DEMO 3: Counter-example — point lookup
-- ============================================================================
-- A specific (security, date) lookup. The base fact table has Liquid
-- Clustering on (security_sk, position_date) so this is already fast.
-- Materialization buys nothing here — and arguably costs you, because the
-- MV is also clustered but is a separate Delta table to maintain.
--
-- Lesson: don't materialize for query patterns that are already fast.
-- MVs help with full-scan aggregation and join elimination, not with
-- selective predicate-pushdown lookups.

-- ── 3A: Direct fact table query ───────────────────────────────────────────
WITH sample_security AS (
    SELECT security_sk
    FROM dim.security
    WHERE is_current = TRUE
    ORDER BY security_sk
    LIMIT 1
)
SELECT
    p.position_date,
    p.security_sk,
    p.market_value,
    p.quantity
FROM fact.position p
JOIN sample_security ss ON p.security_sk = ss.security_sk
WHERE p.position_date BETWEEN DATE'2024-06-01' AND DATE'2024-06-30'
ORDER BY p.position_date;

-- ── 3B: Same lookup against the MV (similar speed) ────────────────────────
WITH sample_security AS (
    SELECT security_sk
    FROM dim.security
    WHERE is_current = TRUE
    ORDER BY security_sk
    LIMIT 1
)
SELECT
    e.position_date,
    e.security_sk,
    e.market_value,
    e.quantity
FROM mart.mv_position_enriched e
JOIN sample_security ss ON e.security_sk = ss.security_sk
WHERE e.position_date BETWEEN DATE'2024-06-01' AND DATE'2024-06-30'
ORDER BY e.position_date;

-- ============================================================================
-- DEMO 4: Refresh planning — what technique did enzyme pick?
-- ============================================================================
-- The event_log() table function returns columns:
--   timestamp, event_type, details (JSON string), origin, maturity_level
--
-- Refresh details aren't top-level columns. They live inside the `details`
-- JSON, parsed via the `:` path operator. The interesting paths are:
--   event_type = 'update_progress'      -> high-level refresh status
--   event_type = 'planning_information' -> per-flow technique selection
--                                          (this is where ROW_BASED vs
--                                           SNAPSHOT vs PARTITION_OVERWRITE
--                                           is recorded)
--
-- For a quick GUI alternative, Catalog Explorer's "See refresh details"
-- button on each MV shows the chosen refresh type directly without SQL.

-- ── 4A: Recent refresh runs (simple) ──────────────────────────────────────
-- Just confirm refreshes are happening and see their status.
SELECT
    timestamp,
    event_type,
    maturity_level,
    -- Pull the human-readable status out of the JSON:
    details:update_progress:state::STRING AS update_state
FROM event_log(TABLE(mart.mv_aum_daily_by_portfolio))
WHERE event_type = 'update_progress'
ORDER BY timestamp DESC
LIMIT 10;

-- ── 4B: Chosen refresh technique (the enzyme diagnostic) ──────────────────
-- planning_information events list every technique enzyme considered, with
-- is_chosen=true on the one it picked. We parse the JSON, explode the
-- techniques array, and filter to the chosen one.
--
-- Possible maintenance_type values:
--   MAINTENANCE_TYPE_ROW_BASED                 -> incremental, per-row
--   MAINTENANCE_TYPE_PARTITION_OVERWRITE       -> incremental, partition-level
--   MAINTENANCE_TYPE_COMPLETE_RECOMPUTE        -> full recompute (the slow one)
--   MAINTENANCE_TYPE_NO_OP                     -> no work needed
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
    FROM event_log(TABLE(mart.mv_aum_daily_by_portfolio))
    WHERE event_type = 'planning_information'
)
SELECT
    timestamp,
    chosen.maintenance_type AS chosen_technique,
    chosen.cost             AS estimated_cost
FROM parsed
LATERAL VIEW explode(pi.technique_information) t AS chosen
WHERE chosen.is_chosen = TRUE
ORDER BY timestamp DESC
LIMIT 5;

-- Same for the denorm MV
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
    FROM event_log(TABLE(mart.mv_position_enriched))
    WHERE event_type = 'planning_information'
)
SELECT
    timestamp,
    chosen.maintenance_type AS chosen_technique,
    chosen.cost             AS estimated_cost
FROM parsed
LATERAL VIEW explode(pi.technique_information) t AS chosen
WHERE chosen.is_chosen = TRUE
ORDER BY timestamp DESC
LIMIT 5;

-- To force an incremental refresh test:
--   1. Insert one row into fact.position (against any current SKs)
--   2. REFRESH MATERIALIZED VIEW mart.mv_aum_daily_by_portfolio;
--   3. Re-run query 4B above — you should see ROW_BASED for the new event.
--
-- Example mutation (commented out — run only if you want to test):
-- INSERT INTO fact.position (position_date, portfolio_sk, entity_sk, security_sk,
--     quantity, market_value, book_value, cost_basis, unrealized_gain_loss,
--     unit_price, price_source, local_currency_code, reporting_currency_code,
--     fx_rate, record_source)
-- SELECT
--     current_date(),
--     (SELECT portfolio_sk FROM dim.portfolio WHERE is_current = TRUE LIMIT 1),
--     (SELECT entity_sk    FROM dim.entity    WHERE is_current = TRUE LIMIT 1),
--     (SELECT security_sk  FROM dim.security  WHERE is_current = TRUE LIMIT 1),
--     1000, 1100000.00, 1000000.00, 950000.00, 100000.00, 1100.00,
--     'BLOOMBERG', 'USD', 'USD', 1.0, 'STATE_STREET';
--
-- REFRESH MATERIALIZED VIEW mart.mv_aum_daily_by_portfolio;
