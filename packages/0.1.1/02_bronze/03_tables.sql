-- ============================================================================
-- 02_bronze/03_tables.sql
-- 14 bronze t_<entity> Delta tables.
--
-- Provenance pattern (slight simplification from plan):
--   * Multi-source entities (5: vsecurity, ventity, vportfolio, vtransaction,
--     vbusiness_unit) carry per-column `<col>_source STRING` companions on
--     columns that MAY come from different sources.
--   * Single-source entities (9 others) carry only top-level `_source_pref`
--     (no per-column companions — the value would be a constant per entity).
--   * All entities carry top-level `_sources_in_conflict ARRAY<STRING>` for
--     diagnostic value (empty in 0.1.0; populated when bronze.v<entity> view
--     detects conflicting source values; see 04_views.sql).
--
-- Delta conventions (per plan §"Delta table conventions"):
--   * Fact-shaped (with date grain): CLUSTER BY (enterprise_key, <date_col>)
--   * Dim-shaped:                    CLUSTER BY (enterprise_key)
--   * Row tracking + CDF + allowColumnDefaults enabled on all
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- DIM-SHAPED TABLES (cluster by enterprise_key)
-- ============================================================================

-- 3.1 t_vsecurity (multi-source: aspen + state_street + efront) ---------------
CREATE TABLE IF NOT EXISTS bronze.t_vsecurity (
    enterprise_key                STRING       NOT NULL,
    security_name                 STRING,
    security_name_source          STRING,
    security_type                 STRING,
    security_type_source          STRING,
    asset_class                   STRING,
    asset_class_source            STRING,
    sub_asset_class               STRING,
    issue_date                    DATE,
    maturity_date                 DATE,
    coupon_rate                   DECIMAL(10, 6),
    currency_code                 STRING,
    currency_code_source          STRING,
    issuer_enterprise_key         STRING       COMMENT 'Resolved from aspen.issuer_source_key via crosswalk',
    isin_code                     STRING,
    cusip_code                    STRING,
    latest_close_price            DECIMAL(18, 6) COMMENT 'From state_street',
    latest_close_price_currency   STRING,
    latest_price_date             DATE,
    contract_total_principal      DECIMAL(18, 2) COMMENT 'Sum of efront contract principals where this security is collateral',
    _source_pref                  STRING       NOT NULL,
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'Bronze unified security. Aspen master + state_street prices + efront collateral context.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.2 t_ventity (multi-source: aspen + efront) --------------------------------
CREATE TABLE IF NOT EXISTS bronze.t_ventity (
    enterprise_key                STRING       NOT NULL,
    entity_name                   STRING,
    entity_name_source            STRING,
    entity_type                   STRING,
    entity_type_source            STRING,
    legal_structure               STRING,
    jurisdiction                  STRING,
    tax_id                        STRING,
    formation_date                DATE,
    dissolution_date              DATE,
    parent_entity_enterprise_key  STRING,
    is_active                     BOOLEAN,
    address_line                  STRING,
    city                          STRING,
    state_region                  STRING,
    country                       STRING,
    has_contracts                 BOOLEAN      COMMENT 'TRUE if at least one efront contract references this entity',
    _source_pref                  STRING       NOT NULL,
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'Bronze unified entity. Aspen master + efront-derived has_contracts flag.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.3 t_vasset (single-source: aspen) -----------------------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vasset (
    enterprise_key                STRING       NOT NULL,
    asset_name                    STRING,
    asset_type                    STRING,
    asset_class                   STRING,
    country                       STRING,
    region                        STRING,
    vintage_year                  INT,
    total_size_local              DECIMAL(18, 2),
    currency_code                 STRING,
    ownership_pct                 DECIMAL(10, 6),
    manager_name                  STRING,
    status                        STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'aspen',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'Bronze unified asset (real estate / infra / specialty). Aspen sole source.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.4 t_vportfolio (multi-source: aladdin + efront) ---------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vportfolio (
    enterprise_key                STRING       NOT NULL,
    portfolio_name                STRING,
    portfolio_name_source         STRING,
    strategy_name                 STRING,
    strategy_name_source          STRING,
    latest_capital_activity_date  DATE         COMMENT 'From efront if any',
    total_capital_called          DECIMAL(18, 2),
    total_distributed             DECIMAL(18, 2),
    _source_pref                  STRING       NOT NULL,
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'Bronze unified portfolio. Aladdin master + efront capital activity rollup.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.5 t_vcontract (single-source: efront) -------------------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vcontract (
    enterprise_key                STRING       NOT NULL,
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
    _source_pref                  STRING       NOT NULL DEFAULT 'efront',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'Bronze unified contract. eFront sole source.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.6 t_vbusiness_unit (multi-source: internal_admin + aladdin overlay) -------
CREATE TABLE IF NOT EXISTS bronze.t_vbusiness_unit (
    enterprise_key                STRING       NOT NULL,
    bu_code                       STRING       NOT NULL,
    bu_name                       STRING,
    bu_name_source                STRING,
    bu_type                       STRING,
    parent_bu_enterprise_key      STRING,
    asset_class_focus             STRING,
    strategy_name                 STRING,
    head_employee_id              STRING,
    established_date              DATE,
    is_active                     BOOLEAN,
    associated_risk_team_codes    ARRAY<STRING> COMMENT 'From aladdin compliance_check.risk_team_code',
    _source_pref                  STRING       NOT NULL,
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key)
COMMENT 'Bronze unified business unit. internal_admin master + aladdin risk-team overlay.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- ============================================================================
-- FACT-SHAPED TABLES (cluster by enterprise_key + date col)
-- ============================================================================

-- 3.7 t_vposition (single-source: state_street) -------------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vposition (
    enterprise_key                STRING       NOT NULL,
    position_date                 DATE         NOT NULL,
    portfolio_enterprise_key      STRING,
    security_enterprise_key       STRING,
    quantity                      DECIMAL(18, 4),
    market_value_local            DECIMAL(18, 2),
    book_value_local              DECIMAL(18, 2),
    cost_basis_local              DECIMAL(18, 2),
    unrealized_gl_local           DECIMAL(18, 2),
    unit_price_local              DECIMAL(18, 6),
    currency_code                 STRING,
    settlement_status             STRING,
    custodian_account             STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'state_street',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, position_date)
COMMENT 'Bronze position fact. State Street custodian sole source.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.8 t_vtransaction (multi-source: state_street + aladdin trade_blotter) -----
CREATE TABLE IF NOT EXISTS bronze.t_vtransaction (
    enterprise_key                STRING       NOT NULL,
    transaction_date              DATE         NOT NULL,
    settlement_date               DATE,
    portfolio_enterprise_key      STRING,
    security_enterprise_key       STRING,
    transaction_type              STRING,
    transaction_type_source       STRING,
    quantity                      DECIMAL(18, 4),
    price_local                   DECIMAL(18, 4),
    gross_amount_local            DECIMAL(18, 2),
    fees_local                    DECIMAL(18, 2),
    net_amount_local              DECIMAL(18, 2),
    currency_code                 STRING,
    counterparty_name             STRING,
    custodian_account             STRING,
    trade_status                  STRING       COMMENT 'NULL for state_street settled rows; PENDING/EXECUTED/CANCELLED for aladdin in-flight',
    _source_pref                  STRING       NOT NULL,
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, transaction_date)
COMMENT 'Bronze transaction fact. State_street settled + aladdin in-flight overlay.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.9 t_vsecurity_price (single-source: state_street) -------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vsecurity_price (
    enterprise_key                STRING       NOT NULL,
    security_enterprise_key       STRING,
    price_date                    DATE         NOT NULL,
    close_price_local             DECIMAL(18, 6),
    currency_code                 STRING,
    price_type                    STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'state_street',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, price_date)
COMMENT 'Bronze security price. State Street EOD close prices for held securities.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.10 t_vportfolio_risk (single-source: aladdin) -----------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vportfolio_risk (
    enterprise_key                STRING       NOT NULL,
    portfolio_enterprise_key      STRING,
    risk_date                     DATE         NOT NULL,
    var_95                        DECIMAL(18, 6),
    var_99                        DECIMAL(18, 6),
    expected_shortfall            DECIMAL(18, 6),
    beta                          DECIMAL(8, 4),
    tracking_error                DECIMAL(8, 4),
    risk_currency                 STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'aladdin',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, risk_date)
COMMENT 'Bronze portfolio risk metrics from Aladdin.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.11 t_vportfolio_performance (single-source: aladdin) ----------------------
CREATE TABLE IF NOT EXISTS bronze.t_vportfolio_performance (
    enterprise_key                STRING       NOT NULL,
    portfolio_enterprise_key      STRING,
    performance_date              DATE         NOT NULL,
    period_return_pct             DECIMAL(10, 6),
    ytd_return_pct                DECIMAL(10, 6),
    since_inception_return_pct    DECIMAL(10, 6),
    benchmark_return_pct          DECIMAL(10, 6),
    benchmark_code                STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'aladdin',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, performance_date)
COMMENT 'Bronze portfolio performance from Aladdin.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.12 t_vrating (single-source: aspen, security + entity ratings UNIONed) ---
CREATE TABLE IF NOT EXISTS bronze.t_vrating (
    enterprise_key                STRING       NOT NULL,
    rated_object_enterprise_key   STRING,
    rated_object_type             STRING       COMMENT 'SECURITY | ENTITY',
    rating_date                   DATE         NOT NULL,
    rating_agency                 STRING,
    rating_value                  STRING,
    rating_outlook                STRING,
    rating_action_type            STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'aspen',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, rating_date)
COMMENT 'Bronze ratings (security + entity unified). Aspen sole source; rated_object_type discriminates.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.13 t_vcollateral (single-source: efront) ----------------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vcollateral (
    enterprise_key                STRING       NOT NULL,
    contract_enterprise_key       STRING,
    exposure_date                 DATE         NOT NULL,
    exposure_amount_local         DECIMAL(18, 2),
    currency_code                 STRING,
    collateral_type               STRING,
    collateral_value_local        DECIMAL(18, 2),
    ltv_pct                       DECIMAL(10, 6),
    _source_pref                  STRING       NOT NULL DEFAULT 'efront',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (enterprise_key, exposure_date)
COMMENT 'Bronze collateral exposure (per contract per date). eFront sole source.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

-- 3.14 t_vfx_rate (single-source: bloomberg) ----------------------------------
CREATE TABLE IF NOT EXISTS bronze.t_vfx_rate (
    enterprise_key                STRING       NOT NULL,
    from_currency                 STRING       NOT NULL,
    to_currency                   STRING       NOT NULL,
    rate_date                     DATE         NOT NULL,
    fx_rate                       DECIMAL(18, 8),
    rate_type                     STRING,
    _source_pref                  STRING       NOT NULL DEFAULT 'bloomberg',
    _sources_in_conflict          ARRAY<STRING>,
    bronze_loaded_at              TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (from_currency, to_currency, rate_date)
COMMENT 'Bronze FX rates from Bloomberg. Drives silver currency normalization.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking' = 'true',
    'delta.enableChangeDataFeed' = 'true'
);

SELECT 'bronze.tables complete' AS status,
       count(*) AS bronze_table_count
FROM information_schema.tables
WHERE table_schema = 'bronze'
  AND table_name LIKE 't_v%';
