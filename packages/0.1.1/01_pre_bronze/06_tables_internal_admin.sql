-- ============================================================================
-- 01_pre_bronze/06_tables_internal_admin.sql
-- Internal org/HR source. 3 raw tables.
--
-- Lineage source for vbusiness_unit_dim (decision #2). Primary source is
-- business_unit_master_raw; aladdin.compliance_check_raw provides a
-- risk-team-membership overlay (decision #7).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 6.1 BUSINESS UNIT MASTER ----------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_internal_admin.business_unit_master_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    bu_code                   STRING       NOT NULL COMMENT 'team_pd_direct_lending / team_pd_distressed / team_re_core / etc.',
    bu_name                   STRING,
    bu_type                   STRING       COMMENT 'INVESTMENT_TEAM / OPERATIONS / RISK / COMPLIANCE',
    parent_bu_code            STRING       COMMENT 'Parent business unit for hierarchy',
    asset_class_focus         STRING       COMMENT 'Free-text strategy descriptor',
    strategy_name             STRING,
    head_employee_id          STRING,
    established_date          DATE,
    is_active                 BOOLEAN,
    record_source             STRING       NOT NULL DEFAULT 'internal_admin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Business unit / team master. Drives 10-team registry in vbusiness_unit_dim.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 6.2 BUSINESS UNIT MEMBERSHIP ------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_internal_admin.business_unit_membership_raw (
    source_key                STRING       NOT NULL COMMENT 'Composite: bu_code + employee_id + start_date',
    enterprise_key            STRING       NOT NULL,
    bu_code                   STRING       NOT NULL,
    employee_id               STRING       NOT NULL,
    role                      STRING       COMMENT 'HEAD / SENIOR / MID / JUNIOR / SUPPORT',
    start_date                DATE         NOT NULL,
    end_date                  DATE         COMMENT 'NULL = active',
    is_active                 BOOLEAN,
    record_source             STRING       NOT NULL DEFAULT 'internal_admin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Many-to-many: which employees are on which business unit, when.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- 6.3 EMPLOYEE ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_internal_admin.employee_raw (
    source_key                STRING       NOT NULL,
    enterprise_key            STRING       NOT NULL,
    employee_id               STRING       NOT NULL,
    full_name                 STRING,
    email                     STRING,
    hire_date                 DATE,
    termination_date          DATE,
    department                STRING,
    title                     STRING,
    record_source             STRING       NOT NULL DEFAULT 'internal_admin',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Employee directory.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

SELECT 'pre_bronze.internal_admin.tables complete' AS status, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'raw_internal_admin';
