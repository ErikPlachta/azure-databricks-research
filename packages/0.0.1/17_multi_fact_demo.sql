-- ============================================================================
-- BRIDGE FRAMEWORK — Multi-Fact Performance Demo
--
-- Run after 16_transaction_views_and_mv.sql.
--
-- =============================================================================
-- WHY THIS MATTERS
-- =============================================================================
-- Most enterprise analytics queries don't sit on a single fact. They
-- correlate trade activity (fact.transaction) with the resulting position
-- snapshots (fact.position) — "what trades drove today's AUM change?"
-- "what was our turnover ratio?" "which portfolios were rebalancing
-- aggressively?"
--
-- A multi-fact join through views requires:
--   - Each view independently computes its own aggregations + windows
--     over its base fact (5M position rows, ~280K transaction rows).
--   - The two view results are then joined on (portfolio_name,
--     transaction_date = position_date) — string + date.
--   - Filters on computed columns can't push to either base fact.
--
-- This is the worst case for a live-view architecture and the strongest
-- case for materialization.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- DEMO 1A: Slow path — daily activity with AUM context, full window
-- ============================================================================
-- For every (portfolio, date) where a transaction occurred, return:
--   - the day's transaction activity (volume, turnover, count, mix)
--   - the portfolio's AUM and concentration metrics that day
--   - a turnover ratio (turnover / AUM)
--
-- No filters. No LIMIT. Full 20-year window. Returns one row per
-- (portfolio, transaction_date) ≈ 100 portfolios × ~7000 days with
-- transactions ≈ 700K rows.

SELECT
    tb.portfolio_name,
    tb.portfolio_type,
    tb.transaction_date,
    -- Transaction-side metrics
    tb.transaction_count,
    tb.distinct_securities_traded,
    tb.turnover_gross,
    tb.net_gross_flow,
    tb.total_fees,
    tb.buy_count,
    tb.sell_count,
    tb.turnover_rank_on_date,
    -- Position-side metrics (joined by string + date)
    pb.aum,
    pb.aum_rank_on_date,
    pb.top_3_concentration_pct,
    pb.entity_count,
    -- Cross-fact derived metric: turnover as % of AUM
    tb.turnover_gross / NULLIF(pb.aum, 0) AS turnover_ratio
FROM mart.vw_transaction_book tb
JOIN mart.vw_portfolio_book pb
    ON tb.portfolio_name  = pb.portfolio_name
   AND tb.transaction_date = pb.position_date
ORDER BY tb.transaction_date DESC, tb.portfolio_name;

-- ============================================================================
-- DEMO 1B: Fast path — same query, MV-backed
-- ============================================================================
SELECT
    tb.portfolio_name,
    tb.portfolio_type,
    tb.transaction_date,
    tb.transaction_count,
    tb.distinct_securities_traded,
    tb.turnover_gross,
    tb.net_gross_flow,
    tb.total_fees,
    tb.buy_count,
    tb.sell_count,
    tb.turnover_rank_on_date,
    pb.aum,
    pb.aum_rank_on_date,
    pb.top_3_concentration_pct,
    pb.entity_count,
    tb.turnover_gross / NULLIF(pb.aum, 0) AS turnover_ratio
FROM mart.mv_transaction_book tb
JOIN mart.mv_portfolio_book pb
    ON tb.portfolio_name  = pb.portfolio_name
   AND tb.transaction_date = pb.position_date
ORDER BY tb.transaction_date DESC, tb.portfolio_name;

-- ============================================================================
-- DEMO 2A: Slow path — three-way fact join with security-level detail
-- ============================================================================
-- For every transaction, return:
--   - the full transaction detail (security, counterparty, side, etc.)
--   - the security's position state on the same day (market_value,
--     pct_of_portfolio_aum)
--   - the portfolio's daily aggregate context (turnover, AUM)
--
-- Three-way join across vw_transaction_detail, vw_security_book,
-- vw_transaction_book. No filters. No LIMIT. ≈ 280K transaction rows
-- as the driving cardinality, joined to security and portfolio context.

SELECT
    td.transaction_date,
    td.portfolio_name,
    td.security_name,
    td.entity_name,
    td.country_code,
    td.transaction_type,
    td.quantity                    AS txn_quantity,
    td.gross_amount                AS txn_gross,
    td.counterparty,
    td.pct_of_daily_turnover,
    -- Security position state on this date
    sb.market_value                AS position_market_value,
    sb.pct_of_portfolio_aum,
    -- Portfolio-day aggregate context
    tb.turnover_gross              AS portfolio_day_turnover,
    tb.transaction_count           AS portfolio_day_txn_count,
    tb.turnover_rank_on_date,
    -- Cross-grain: txn as % of portfolio's day turnover
    ABS(td.gross_amount) / NULLIF(tb.turnover_gross, 0) AS txn_share_of_portfolio_day
FROM mart.vw_transaction_detail td
JOIN mart.vw_security_book sb
    ON td.portfolio_name  = sb.portfolio_name
   AND td.security_name   = sb.security_name
   AND td.transaction_date = sb.position_date
JOIN mart.vw_transaction_book tb
    ON td.portfolio_name  = tb.portfolio_name
   AND td.transaction_date = tb.transaction_date
ORDER BY td.transaction_date DESC, td.portfolio_name, ABS(td.gross_amount) DESC;

-- ============================================================================
-- DEMO 2B: Fast path — same query, MV-backed
-- ============================================================================
SELECT
    td.transaction_date,
    td.portfolio_name,
    td.security_name,
    td.entity_name,
    td.country_code,
    td.transaction_type,
    td.quantity                    AS txn_quantity,
    td.gross_amount                AS txn_gross,
    td.counterparty,
    td.pct_of_daily_turnover,
    sb.market_value                AS position_market_value,
    sb.pct_of_portfolio_aum,
    tb.turnover_gross              AS portfolio_day_turnover,
    tb.transaction_count           AS portfolio_day_txn_count,
    tb.turnover_rank_on_date,
    ABS(td.gross_amount) / NULLIF(tb.turnover_gross, 0) AS txn_share_of_portfolio_day
FROM mart.mv_transaction_detail td
JOIN mart.mv_security_book sb
    ON td.portfolio_name  = sb.portfolio_name
   AND td.security_name   = sb.security_name
   AND td.transaction_date = sb.position_date
JOIN mart.mv_transaction_book tb
    ON td.portfolio_name  = tb.portfolio_name
   AND td.transaction_date = tb.transaction_date
ORDER BY td.transaction_date DESC, td.portfolio_name, ABS(td.gross_amount) DESC;

-- ============================================================================
-- WHAT THE TWO DEMOS DEMONSTRATE
-- ============================================================================
-- Demo 1: Two-fact aggregation join
--   - Each side computes its own daily aggregations + window functions
--     before the join.
--   - View path: full evaluation of both views over all base data, then
--     hash-join on (portfolio_name, date) string-pair, then ORDER BY
--     shuffle. Genuinely intractable as a live query.
--   - MV path: two compact pre-computed Delta tables joined directly.
--
-- Demo 2: Three-fact denormalized join
--   - vw_transaction_detail expands to ~280K rows BEFORE joining.
--   - vw_security_book is ~5M rows.
--   - vw_transaction_book is ~700K rows.
--   - Three-way join across all three on string keys with no predicate
--     pushdown. The view path here is the worst case in the entire suite.
--
-- These are the queries that make the materialization decision easy.
