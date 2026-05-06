-- ============================================================================
-- BRIDGE FRAMEWORK — Materialized Views (mart schema)
--
-- Run after 06_analytical_views.sql.
--
-- =============================================================================
-- WHAT THIS FILE DOES
-- =============================================================================
-- Defines materialized-view counterparts to the plain views in file 06.
-- The SELECT bodies are IDENTICAL between vw_X and mv_X — the only
-- difference is the MATERIALIZED keyword. This makes the perf comparison
-- in file 08 a fair apples-to-apples test.
--
-- =============================================================================
-- WHAT HAPPENS WHEN YOU RUN THIS FILE
-- =============================================================================
-- CREATE MATERIALIZED VIEW triggers an INITIAL FULL MATERIALIZATION. For
-- the default 20-year seed (~5M rows), expect:
--
--   mv_aum_daily_by_portfolio  ~30–90s (aggregation: 5M rows → ~730K rows)
--   mv_position_enriched       ~60–180s (denorm: 5M rows × 4 dim joins)
--
-- These are one-time costs. Subsequent reads are sub-second.
--
-- Subsequent REFRESH operations are incremental when enzyme can prove the
-- query is amenable (ROW_BASED). For the queries below, both should refresh
-- incrementally for fact.position appends — see file 08 demo 4 for how to
-- inspect the technique chosen.
--
-- =============================================================================
-- REFRESH STRATEGY
-- =============================================================================
-- We DO NOT specify SCHEDULE — refresh is manual via:
--     REFRESH MATERIALIZED VIEW mart.mv_aum_daily_by_portfolio;
--
-- This keeps the demo predictable; production usage would typically attach
-- SCHEDULE EVERY 1 HOUR or similar:
--     CREATE OR REPLACE MATERIALIZED VIEW mart.mv_aum_daily_by_portfolio
--     SCHEDULE EVERY 1 HOUR
--     AS SELECT ...;
--
-- =============================================================================
-- FREE EDITION NOTES
-- =============================================================================
-- Free Edition serverless supports MVs. The catalog explorer shows them as
-- "Materialized View" type, with refresh history visible in the UI. The
-- event_log() table function exposes refresh planning details (the
-- 'technique' field shows ROW_BASED / SNAPSHOT / PARTITION_OVERWRITE).
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- MV 1: mv_aum_daily_by_portfolio
--
-- IDENTICAL SELECT body to mart.vw_aum_daily_by_portfolio. Same grain,
-- same columns, same semantics — just pre-computed.
--
-- ENZYME EXPECTATIONS
--   On fact.position INSERT: ROW_BASED. Each new position row's
--   contribution to its (date, portfolio_sk) bucket is added to the
--   pre-aggregated values via the inverse of SUM (which is just SUM).
--
--   On fact.position DELETE: ROW_BASED. Subtract the deleted row's
--   contribution from the aggregate.
--
--   On fact.position UPDATE: ROW_BASED. Subtract old contribution, add
--   new contribution.
--
--   On dim.portfolio INSERT/UPDATE (e.g., Phase 6 SCD2 events on
--   portfolios — currently no-op since we don't restructure portfolios):
--   ROW_BASED with broadcast — re-evaluates the affected portfolio_sk
--   group only.
--
--   On CREATE OR REPLACE MATERIALIZED VIEW (re-running this file):
--   FULL_RECOMPUTE — definition changed, no incremental path.
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_aum_daily_by_portfolio
COMMENT 'Pre-computed daily AUM per portfolio. Refresh manually or attach SCHEDULE.'
AS
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
-- MV 2: mv_position_enriched
--
-- IDENTICAL SELECT body to mart.vw_position_enriched. Materializes the
-- four-way denormalization so consumers don't pay the join cost on every
-- query.
--
-- STORAGE FOOTPRINT
--   ~5M rows × ~25 columns ≈ a few hundred MB. Stored as Delta. This is
--   the "trade storage for latency" pattern: you accept the duplication
--   in exchange for predictable read times.
--
-- ENZYME EXPECTATIONS
--   On fact.position INSERT: ROW_BASED. Each new row joins to its (small,
--   broadcasted) dim rows and is appended.
--
--   On dim.portfolio / dim.entity / dim.asset / dim.security UPDATE
--   (e.g., Phase 6 entity restructurings): ROW_BASED for the affected SKs
--   only. The MV's affected rows are re-evaluated; everything else is
--   untouched.
--
--   On dim DELETE (e.g., Phase 1 of a re-seed): the optimizer typically
--   picks SNAPSHOT (full recompute) because cascading deletion through
--   the join tree isn't ROW_BASED-tractable.
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_position_enriched
COMMENT 'Pre-joined position records with all dim attributes attached.'
AS
SELECT
    p.position_id,
    p.position_date,
    p.portfolio_sk,
    pf.portfolio_name,
    pf.portfolio_type,
    p.entity_sk,
    e.entity_name,
    e.entity_type,
    e.jurisdiction,
    a.asset_sk,
    a.asset_name,
    a.asset_type,
    a.city          AS asset_city,
    a.country_code  AS asset_country,
    p.security_sk,
    s.security_name,
    s.security_type,
    s.cusip,
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

SELECT 'Materialized views created. Initial materialization is complete.' AS status;
