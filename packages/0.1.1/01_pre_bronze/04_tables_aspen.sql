-- ============================================================================
-- 01_pre_bronze/04_tables_aspen.sql
-- Internal research / management source (Aspen). 7 raw tables.
--
-- Aspen is treated as default source-of-truth for master attributes (entity,
-- security, asset masters; ratings; industry classifications). Per user, this
-- isn't absolute — holes exist where other sources have data Aspen lacks.
-- See DECISIONS.md #3 for precedence rules.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 4.1 ENTITY MASTER -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.entity_master_raw (
    source_key                STRING       NOT NULL COMMENT 'Aspen entity_id',
    enterprise_key            STRING       NOT NULL,
    entity_name               STRING,
    entity_type               STRING       COMMENT 'CORPORATE / FUND / SPV / INDIVIDUAL / TRUST',
    legal_structure           STRING       COMMENT 'LLC / LP / Inc / Trust / Other',
    jurisdiction              STRING,
    tax_id                    STRING,
    formation_date            DATE,
    dissolution_date          DATE,
    parent_entity_source_key  STRING,
    is_active                 BOOLEAN,
    address_line              STRING,
    city                      STRING,
    state_region              STRING,
    country                   STRING       COMMENT 'ISO-3 (USA, CAN, GBR, DEU, JPN, ...)',
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Entity master. Default source-of-truth for entity attributes; eFront fills in PD-specific entities Aspen lacks.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 4.2 SECURITY MASTER ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.security_master_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    security_name             STRING,
    security_type             STRING       COMMENT 'EQUITY / SENIOR_DEBT / SUBORD_DEBT / PREFERRED / WARRANT / CONVERTIBLE',
    asset_class               STRING       COMMENT 'PUBLIC_EQUITY / PRIVATE_EQUITY / SENIOR_DEBT / MEZZ / DISTRESSED / RE_DEBT / SPECIALTY',
    sub_asset_class           STRING,
    issue_date                DATE,
    maturity_date             DATE,
    coupon_rate               DECIMAL(10, 6),
    currency_code             STRING,
    issuer_source_key         STRING       COMMENT 'Aspen entity_id of issuer',
    isin_code                 STRING,
    cusip_code                STRING,
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Security master. Aspen primary; state_street provides prices via security_price_raw.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 4.3 ASSET MASTER ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.asset_master_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    asset_name                STRING,
    asset_type                STRING       COMMENT 'OFFICE / RETAIL / INDUSTRIAL / MULTIFAMILY / HOTEL / INFRA / OTHER',
    asset_class               STRING,
    country                   STRING,
    region                    STRING,
    vintage_year              INT,
    total_size_local          DECIMAL(18, 2),
    currency_code             STRING,
    ownership_pct             DECIMAL(10, 6),
    manager_name              STRING,
    status                    STRING       COMMENT 'ACQUIRED / DEVELOPING / OPERATING / DIVESTED',
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Real-asset master (real estate / infrastructure / specialty).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 4.4 ENTITY RATING -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.entity_rating_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    entity_source_key         STRING       NOT NULL,
    rating_date               DATE         NOT NULL,
    rating_agency             STRING       COMMENT 'MOODY / SP / FITCH / INTERNAL',
    rating_value              STRING       COMMENT 'AAA / AA+ / AA / ... / D',
    rating_outlook            STRING       COMMENT 'POSITIVE / STABLE / NEGATIVE / WATCH',
    rating_action_type        STRING       COMMENT 'INITIAL / UPGRADE / DOWNGRADE / AFFIRM / WITHDRAW',
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Entity-level ratings (issuer credit ratings).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 4.5 SECURITY RATING ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.security_rating_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    security_source_key       STRING       NOT NULL,
    rating_date               DATE         NOT NULL,
    rating_agency             STRING,
    rating_value              STRING,
    rating_outlook            STRING,
    rating_action_type        STRING,
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Instrument-level ratings.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 4.6 INDUSTRY CLASSIFICATION -------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.industry_classification_raw (
    source_key                STRING       NOT NULL COMMENT 'Composite: classification_system + classification_code',
    enterprise_key            STRING       NOT NULL,
    classification_code       STRING       NOT NULL,
    classification_name       STRING,
    parent_code               STRING,
    classification_level      INT          COMMENT '1=sector, 2=industry-group, 3=industry, 4=sub-industry',
    classification_system     STRING       COMMENT 'GICS / NAICS / ICB / INTERNAL',
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Industry hierarchy. Multi-level: sector → industry-group → industry → sub-industry.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 4.7 REPORTING GROUP ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_aspen.reporting_group_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    group_code                STRING       NOT NULL,
    group_name                STRING,
    parent_group_code         STRING,
    group_level               INT,
    group_type                STRING       COMMENT 'STRATEGY / GEOGRAPHY / STRUCTURE / RISK',
    record_source             STRING       NOT NULL DEFAULT 'aspen',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Custom reporting groups (strategy, geography, structure, risk roll-ups).'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

SELECT 'pre_bronze.aspen.tables complete' AS status, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'raw_aspen';
