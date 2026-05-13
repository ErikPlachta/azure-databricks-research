-- ============================================================================
-- 04_gold/02_tables.sql
-- Gold tables: 5 PD-team schemas + gold_pd_consolidated.
--
-- 10 entities per team (matches user's enterprise `private_debt` view list):
-- 8 facts + 2 dim subsets. 5 teams × 10 = 50 team-table definitions, plus 3
-- consolidated cross-team facts = 53 gold tables.
--
-- Table shapes are uniform per entity-type across teams. Only the data
-- filtering differs (in views/MVs). Team-derived columns (concentration_pct,
-- portfolio_rank, vintage_year) appear on the position + portfolio analytics
-- tables where they're computable.
--
-- Liquid Clustering: facts on (<date_col>, portfolio_sk); dims on (enterprise_key).
-- All tables: row tracking + CDF + allowColumnDefaults.
-- Audit: silver_loaded_at + gold_loaded_at.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- Helper macro: TBLPROPERTIES is identical across all gold tables. Inlined
-- for clarity (Spark SQL doesn't support DDL macros).

-- ============================================================================
-- SECTION A — team_pd_direct_lending (10 tables)
-- ============================================================================

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vposition_analytics_fact (
    position_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL, position_date DATE NOT NULL,
    portfolio_sk BIGINT, security_sk BIGINT, business_unit_sk BIGINT,
    quantity DECIMAL(18, 4), market_value_usd DECIMAL(18, 2), book_value_usd DECIMAL(18, 2),
    cost_basis_usd DECIMAL(18, 2), unrealized_gl_usd DECIMAL(18, 2),
    concentration_pct DECIMAL(10, 6) COMMENT 'market_value_usd / SUM OVER team-date',
    portfolio_rank INT COMMENT 'DENSE_RANK by market_value_usd within (team, date)',
    currency_code STRING, silver_loaded_at TIMESTAMP,
    gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (position_date, portfolio_sk)
COMMENT 'PD direct-lending positions with concentration + rank.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vcontract_details_fact (
    contract_details_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL, detail_date DATE NOT NULL,
    contract_sk BIGINT, entity_sk BIGINT, contract_type STRING,
    principal_usd DECIMAL(18, 2), coupon_rate DECIMAL(10, 6), spread_over_benchmark DECIMAL(10, 6),
    days_to_maturity INT, status STRING, has_active_breach BOOLEAN,
    vintage_year INT COMMENT 'year(signing_date)',
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (detail_date, contract_sk)
COMMENT 'PD direct-lending contract details.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vcontract_summary_fact (
    contract_summary_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL, summary_date DATE NOT NULL,
    contract_sk BIGINT, outstanding_principal_usd DECIMAL(18, 2), accrued_interest_usd DECIMAL(18, 2),
    paid_to_date_usd DECIMAL(18, 2), performance_status STRING,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (summary_date, contract_sk)
COMMENT 'PD direct-lending contract period-end summaries.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vportfolio_analytics_fact (
    portfolio_analytics_sk BIGINT NOT NULL, analytics_date DATE NOT NULL,
    portfolio_sk BIGINT, business_unit_sk BIGINT,
    var_95 DECIMAL(18, 6), var_99 DECIMAL(18, 6), expected_shortfall DECIMAL(18, 6),
    period_return_pct DECIMAL(10, 6), ytd_return_pct DECIMAL(10, 6), benchmark_return_pct DECIMAL(10, 6),
    benchmark_code STRING, silver_loaded_at TIMESTAMP,
    gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (analytics_date, portfolio_sk)
COMMENT 'PD direct-lending portfolio analytics.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vsecurity_dim (
    security_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL,
    effective_start_date DATE NOT NULL, effective_end_date DATE NOT NULL DEFAULT DATE'9999-12-31',
    is_current BOOLEAN NOT NULL, security_name STRING, asset_class STRING, sub_asset_class STRING,
    issue_date DATE, maturity_date DATE, coupon_rate DECIMAL(10, 6), currency_code STRING,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (enterprise_key)
COMMENT 'PD direct-lending team-relevant security dim subset (held by team).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vsecurity_master_fact (
    security_master_sk BIGINT NOT NULL, snapshot_date DATE NOT NULL,
    security_sk BIGINT, enterprise_key STRING NOT NULL, security_name STRING,
    asset_class STRING, latest_close_price_usd DECIMAL(18, 6), days_to_maturity INT, is_matured BOOLEAN,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (snapshot_date, security_sk)
COMMENT 'PD direct-lending security master snapshot.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vsecurity_price_fact (
    security_price_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL, price_date DATE NOT NULL,
    security_sk BIGINT, close_price_usd DECIMAL(18, 6), currency_code STRING, price_type STRING,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (price_date, security_sk)
COMMENT 'PD direct-lending security prices for held securities.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vsecurity_rating_dim (
    security_rating_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL,
    effective_start_date DATE NOT NULL, effective_end_date DATE NOT NULL DEFAULT DATE'9999-12-31',
    is_current BOOLEAN NOT NULL, security_enterprise_key STRING, rating_agency STRING,
    rating_value STRING, rating_outlook STRING, rating_numeric_score INT,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (enterprise_key)
COMMENT 'PD direct-lending team-relevant security ratings.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vtransactions_collateral_exposure_fact (
    collateral_exposure_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL, exposure_date DATE NOT NULL,
    contract_sk BIGINT, exposure_amount_usd DECIMAL(18, 2), collateral_value_usd DECIMAL(18, 2),
    collateral_type STRING, ltv_pct DECIMAL(10, 6),
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (exposure_date, contract_sk)
COMMENT 'PD direct-lending collateral exposure.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS team_pd_direct_lending.t_vtransactions_collateral_positions_fact (
    collateral_position_sk BIGINT NOT NULL, enterprise_key STRING NOT NULL, position_date DATE NOT NULL,
    contract_sk BIGINT, security_sk BIGINT, position_value_usd DECIMAL(18, 2),
    collateral_role STRING, silver_loaded_at TIMESTAMP,
    gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (position_date, contract_sk)
COMMENT 'PD direct-lending collateral positions.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- ============================================================================
-- SECTIONS B-E — same 10 tables for the other 4 PD teams.
-- Schemas are identical to direct_lending (above) modulo schema name.
-- ============================================================================

-- SECTION B — team_pd_distressed
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_pd_distressed.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION C — team_pd_mezzanine
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_pd_mezzanine.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION D — team_pd_real_estate_debt
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_pd_real_estate_debt.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION E — team_pd_specialty_finance
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_pd_specialty_finance.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- ============================================================================
-- SECTION F — gold_pd_consolidated (3 cross-team UNION facts)
-- ============================================================================

CREATE TABLE IF NOT EXISTS gold_pd_consolidated.t_vpd_position_book (
    pd_position_book_sk BIGINT NOT NULL, team_code STRING NOT NULL,
    enterprise_key STRING NOT NULL, position_date DATE NOT NULL,
    portfolio_sk BIGINT, security_sk BIGINT, business_unit_sk BIGINT,
    market_value_usd DECIMAL(18, 2), book_value_usd DECIMAL(18, 2),
    cost_basis_usd DECIMAL(18, 2), unrealized_gl_usd DECIMAL(18, 2),
    concentration_pct DECIMAL(10, 6), portfolio_rank INT, currency_code STRING,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (position_date, team_code)
COMMENT 'Cross-team PD position book. UNION ALL across the 5 team_pd_*.vposition_analytics_fact views with team_code passthrough.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS gold_pd_consolidated.t_vpd_transaction_book (
    pd_transaction_book_sk BIGINT NOT NULL, team_code STRING NOT NULL,
    enterprise_key STRING NOT NULL, transaction_date DATE NOT NULL,
    settlement_date DATE, portfolio_sk BIGINT, security_sk BIGINT,
    transaction_type STRING, gross_amount_usd DECIMAL(18, 2), net_amount_usd DECIMAL(18, 2),
    fees_usd DECIMAL(18, 2), counterparty_name STRING, currency_code STRING,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (transaction_date, team_code)
COMMENT 'Cross-team PD transaction book. UNION ALL across teams with team_code.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

CREATE TABLE IF NOT EXISTS gold_pd_consolidated.t_vpd_contract_book (
    pd_contract_book_sk BIGINT NOT NULL, team_code STRING NOT NULL,
    enterprise_key STRING NOT NULL, summary_date DATE NOT NULL,
    contract_sk BIGINT, outstanding_principal_usd DECIMAL(18, 2),
    accrued_interest_usd DECIMAL(18, 2), paid_to_date_usd DECIMAL(18, 2),
    performance_status STRING, has_active_breach BOOLEAN,
    silver_loaded_at TIMESTAMP, gold_loaded_at TIMESTAMP NOT NULL DEFAULT current_timestamp()
) CLUSTER BY (summary_date, team_code)
COMMENT 'Cross-team PD contract book. UNION ALL across teams.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- ============================================================================
-- SECTIONS G-K (0.1.2) — non-PD team tables. LIKE-cloned from
-- team_pd_direct_lending; seed already has positions for teams 6-10 so these
-- get rows on the next orchestrator refresh.
-- ============================================================================

-- SECTION G — team_re_core
CREATE TABLE IF NOT EXISTS team_re_core.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_re_core.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_re_core.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_re_core.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION H — team_re_value_add
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_re_value_add.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION I — team_pe_buyout
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_pe_buyout.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION J — team_infra
CREATE TABLE IF NOT EXISTS team_infra.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_infra.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_infra.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_infra.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

-- SECTION K — team_public_equity
CREATE TABLE IF NOT EXISTS team_public_equity.t_vposition_analytics_fact LIKE team_pd_direct_lending.t_vposition_analytics_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vcontract_details_fact LIKE team_pd_direct_lending.t_vcontract_details_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vcontract_summary_fact LIKE team_pd_direct_lending.t_vcontract_summary_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vportfolio_analytics_fact LIKE team_pd_direct_lending.t_vportfolio_analytics_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vsecurity_dim LIKE team_pd_direct_lending.t_vsecurity_dim;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vsecurity_master_fact LIKE team_pd_direct_lending.t_vsecurity_master_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vsecurity_price_fact LIKE team_pd_direct_lending.t_vsecurity_price_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vsecurity_rating_dim LIKE team_pd_direct_lending.t_vsecurity_rating_dim;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vtransactions_collateral_exposure_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact;
CREATE TABLE IF NOT EXISTS team_public_equity.t_vtransactions_collateral_positions_fact LIKE team_pd_direct_lending.t_vtransactions_collateral_positions_fact;

SELECT 'gold.tables complete' AS status,
       count(*) AS gold_table_count
FROM information_schema.tables
WHERE table_schema IN ('team_pd_direct_lending','team_pd_distressed','team_pd_mezzanine',
                       'team_pd_real_estate_debt','team_pd_specialty_finance','gold_pd_consolidated',
                       'team_re_core','team_re_value_add','team_pe_buyout','team_infra','team_public_equity')
  AND table_name LIKE 't_v%';
