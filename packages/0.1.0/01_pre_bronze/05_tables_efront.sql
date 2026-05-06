-- ============================================================================
-- 01_pre_bronze/05_tables_efront.sql
-- BlackRock eFront source. 6 raw tables.
--
-- Heavy contributor to private-debt domain. Table shapes inferred from
-- industry-standard eFront usage (fund admin, private-capital deal mgmt).
-- See DECISIONS.md #4 for per-table assumptions; willing to revise once
-- authoritative shapes are available.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 5.1 CONTRACT (loan / credit-facility / fund commitment) ---------------------
CREATE TABLE IF NOT EXISTS raw_efront.contract_raw (
    source_key                STRING       NOT NULL COMMENT 'eFront contract_uuid',
    enterprise_key            STRING       NOT NULL,
    contract_name             STRING,
    entity_source_key         STRING       NOT NULL COMMENT 'Borrower or counterparty entity',
    contract_type             STRING       COMMENT 'TERM_LOAN / REVOLVER / MEZZ / UNITRANCHE / EQUITY_COMMITMENT',
    signing_date              DATE,
    maturity_date             DATE,
    principal_local           DECIMAL(18, 2),
    currency_code             STRING,
    coupon_type               STRING       COMMENT 'FIXED / FLOATING / PIK',
    coupon_rate               DECIMAL(10, 6),
    spread_over_benchmark     DECIMAL(10, 6),
    benchmark_code            STRING       COMMENT 'SOFR / EURIBOR / SONIA',
    status                    STRING       COMMENT 'ACTIVE / FULL_REPAID / DEFAULT / RESTRUCTURED / WRITTEN_OFF',
    record_source             STRING       NOT NULL DEFAULT 'efront',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Private-debt contracts (loans, credit facilities, equity commitments).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 5.2 CONTRACT SUMMARY (period-end snapshots) ---------------------------------
CREATE TABLE IF NOT EXISTS raw_efront.contract_summary_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    contract_source_key       STRING       NOT NULL,
    summary_date              DATE         NOT NULL,
    outstanding_principal_local DECIMAL(18, 2),
    accrued_interest_local    DECIMAL(18, 2),
    paid_to_date_local        DECIMAL(18, 2),
    currency_code             STRING,
    performance_status        STRING       COMMENT 'CURRENT / WATCH / NON_ACCRUAL / IMPAIRED',
    record_source             STRING       NOT NULL DEFAULT 'efront',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Period-end contract snapshots (typically monthly). Drives silver vcontract_summary_fact and its monthend siblings.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 5.3 CONTRACT COVENANT -------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_efront.contract_covenant_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    contract_source_key       STRING       NOT NULL,
    covenant_date             DATE         NOT NULL,
    covenant_type             STRING       COMMENT 'LEVERAGE / DSCR / INTEREST_COVERAGE / FCCR / LTV / MIN_LIQUIDITY',
    covenant_threshold        DECIMAL(18, 6),
    covenant_actual           DECIMAL(18, 6),
    covenant_status           STRING       COMMENT 'PASS / WATCH / TRIPPED / WAIVED',
    breach_severity           STRING       COMMENT 'NONE / SOFT / HARD',
    record_source             STRING       NOT NULL DEFAULT 'efront',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Contract-level covenant tests. Drives gold-team covenant compliance flags.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 5.4 CAPITAL ACTIVITY (fund cashflows / GP/LP) -------------------------------
CREATE TABLE IF NOT EXISTS raw_efront.capital_activity_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL COMMENT 'Closed-end fund identifier',
    entity_source_key         STRING       COMMENT 'Optional: counterparty entity for the activity',
    activity_date             DATE         NOT NULL,
    activity_type             STRING       COMMENT 'CAPITAL_CALL / DISTRIBUTION / FEE / EXPENSE / RECALL',
    amount_local              DECIMAL(18, 2),
    currency_code             STRING,
    lp_id_string              STRING       COMMENT 'Investor identifier (Limited Partner)',
    gp_id_string              STRING       COMMENT 'General Partner identifier',
    record_source             STRING       NOT NULL DEFAULT 'efront',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Capital activity for closed-end fund portfolios. eFront fills portfolio rows aladdin lacks.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 5.5 COLLATERAL EXPOSURE -----------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_efront.collateral_exposure_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    contract_source_key       STRING       NOT NULL,
    exposure_date             DATE         NOT NULL,
    exposure_amount_local     DECIMAL(18, 2),
    currency_code             STRING,
    collateral_type           STRING       COMMENT 'REAL_ESTATE / EQUIPMENT / RECEIVABLES / SECURITIES / OTHER',
    collateral_value_local    DECIMAL(18, 2),
    ltv_pct                   DECIMAL(10, 6) COMMENT 'Loan-to-value ratio',
    record_source             STRING       NOT NULL DEFAULT 'efront',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Collateral exposure measurement per contract per date.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 5.6 COLLATERAL POSITION -----------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_efront.collateral_position_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    contract_source_key       STRING       NOT NULL,
    security_source_key       STRING       COMMENT 'Optional: security pledged as collateral',
    asset_source_key          STRING       COMMENT 'Optional: real asset pledged as collateral',
    position_date             DATE         NOT NULL,
    position_value_local      DECIMAL(18, 2),
    currency_code             STRING,
    collateral_role           STRING       COMMENT 'PRIMARY / SUPPORTING / CROSS_COLLATERAL',
    record_source             STRING       NOT NULL DEFAULT 'efront',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Specific securities or real assets pledged as collateral against a contract.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

SELECT 'pre_bronze.efront.tables complete' AS status, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'raw_efront';
