-- ============================================================================
-- BRIDGE FRAMEWORK — Transaction-Grain Consumer Views (mart schema)
--
-- Run after 15_fact_transaction_setup.sql.
--
-- =============================================================================
-- DESIGN
-- =============================================================================
-- Same consumer-layer convention as 12/13: string identifiers only, no SKs,
-- computed columns the consumer naturally filters on.
--
-- vw_transaction_book / mv_transaction_book — daily portfolio transaction
-- activity at the (portfolio_name, transaction_date) grain. Aggregates
-- away security-level detail; consumers join to vw_security_book or
-- vw_transaction_detail when they need the breakdown.
--
-- vw_transaction_detail / mv_transaction_detail — full denormalized
-- transaction record with portfolio / entity / security / asset names
-- attached. Same grain as fact.transaction (one row per transaction).
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- VIEW: vw_transaction_book
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_transaction_book AS
SELECT
    pf.portfolio_name,
    pf.portfolio_type,
    t.transaction_date,
    -- Volume metrics (signed quantities → net flow naturally signed)
    SUM(t.gross_amount)                                                  AS net_gross_flow,
    SUM(ABS(t.gross_amount))                                             AS turnover_gross,
    SUM(t.net_amount)                                                    AS net_cash_flow,
    SUM(t.fees)                                                          AS total_fees,
    -- Activity metrics
    COUNT(*)                                                             AS transaction_count,
    COUNT(DISTINCT t.security_sk)                                        AS distinct_securities_traded,
    SUM(CASE WHEN t.transaction_type = 'BUY'         THEN 1 ELSE 0 END) AS buy_count,
    SUM(CASE WHEN t.transaction_type = 'SELL'        THEN 1 ELSE 0 END) AS sell_count,
    SUM(CASE WHEN t.transaction_type = 'ACQUISITION' THEN 1 ELSE 0 END) AS acquisition_count,
    SUM(CASE WHEN t.transaction_type = 'DISPOSAL'    THEN 1 ELSE 0 END) AS disposal_count,
    -- Ranks each (portfolio, day) by absolute turnover within the day
    DENSE_RANK() OVER (
        PARTITION BY t.transaction_date
        ORDER BY SUM(ABS(t.gross_amount)) DESC
    )                                                                    AS turnover_rank_on_date
FROM workspace.fact.transaction t
JOIN workspace.dim.portfolio pf ON t.portfolio_sk = pf.portfolio_sk
GROUP BY pf.portfolio_name, pf.portfolio_type, t.transaction_date;

-- ============================================================================
-- VIEW: vw_transaction_detail
-- ============================================================================
CREATE OR REPLACE VIEW mart.vw_transaction_detail AS
SELECT
    t.transaction_id,
    t.transaction_date,
    t.settlement_date,
    pf.portfolio_name,
    pf.portfolio_type,
    e.entity_name,
    a.asset_name,
    a.country_code,
    s.security_name,
    s.security_type,
    t.transaction_type,
    t.quantity,
    t.price,
    t.gross_amount,
    t.fees,
    t.net_amount,
    t.counterparty,
    t.record_source,
    -- Per-portfolio per-day share of turnover
    ABS(t.gross_amount) / NULLIF(
        SUM(ABS(t.gross_amount)) OVER (PARTITION BY pf.portfolio_name, t.transaction_date),
        0
    )                                                                    AS pct_of_daily_turnover
FROM workspace.fact.transaction t
JOIN workspace.dim.portfolio pf ON t.portfolio_sk = pf.portfolio_sk
JOIN workspace.dim.entity    e  ON t.entity_sk    = e.entity_sk
JOIN workspace.dim.security  s  ON t.security_sk  = s.security_sk
JOIN workspace.dim.asset     a  ON s.asset_sk     = a.asset_sk;

-- ============================================================================
-- MV: mv_transaction_book — IDENTICAL body to vw_transaction_book
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_transaction_book
COMMENT 'Daily portfolio transaction activity. Refresh = COMPLETE_RECOMPUTE (window function).'
AS
SELECT
    pf.portfolio_name,
    pf.portfolio_type,
    t.transaction_date,
    SUM(t.gross_amount)                                                  AS net_gross_flow,
    SUM(ABS(t.gross_amount))                                             AS turnover_gross,
    SUM(t.net_amount)                                                    AS net_cash_flow,
    SUM(t.fees)                                                          AS total_fees,
    COUNT(*)                                                             AS transaction_count,
    COUNT(DISTINCT t.security_sk)                                        AS distinct_securities_traded,
    SUM(CASE WHEN t.transaction_type = 'BUY'         THEN 1 ELSE 0 END) AS buy_count,
    SUM(CASE WHEN t.transaction_type = 'SELL'        THEN 1 ELSE 0 END) AS sell_count,
    SUM(CASE WHEN t.transaction_type = 'ACQUISITION' THEN 1 ELSE 0 END) AS acquisition_count,
    SUM(CASE WHEN t.transaction_type = 'DISPOSAL'    THEN 1 ELSE 0 END) AS disposal_count,
    DENSE_RANK() OVER (
        PARTITION BY t.transaction_date
        ORDER BY SUM(ABS(t.gross_amount)) DESC
    )                                                                    AS turnover_rank_on_date
FROM workspace.fact.transaction t
JOIN workspace.dim.portfolio pf ON t.portfolio_sk = pf.portfolio_sk
GROUP BY pf.portfolio_name, pf.portfolio_type, t.transaction_date;

-- ============================================================================
-- MV: mv_transaction_detail — IDENTICAL body to vw_transaction_detail
-- ============================================================================
CREATE OR REPLACE MATERIALIZED VIEW mart.mv_transaction_detail
COMMENT 'Denormalized transaction record. Refresh = COMPLETE_RECOMPUTE (window function).'
AS
SELECT
    t.transaction_id,
    t.transaction_date,
    t.settlement_date,
    pf.portfolio_name,
    pf.portfolio_type,
    e.entity_name,
    a.asset_name,
    a.country_code,
    s.security_name,
    s.security_type,
    t.transaction_type,
    t.quantity,
    t.price,
    t.gross_amount,
    t.fees,
    t.net_amount,
    t.counterparty,
    t.record_source,
    ABS(t.gross_amount) / NULLIF(
        SUM(ABS(t.gross_amount)) OVER (PARTITION BY pf.portfolio_name, t.transaction_date),
        0
    )                                                                    AS pct_of_daily_turnover
FROM workspace.fact.transaction t
JOIN workspace.dim.portfolio pf ON t.portfolio_sk = pf.portfolio_sk
JOIN workspace.dim.entity    e  ON t.entity_sk    = e.entity_sk
JOIN workspace.dim.security  s  ON t.security_sk  = s.security_sk
JOIN workspace.dim.asset     a  ON s.asset_sk     = a.asset_sk;

SELECT 'Transaction views and MVs created.' AS status;
