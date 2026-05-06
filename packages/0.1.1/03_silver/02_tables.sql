-- ============================================================================
-- 03_silver/02_tables.sql
-- ~21 silver t_<entity> Delta tables.
--
-- Conventions:
--   * SCD2 dims (8): <entity>_sk BIGINT NOT NULL (assigned via ROW_NUMBER in
--     view), enterprise_key, effective_start_date, effective_end_date
--     (DEFAULT '9999-12-31' for current), is_current BOOLEAN, preceding/
--     succeeding_record_sk BIGINT chain links, plus entity attributes.
--   * vfx_rate_dim: type-2-lite (effective dates but no chain).
--   * Facts: temporal-resolved dim_sk FKs + _local + _usd amount cols.
--   * Cancels: parallel to base fact, plus cancel_event_date + cancel_reason.
--   * Monthend: period-end snapshots from base fact, aggregated.
--
-- Liquid Clustering:
--   * SCD2 dims: CLUSTER BY (enterprise_key)
--   * Facts (date-grained): CLUSTER BY (<date_col>, portfolio_sk)
--   * fx_rate_dim: CLUSTER BY (from_currency, to_currency, rate_date)
--
-- All tables: row tracking + CDF + allowColumnDefaults enabled.
--
-- Audit: bronze_loaded_at + silver_loaded_at timestamps.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- SCD2 DIMS (8)
-- ============================================================================

-- 2.1 vsecurity_dim ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vsecurity_dim (
    security_sk                   BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    security_name                 STRING,
    security_type                 STRING,
    asset_class                   STRING,
    sub_asset_class               STRING,
    issue_date                    DATE,
    maturity_date                 DATE,
    coupon_rate                   DECIMAL(10, 6),
    currency_code                 STRING,
    issuer_enterprise_key         STRING,
    isin_code                     STRING,
    cusip_code                    STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 security dimension. Chain-linked via preceding/succeeding_record_sk. is_current=TRUE marks the latest version. Use temporal-resolution joins on fact tables: fact_date BETWEEN effective_start_date AND effective_end_date.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.2 vsecurity_rating_dim -----------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vsecurity_rating_dim (
    security_rating_sk            BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    security_enterprise_key       STRING,
    rating_agency                 STRING,
    rating_value                  STRING,
    rating_outlook                STRING,
    rating_action_type            STRING,
    rating_numeric_score          INT          COMMENT 'Derived: AAA=1, AA=2, ..., D=10. NULL if unmapped.',
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 security rating dimension. Each rating_action (UPGRADE/DOWNGRADE/AFFIRM) closes the prior row and opens a new one.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.3 vcontract_dim ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vcontract_dim (
    contract_sk                   BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    contract_name                 STRING,
    entity_enterprise_key         STRING,
    contract_type                 STRING,
    signing_date                  DATE,
    maturity_date                 DATE,
    principal_local               DECIMAL(18, 2),
    currency_code                 STRING,
    coupon_type                   STRING,
    coupon_rate                   DECIMAL(10, 6),
    spread_over_benchmark         DECIMAL(10, 6),
    benchmark_code                STRING,
    status                        STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 contract dimension. Amendments emit new SCD2 rows; the original is closed and the amendment becomes is_current.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.4 vportfolio_dim -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vportfolio_dim (
    portfolio_sk                  BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    portfolio_name                STRING,
    strategy_name                 STRING,
    business_unit_enterprise_key  STRING       COMMENT 'FK to vbusiness_unit_dim',
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 portfolio dimension. Portfolios link to business units (10-team registry).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.5 ventity_dim --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_ventity_dim (
    entity_sk                     BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    entity_name                   STRING,
    entity_type                   STRING,
    legal_structure               STRING,
    jurisdiction                  STRING,
    tax_id                        STRING,
    formation_date                DATE,
    dissolution_date              DATE,
    parent_entity_enterprise_key  STRING,
    is_active                     BOOLEAN,
    country                       STRING,
    has_contracts                 BOOLEAN,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 entity dimension. Restructurings emit successor rows linked via preceding/succeeding_record_sk. Soft-deletes mark dissolution_date and is_current=FALSE without successor.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.6 vsecurity_industry_dim ---------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vsecurity_industry_dim (
    industry_sk                   BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    classification_code           STRING,
    classification_name           STRING,
    parent_code                   STRING,
    classification_level          INT,
    classification_system         STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 industry classification dimension (GICS / NAICS / ICB / INTERNAL).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.7 vreporting_group_dim -----------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vreporting_group_dim (
    reporting_group_sk            BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    group_code                    STRING,
    group_name                    STRING,
    parent_group_code             STRING,
    group_level                   INT,
    group_type                    STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 reporting group dimension (strategy / geography / structure / risk roll-ups).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.8 vbusiness_unit_dim -------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vbusiness_unit_dim (
    business_unit_sk              BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    effective_start_date          DATE         NOT NULL,
    effective_end_date            DATE         NOT NULL DEFAULT DATE'9999-12-31',
    is_current                    BOOLEAN      NOT NULL,
    preceding_record_sk           BIGINT,
    succeeding_record_sk          BIGINT,
    bu_code                       STRING       NOT NULL COMMENT 'team_pd_direct_lending / team_pd_distressed / team_re_core / etc.',
    bu_name                       STRING,
    bu_type                       STRING,
    parent_bu_enterprise_key      STRING,
    asset_class_focus             STRING,
    strategy_name                 STRING,
    is_pd_strategy                BOOLEAN      COMMENT 'TRUE for the 5 team_pd_* strategies; FALSE for non-PD teams',
    head_employee_id              STRING,
    established_date              DATE,
    is_active                     BOOLEAN,
    associated_risk_team_codes    ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'SCD2 business unit dimension (10 teams: 5 PD strategies + 5 non-PD). is_pd_strategy flag identifies the gold-team subset.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- ============================================================================
-- TYPE-2-LITE DIM (1)
-- ============================================================================

-- 2.9 vfx_rate_dim -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vfx_rate_dim (
    fx_rate_sk                    BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    from_currency                 STRING       NOT NULL,
    to_currency                   STRING       NOT NULL,
    rate_date                     DATE         NOT NULL,
    fx_rate                       DECIMAL(18, 8) NOT NULL,
    rate_type                     STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (from_currency, to_currency, rate_date)
COMMENT 'Type-2-lite FX rate dim. Date-bounded but no preceding/succeeding chain — rates simply expire when superseded by next-day rate. Powers silver-layer USD normalization.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- ============================================================================
-- FACTS (8 base + 2 monthend = 10)
-- ============================================================================

-- 2.10 vposition_analytics_fact (daily position with USD normalization) -------
CREATE TABLE IF NOT EXISTS investments.t_vposition_analytics_fact (
    position_sk                   BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    position_date                 DATE         NOT NULL,
    portfolio_sk                  BIGINT       COMMENT 'Temporal-resolved FK to vportfolio_dim',
    security_sk                   BIGINT       COMMENT 'Temporal-resolved FK to vsecurity_dim',
    business_unit_sk              BIGINT,
    quantity                      DECIMAL(18, 4),
    market_value_local            DECIMAL(18, 2),
    market_value_usd              DECIMAL(18, 2) COMMENT 'market_value_local * fx_rate(currency_code -> USD, position_date)',
    book_value_local              DECIMAL(18, 2),
    book_value_usd                DECIMAL(18, 2),
    cost_basis_local              DECIMAL(18, 2),
    cost_basis_usd                DECIMAL(18, 2),
    unrealized_gl_local           DECIMAL(18, 2),
    unrealized_gl_usd             DECIMAL(18, 2),
    unit_price_local              DECIMAL(18, 6),
    currency_code                 STRING,
    fx_rate_to_usd                DECIMAL(18, 8),
    settlement_status             STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (position_date, portfolio_sk)
COMMENT 'Daily position fact with currency-normalized USD columns. dim_sks resolved via temporal join: fact_date BETWEEN dim.effective_start_date AND dim.effective_end_date.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.11 vposition_monthend_fact -------------------------------------------------
CREATE TABLE IF NOT EXISTS investments_history.t_vposition_monthend_fact (
    position_monthend_sk          BIGINT       NOT NULL,
    monthend_date                 DATE         NOT NULL COMMENT 'Last day of month',
    portfolio_sk                  BIGINT,
    security_sk                   BIGINT,
    business_unit_sk              BIGINT,
    quantity                      DECIMAL(18, 4),
    market_value_local            DECIMAL(18, 2),
    market_value_usd              DECIMAL(18, 2),
    book_value_local              DECIMAL(18, 2),
    cost_basis_usd                DECIMAL(18, 2),
    unrealized_gl_usd             DECIMAL(18, 2),
    currency_code                 STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (monthend_date, portfolio_sk)
COMMENT 'Period-end (month-end) position snapshot. Pre-aggregated from vposition_analytics_fact. Cancel-aware (excludes corrected-out positions).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.12 vsecurity_master_fact ---------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vsecurity_master_fact (
    security_master_sk            BIGINT       NOT NULL,
    snapshot_date                 DATE         NOT NULL,
    security_sk                   BIGINT,
    enterprise_key                STRING       NOT NULL,
    security_name                 STRING,
    asset_class                   STRING,
    sub_asset_class               STRING,
    issue_date                    DATE,
    maturity_date                 DATE,
    coupon_rate                   DECIMAL(10, 6),
    currency_code                 STRING,
    issuer_enterprise_key         STRING,
    latest_close_price_local      DECIMAL(18, 6),
    latest_close_price_usd        DECIMAL(18, 6),
    days_to_maturity              INT,
    is_matured                    BOOLEAN,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (snapshot_date, security_sk)
COMMENT 'Security master snapshot fact. Period-end view combining SCD2 dim attrs with latest pricing + derived flags.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.13 vsecurity_price_fact ----------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vsecurity_price_fact (
    security_price_sk             BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    price_date                    DATE         NOT NULL,
    security_sk                   BIGINT,
    close_price_local             DECIMAL(18, 6),
    close_price_usd               DECIMAL(18, 6),
    currency_code                 STRING,
    fx_rate_to_usd                DECIMAL(18, 8),
    price_type                    STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (price_date, security_sk)
COMMENT 'Daily security price fact with USD normalization.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.14 vcontract_details_fact --------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vcontract_details_fact (
    contract_details_sk           BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    detail_date                   DATE         NOT NULL,
    contract_sk                   BIGINT,
    entity_sk                     BIGINT,
    contract_type                 STRING,
    principal_local               DECIMAL(18, 2),
    principal_usd                 DECIMAL(18, 2),
    coupon_rate                   DECIMAL(10, 6),
    spread_over_benchmark         DECIMAL(10, 6),
    days_to_maturity              INT,
    status                        STRING,
    has_active_breach             BOOLEAN      COMMENT 'TRUE if any covenant_status = TRIPPED on detail_date',
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (detail_date, contract_sk)
COMMENT 'Contract details fact. Joins contract dim + covenant breach flag + USD normalization.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.15 vcontract_summary_fact --------------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vcontract_summary_fact (
    contract_summary_sk           BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    summary_date                  DATE         NOT NULL,
    contract_sk                   BIGINT,
    outstanding_principal_local   DECIMAL(18, 2),
    outstanding_principal_usd     DECIMAL(18, 2),
    accrued_interest_local        DECIMAL(18, 2),
    accrued_interest_usd          DECIMAL(18, 2),
    paid_to_date_local            DECIMAL(18, 2),
    paid_to_date_usd              DECIMAL(18, 2),
    currency_code                 STRING,
    fx_rate_to_usd                DECIMAL(18, 8),
    performance_status            STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (summary_date, contract_sk)
COMMENT 'Period-end contract summary fact (typically monthly). USD-normalized.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.16 vportfolio_analytics_fact -----------------------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vportfolio_analytics_fact (
    portfolio_analytics_sk        BIGINT       NOT NULL,
    analytics_date                DATE         NOT NULL,
    portfolio_sk                  BIGINT,
    business_unit_sk              BIGINT,
    var_95                        DECIMAL(18, 6),
    var_99                        DECIMAL(18, 6),
    expected_shortfall            DECIMAL(18, 6),
    beta                          DECIMAL(8, 4),
    tracking_error                DECIMAL(8, 4),
    period_return_pct             DECIMAL(10, 6),
    ytd_return_pct                DECIMAL(10, 6),
    since_inception_return_pct    DECIMAL(10, 6),
    benchmark_return_pct          DECIMAL(10, 6),
    benchmark_code                STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (analytics_date, portfolio_sk)
COMMENT 'Portfolio analytics fact: aladdin risk + performance joined per-portfolio per-date.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.17 vportfolio_analytics_monthend_fact --------------------------------------
CREATE TABLE IF NOT EXISTS investments_history.t_vportfolio_analytics_monthend_fact (
    portfolio_analytics_monthend_sk BIGINT     NOT NULL,
    monthend_date                 DATE         NOT NULL,
    portfolio_sk                  BIGINT,
    business_unit_sk              BIGINT,
    monthend_var_95               DECIMAL(18, 6),
    monthend_var_99               DECIMAL(18, 6),
    period_return_pct             DECIMAL(10, 6),
    ytd_return_pct                DECIMAL(10, 6),
    benchmark_return_pct          DECIMAL(10, 6),
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (monthend_date, portfolio_sk)
COMMENT 'Period-end portfolio analytics. Pre-aggregated last-day-of-month snapshot.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.18 vtransactions_collateral_exposure_fact ----------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vtransactions_collateral_exposure_fact (
    collateral_exposure_sk        BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    exposure_date                 DATE         NOT NULL,
    contract_sk                   BIGINT,
    exposure_amount_local         DECIMAL(18, 2),
    exposure_amount_usd           DECIMAL(18, 2),
    collateral_value_local        DECIMAL(18, 2),
    collateral_value_usd          DECIMAL(18, 2),
    currency_code                 STRING,
    fx_rate_to_usd                DECIMAL(18, 8),
    collateral_type               STRING,
    ltv_pct                       DECIMAL(10, 6),
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (exposure_date, contract_sk)
COMMENT 'Collateral exposure per contract per date. USD-normalized.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.19 vtransactions_collateral_positions_fact ---------------------------------
CREATE TABLE IF NOT EXISTS investments.t_vtransactions_collateral_positions_fact (
    collateral_position_sk        BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    position_date                 DATE         NOT NULL,
    contract_sk                   BIGINT,
    security_sk                   BIGINT,
    asset_enterprise_key          STRING,
    position_value_local          DECIMAL(18, 2),
    position_value_usd            DECIMAL(18, 2),
    currency_code                 STRING,
    fx_rate_to_usd                DECIMAL(18, 8),
    collateral_role               STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (position_date, contract_sk)
COMMENT 'Specific securities/assets pledged as collateral against a contract on a given date.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.20 vtransaction_fact -------------------------------------------------------
-- Transaction-level fact joining bronze.vtransaction to silver dims for
-- temporal-resolved portfolio_sk/security_sk + FX-converted USD amounts.
-- Powers gold_pd_consolidated.vpd_transaction_book (DECISIONS.md #15).
CREATE TABLE IF NOT EXISTS investments.t_vtransaction_fact (
    transaction_fact_sk           BIGINT       NOT NULL,
    enterprise_key                STRING       NOT NULL,
    transaction_date              DATE         NOT NULL,
    settlement_date               DATE,
    portfolio_sk                  BIGINT       COMMENT 'Temporal-resolved FK to vportfolio_dim',
    security_sk                   BIGINT       COMMENT 'Temporal-resolved FK to vsecurity_dim',
    business_unit_sk              BIGINT,
    transaction_type              STRING,
    quantity                      DECIMAL(18, 4),
    price_local                   DECIMAL(18, 6),
    gross_amount_local            DECIMAL(18, 2),
    gross_amount_usd              DECIMAL(18, 2) COMMENT 'gross_amount_local * fx_rate(currency_code → USD, transaction_date)',
    fees_local                    DECIMAL(18, 2),
    fees_usd                      DECIMAL(18, 2),
    net_amount_local              DECIMAL(18, 2),
    net_amount_usd                DECIMAL(18, 2),
    currency_code                 STRING,
    fx_rate_to_usd                DECIMAL(18, 8),
    counterparty_name             STRING,
    custodian_account             STRING,
    trade_status                  STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (transaction_date, portfolio_sk)
COMMENT 'Transaction fact: bronze.vtransaction enriched with dim_sks + USD normalization. Powers gold_pd_consolidated.vpd_transaction_book.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- ============================================================================
-- CANCEL SIBLINGS (3)
-- ============================================================================

-- 2.20 vcontract_details_cancels_fact ------------------------------------------
CREATE TABLE IF NOT EXISTS investments_history.t_vcontract_details_cancels_fact (
    cancel_sk                     BIGINT       NOT NULL,
    cancelled_contract_details_sk BIGINT       NOT NULL COMMENT 'Original contract_details_sk being cancelled',
    contract_sk                   BIGINT,
    cancel_event_date             DATE         NOT NULL,
    original_detail_date          DATE,
    cancel_reason                 STRING,
    cancelled_principal_usd       DECIMAL(18, 2),
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (cancel_event_date, contract_sk)
COMMENT 'Cancel/reversal events for contract details. Downstream queries UNION + filter to exclude cancelled entries.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.21 vposition_cancels_fact --------------------------------------------------
CREATE TABLE IF NOT EXISTS investments_history.t_vposition_cancels_fact (
    cancel_sk                     BIGINT       NOT NULL,
    cancelled_position_sk         BIGINT       NOT NULL,
    portfolio_sk                  BIGINT,
    security_sk                   BIGINT,
    cancel_event_date             DATE         NOT NULL,
    original_position_date        DATE,
    cancel_reason                 STRING,
    cancelled_market_value_usd    DECIMAL(18, 2),
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (cancel_event_date, portfolio_sk)
COMMENT 'Position correction/cancel events. State Street emits these via duplicate source_keys with corrected values.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- 2.22 vsecurity_price_cancels_fact --------------------------------------------
CREATE TABLE IF NOT EXISTS investments_history.t_vsecurity_price_cancels_fact (
    cancel_sk                     BIGINT       NOT NULL,
    cancelled_security_price_sk   BIGINT       NOT NULL,
    security_sk                   BIGINT,
    cancel_event_date             DATE         NOT NULL,
    original_price_date           DATE,
    cancel_reason                 STRING,
    cancelled_close_price_usd     DECIMAL(18, 6),
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (cancel_event_date, security_sk)
COMMENT 'Security price correction/cancel events. Custodian emits price restatements via this pattern.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

-- ============================================================================
-- BRIDGE (1)
-- ============================================================================

-- 2.23 vincome_bridge ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS investments_history.t_vincome_bridge (
    income_bridge_sk              BIGINT       NOT NULL,
    portfolio_sk                  BIGINT       NOT NULL,
    security_sk                   BIGINT,
    contract_sk                   BIGINT,
    income_date                   DATE         NOT NULL,
    income_type                   STRING       COMMENT 'COUPON / DIVIDEND / FEE_INCOME / OTHER',
    income_amount_local           DECIMAL(18, 2),
    income_amount_usd             DECIMAL(18, 2),
    currency_code                 STRING,
    bronze_loaded_at              TIMESTAMP,
    silver_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (income_date, portfolio_sk)
COMMENT 'Income flows bridge. Many-to-many between portfolios and securities/contracts on a given income date.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported', 'delta.enableRowTracking' = 'true', 'delta.enableChangeDataFeed' = 'true');

SELECT 'silver.tables complete' AS status,
       count(*) AS silver_table_count
FROM information_schema.tables
WHERE table_schema = 'investments'
  AND table_name LIKE 't_v%';
