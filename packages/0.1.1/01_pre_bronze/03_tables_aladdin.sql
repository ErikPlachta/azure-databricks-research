-- ============================================================================
-- 01_pre_bronze/03_tables_aladdin.sql
-- BlackRock Aladdin source. 4 raw tables.
--
-- Provides portfolio risk/performance, compliance, and trading data. Bronze
-- precedence treats Aladdin as primary for vportfolio_risk and
-- vportfolio_performance, secondary overlay for vportfolio (master from
-- aladdin) and vbusiness_unit (compliance-team membership overlay), and
-- in-flight data for vtransaction (trade_blotter feeds settled state_street
-- with in-progress trades).
--
-- See DECISIONS.md #3 for the precedence table.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 3.1 PORTFOLIO RISK ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aladdin.portfolio_risk_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL COMMENT 'Aladdin portfolio identifier',
    risk_date                 DATE         NOT NULL,
    var_95                    DECIMAL(18, 6) COMMENT '95% Value-at-Risk',
    var_99                    DECIMAL(18, 6),
    expected_shortfall        DECIMAL(18, 6),
    beta                      DECIMAL(8, 4),
    tracking_error            DECIMAL(8, 4),
    risk_currency             STRING       COMMENT 'Currency in which risk metrics are expressed',
    portfolio_name            STRING       COMMENT 'Denormalized; may diverge from aspen master',
    strategy_name             STRING,
    record_source             STRING       NOT NULL DEFAULT 'aladdin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Daily portfolio-level risk metrics from Aladdin.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 3.2 PORTFOLIO PERFORMANCE ---------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aladdin.portfolio_performance_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL,
    performance_date          DATE         NOT NULL,
    period_return_pct         DECIMAL(10, 6) COMMENT 'Daily/period return as decimal (0.0125 = 1.25%)',
    ytd_return_pct            DECIMAL(10, 6),
    since_inception_return_pct DECIMAL(10, 6),
    benchmark_return_pct      DECIMAL(10, 6),
    benchmark_code            STRING,
    record_source             STRING       NOT NULL DEFAULT 'aladdin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Daily portfolio performance from Aladdin.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 3.3 COMPLIANCE CHECK --------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aladdin.compliance_check_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL,
    check_date                DATE         NOT NULL,
    rule_code                 STRING,
    rule_name                 STRING,
    rule_status               STRING       COMMENT 'PASS / WARN / BREACH',
    breach_amount             DECIMAL(18, 2),
    breach_pct                DECIMAL(10, 6),
    risk_team_code            STRING       COMMENT 'Risk-team assignment (used by vbusiness_unit overlay)',
    record_source             STRING       NOT NULL DEFAULT 'aladdin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Compliance check results. risk_team_code feeds the vbusiness_unit overlay (decision #7).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 3.4 TRADE BLOTTER -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aladdin.trade_blotter_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    portfolio_source_key      STRING       NOT NULL,
    security_source_key       STRING       NOT NULL,
    trade_date                DATE         NOT NULL,
    trade_status              STRING       COMMENT 'PENDING / EXECUTED / SETTLED / CANCELLED',
    quantity                  DECIMAL(18, 4),
    limit_price               DECIMAL(18, 4),
    side                      STRING       COMMENT 'BUY / SELL',
    trader_id                 STRING,
    currency_code             STRING,
    record_source             STRING       NOT NULL DEFAULT 'aladdin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Order/trade blotter. State Street settled-state is authoritative for vtransaction; this provides in-flight overlay.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

SELECT 'pre_bronze.aladdin.tables complete' AS status, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'raw_aladdin';
