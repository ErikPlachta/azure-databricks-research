-- ============================================================================
-- 06_demos/99_adhoc_playground.sql
-- Scratch space. Real-analyst-style queries against the medallion stack —
-- the kind of work the v/mv/t machinery is built to support.
--
-- Each section is self-contained. Mix and match; copy queries into your
-- own SQL editor scratch tab.
--
-- Pedagogical goal: feel out the data shape end-to-end, not lecture about
-- features. Use whichever artifact (v / mv / t) suits the question:
--   * Live exploration → v (always fresh).
--   * Reporting / dashboarding → mv or t (fast + stable).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Headline: top 10 PD positions by market value, cross-team ──────────
SELECT team_code, security_sk, position_date,
       market_value_usd, concentration_pct, portfolio_rank
FROM gold_pd_consolidated.mvpd_position_book
ORDER BY market_value_usd DESC
LIMIT 10;

-- ── 2. Per-team current AUM ────────────────────────────────────────────────
SELECT team_code,
       count(DISTINCT enterprise_key)         AS unique_positions,
       sum(market_value_usd)                  AS total_aum_usd,
       avg(concentration_pct)                 AS avg_concentration_pct,
       max(portfolio_rank)                    AS deepest_rank
FROM gold_pd_consolidated.mvpd_position_book
WHERE position_date = (SELECT max(position_date) FROM gold_pd_consolidated.mvpd_position_book)
GROUP BY team_code
ORDER BY total_aum_usd DESC;

-- ── 3. Contract concentration: largest outstanding principals across PD teams
SELECT team_code, contract_sk, summary_date,
       outstanding_principal_usd, accrued_interest_usd, performance_status,
       has_active_breach
FROM gold_pd_consolidated.mvpd_contract_book
WHERE summary_date = (SELECT max(summary_date) FROM gold_pd_consolidated.mvpd_contract_book)
ORDER BY outstanding_principal_usd DESC
LIMIT 20;

-- ── 4. Transaction volume by team and quarter ──────────────────────────────
SELECT team_code,
       date_trunc('QUARTER', transaction_date) AS quarter,
       count(*)                                AS txn_count,
       sum(gross_amount_usd)                   AS gross_volume_usd,
       sum(fees_usd)                           AS total_fees_usd
FROM gold_pd_consolidated.mvpd_transaction_book
GROUP BY 1, 2
ORDER BY 1, 2 DESC;

-- ── 5. SCD2 dim: contract amendments over time ─────────────────────────────
-- How often do contract terms change? (Each amendment creates a new SCD2 row.)
SELECT count(*)               AS total_contract_versions,
       count(DISTINCT enterprise_key) AS unique_contracts,
       count(*) - count(DISTINCT enterprise_key) AS amendments
FROM investments.t_vcontract_dim;

-- ── 6. Provenance: which sources contributed to bronze.vsecurity? ─────────
SELECT _source_pref,
       count(*) AS rows_won_by_source,
       count(*) / sum(count(*)) OVER () AS pct_of_total
FROM bronze.vsecurity
GROUP BY _source_pref
ORDER BY rows_won_by_source DESC;

-- ── 7. Slow-path / fast-path pairing: same answer, different artifacts ────
-- Run both — same answer, different latency.
SELECT 'slow_path_v' AS source, count(*) AS n FROM gold_pd_consolidated.vpd_position_book;
SELECT 'fast_path_mv' AS source, count(*) AS n FROM gold_pd_consolidated.mvpd_position_book;
SELECT 'fastest_path_t' AS source, count(*) AS n FROM gold_pd_consolidated.t_vpd_position_book;

-- ── 8. FX rates currently in effect ────────────────────────────────────────
SELECT from_currency, to_currency, rate_date, fx_rate
FROM investments.t_vfx_rate_dim
WHERE rate_date = (SELECT max(rate_date) FROM investments.t_vfx_rate_dim)
ORDER BY from_currency;
