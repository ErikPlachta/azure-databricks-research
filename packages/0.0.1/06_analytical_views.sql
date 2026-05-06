-- ============================================================================
-- BRIDGE FRAMEWORK — Analytical Views (mart schema)
--
-- Run after 04_seed_data.sql.
--
-- =============================================================================
-- WHAT THIS FILE DOES
-- =============================================================================
-- Defines two consumer-facing views in a new `mart` schema. These views are
-- the "live computation" path — every SELECT against them re-executes the
-- full query against fact.position and the dim tables.
--
-- The point of having them as plain views (vs materialized) is to establish
-- a baseline. File 07 then defines materialized-view counterparts with
-- IDENTICAL SELECT bodies, so the comparison in file 08 is apples-to-apples.
--
-- In your enterprise environment ("only views are exposed to consumers"),
-- this layer is what apps actually query. Some of these views may be
-- backed by an MV (fast); others may compute live (slow). The view
-- contract is the same; the implementation choice is internal.
--
-- =============================================================================
-- ARCHITECTURAL NOTE — WHY mart EXISTS
-- =============================================================================
-- Existing schemas:
--   bridge — framework infrastructure (crosswalks, key domains, source registry)
--   dim    — SCD2-tracked golden records (entities, portfolios, etc.)
--   fact   — transactional facts (positions)
--
-- New:
--   mart   — analytical objects (views, MVs) downstream of dim/fact.
--
-- This separation matters because mart is the layer consumers query. In a
-- production deployment, mart objects can be re-defined, re-materialized,
-- or restructured without touching dim/fact. dim/fact are owned by the
-- pipeline; mart is owned by analytics.
-- ============================================================================

USE CATALOG workspace;

CREATE SCHEMA IF NOT EXISTS mart
COMMENT 'Analytical views and materialized views over dim/fact';

-- ============================================================================
-- VIEW 1: vw_aum_daily_by_portfolio
--
-- Daily Assets Under Management per portfolio. The grain is one row per
-- (position_date, portfolio_sk).
--
-- WHAT IT'S FOR
--   CFO dashboards, trend analysis, board-deck rollups. The "where is the
--   firm's money on each day, broken out by fund."
--
-- PERFORMANCE PROFILE (live view)
--   Input: ~5M rows from fact.position
--   Output: ~730K rows (7300 dates × ~100 portfolios)
--   Operation: aggregate-and-group. Spark scans the entire fact, hash-aggs
--   on (date, portfolio_sk), then broadcast-joins to dim.portfolio for the
--   name. On Free Edition serverless this costs ~5–15 seconds per query.
--
-- WHY IT'S A GREAT MV CANDIDATE
--   * Pure invertible aggregation (SUM, COUNT) — every aggregation operator
--     is invertible, so enzyme can do incremental refresh on every fact
--     insert/update/delete.
--   * Output cardinality is much smaller than input (~7×) — the MV stores
--     materially less data than the fact.
--   * Read shape is consumer-friendly: most dashboards filter by date range
--     and group by portfolio.
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_aum_daily_by_portfolio AS
SELECT
    p.position_date,
    pf.portfolio_sk,
    pf.portfolio_name,
    pf.portfolio_type,
    SUM(p.market_value)         AS aum,
    SUM(p.book_value)           AS book_value,
    SUM(p.unrealized_gain_loss) AS unrealized_pnl,
    COUNT(*)                    AS position_count
FROM workspace.fact.position p
JOIN workspace.dim.portfolio pf
     ON p.portfolio_sk = pf.portfolio_sk
GROUP BY
    p.position_date,
    pf.portfolio_sk,
    pf.portfolio_name,
    pf.portfolio_type;

-- ============================================================================
-- VIEW 2: vw_position_enriched
--
-- Denormalized position records — fact.position joined to dim names. The
-- grain is one row per fact.position row (no aggregation).
--
-- WHAT IT'S FOR
--   Position-level reporting, holdings reports, audit trails, anywhere
--   consumers want "the position with names attached" without writing the
--   four-way join themselves.
--
-- PERFORMANCE PROFILE (live view)
--   Input: ~5M rows from fact.position
--   Output: ~5M rows (no aggregation — same row count)
--   Operation: four broadcast joins (portfolio, entity, asset via security,
--   security). All dims are small (≤700 rows each) and broadcast cleanly.
--   On Free Edition serverless this costs ~10–30 seconds per full scan,
--   though most queries with WHERE clauses run faster.
--
-- WHY IT'S A REASONABLE MV CANDIDATE (with caveats)
--   * Joins-only (no aggregation) — enzyme handles this with row-based
--     incremental. Every new position row triggers append-only MV update.
--   * BUT: same row count means the MV is no smaller than the fact (in
--     fact slightly larger due to repeated dim attribute storage). The
--     speedup comes from avoiding the join, not reducing the data.
--   * Trade-off: storage cost is real. ~500MB+ for a 5M-row denorm.
--
-- WHEN YOU'D MATERIALIZE THIS
--   When apps need consistent sub-second response times for queries that
--   would otherwise take 5–10 seconds via the view. Storage cost is
--   acceptable in exchange for predictable consumer-facing latency.
--
-- WHEN YOU WOULDN'T
--   When consumers are already filtering aggressively (e.g., always by a
--   single portfolio) and the live view is fast enough with predicate
--   pushdown. Don't materialize for the sake of it.
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_position_enriched AS
SELECT
    p.position_id,
    p.position_date,
    -- Portfolio
    p.portfolio_sk,
    pf.portfolio_name,
    pf.portfolio_type,
    -- Entity
    p.entity_sk,
    e.entity_name,
    e.entity_type,
    e.jurisdiction,
    -- Asset (joined via security)
    a.asset_sk,
    a.asset_name,
    a.asset_type,
    a.city          AS asset_city,
    a.country_code  AS asset_country,
    -- Security
    p.security_sk,
    s.security_name,
    s.security_type,
    s.cusip,
    -- Position metrics
    p.quantity,
    p.market_value,
    p.book_value,
    p.cost_basis,
    p.unrealized_gain_loss,
    p.unit_price,
    p.local_currency_code,
    p.reporting_currency_code,
    p.fx_rate,
    p.record_source
FROM workspace.fact.position p
JOIN workspace.dim.portfolio pf ON p.portfolio_sk = pf.portfolio_sk
JOIN workspace.dim.entity    e  ON p.entity_sk    = e.entity_sk
JOIN workspace.dim.security  s  ON p.security_sk  = s.security_sk
JOIN workspace.dim.asset     a  ON s.asset_sk     = a.asset_sk;

SELECT 'Analytical views created in mart schema.' AS status;
