-- ============================================================================
-- 01_pre_bronze/02_tables_state_street.sql
-- Custodian source. 5 raw tables.
--
-- Conventions:
--   * source_key      = State Street's natural key (e.g., position_id, txn_id)
--   * enterprise_key  = assigned at ingestion (deterministic hash for demo)
--   * loaded_at       = ingestion timestamp
--   * NO clustering / row-tracking / CDF (per plan §"Pre-bronze")
--   * `delta.feature.allowColumnDefaults` IS enabled — required for the
--     DEFAULT clauses on record_source / loaded_at. This is a separate
--     feature from row-tracking / CDF and doesn't make MV refresh faster.
--   * Mixed-currency rows; NULL-tolerant lookup strings; multiple corrections
--     per source_key are possible (data-team-not-analytics-aware reality)
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 2.1 POSITION (daily holdings) -----------------------------------------------
CREATE TABLE IF NOT EXISTS raw_state_street.position_raw (
    source_key                STRING       NOT NULL COMMENT 'State Street position_id',
    enterprise_key            STRING       NOT NULL COMMENT 'Internal stable ID assigned at ingestion',
    portfolio_source_key      STRING       NOT NULL COMMENT 'State Street account/portfolio identifier',
    security_source_key       STRING       NOT NULL COMMENT 'State Street security identifier',
    position_date             DATE         NOT NULL,
    quantity                  DECIMAL(18, 4),
    market_value_local        DECIMAL(18, 2),
    book_value_local          DECIMAL(18, 2),
    cost_basis_local          DECIMAL(18, 2),
    unrealized_gl_local       DECIMAL(18, 2),
    unit_price_local          DECIMAL(18, 6),
    currency_code             STRING       COMMENT 'Local currency for *_local cols (USD/EUR/GBP/JPY/CAD/AUD)',
    settlement_status         STRING       COMMENT 'SETTLED / PENDING / FAILED',
    custodian_account         STRING,
    record_source             STRING       NOT NULL DEFAULT 'state_street',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Daily position holdings from State Street. Multiple rows per source_key represent corrections; downstream views must handle latest-wins.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 2.2 TRANSACTION -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_state_street.transaction_raw (
    source_key                STRING       NOT NULL COMMENT 'State Street transaction_id',
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL,
    security_source_key       STRING       NOT NULL,
    transaction_date          DATE         NOT NULL,
    settlement_date           DATE,
    transaction_type          STRING       COMMENT 'BUY / SELL / ACQUISITION / DISPOSAL',
    quantity                  DECIMAL(18, 4),
    price_local               DECIMAL(18, 4),
    gross_amount_local        DECIMAL(18, 2),
    fees_local                DECIMAL(18, 2),
    net_amount_local          DECIMAL(18, 2),
    currency_code             STRING,
    counterparty_name         STRING,
    custodian_account         STRING,
    record_source             STRING       NOT NULL DEFAULT 'state_street',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Transaction settlements from State Street. Cancel/correction events show as additional rows with the same source_key.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 2.3 SECURITY PRICE (end-of-day) ---------------------------------------------
CREATE TABLE IF NOT EXISTS raw_state_street.security_price_raw (
    source_key                STRING       NOT NULL COMMENT 'Composite: security_source_key + price_date',
    enterprise_key            STRING       NOT NULL,
    security_source_key       STRING       NOT NULL,
    price_date                DATE         NOT NULL,
    close_price_local         DECIMAL(18, 6),
    currency_code             STRING,
    price_type                STRING       COMMENT 'CLOSE / NAV / VALUATION',
    record_source             STRING       NOT NULL DEFAULT 'state_street',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'End-of-day prices for held securities. Sparse (only securities the firm holds). Bloomberg covers broader market data — deferred to 0.1.5.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 2.4 CASH FLOW ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_state_street.cash_flow_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL,
    cash_flow_date            DATE         NOT NULL,
    cash_flow_type            STRING       COMMENT 'INCOME / EXPENSE / CONTRIBUTION / DISTRIBUTION / FEE',
    amount_local              DECIMAL(18, 2),
    currency_code             STRING,
    counterparty_name         STRING,
    record_source             STRING       NOT NULL DEFAULT 'state_street',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Cash movements at the portfolio level.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 2.5 NAV (Net Asset Value) ---------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_state_street.nav_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL,
    nav_date                  DATE         NOT NULL,
    nav_local                 DECIMAL(18, 2),
    currency_code             STRING,
    gross_assets_local        DECIMAL(18, 2),
    net_assets_local          DECIMAL(18, 2),
    total_units               DECIMAL(18, 4),
    record_source             STRING       NOT NULL DEFAULT 'state_street',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Daily NAV per portfolio.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

SELECT 'pre_bronze.state_street.tables complete' AS status, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'raw_state_street';
