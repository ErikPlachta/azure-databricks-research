-- ============================================================================
-- BRIDGE FRAMEWORK — Functions and Views
-- 
-- Run after 01_ddl_schema_tables.sql.
--
-- Translation notes:
--   * T-SQL scalar functions → Databricks SQL UDFs (RETURNS <scalar> RETURN ...).
--   * T-SQL TVFs returning @results TABLE → Databricks SQL UDFs with
--     RETURNS TABLE (...) RETURN <query>. Body is a single query expression.
--   * Fix applied: scalar key resolution now adds an explicit
--     ORDER BY crosswalk_sk DESC LIMIT 1 to make the result deterministic
--     when there are multiple is_current=true rows. The DDL doesn't enforce
--     uniqueness, so this guard matters.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- SECTION 1: CROSSWALK RESOLUTION FUNCTIONS
-- ============================================================================

-- 1.1 Resolve current source key → target key (scalar)
CREATE OR REPLACE FUNCTION bridge.fn_resolve_key_current(
    p_domain_code STRING,
    p_source_code STRING,
    p_source_key  STRING,
    p_target_code STRING
)
RETURNS STRING
COMMENT 'Resolves a source key to its current target key. Returns NULL if no mapping.'
RETURN (
    SELECT kc.target_key
    FROM bridge.key_crosswalk kc
    JOIN bridge.key_domain     kd  ON kc.domain_id        = kd.domain_id
    JOIN bridge.source_registry src ON kc.source_system_id = src.source_id
    JOIN bridge.source_registry tgt ON kc.target_system_id = tgt.source_id
    WHERE kd.domain_code  = p_domain_code
      AND src.source_code = p_source_code
      AND kc.source_key   = p_source_key
      AND tgt.source_code = p_target_code
      AND kc.is_current   = TRUE
    ORDER BY kc.crosswalk_sk DESC
    LIMIT 1
);

-- 1.2 Resolve source key → target key as of a historical date (scalar)
CREATE OR REPLACE FUNCTION bridge.fn_resolve_key_as_of(
    p_domain_code STRING,
    p_source_code STRING,
    p_source_key  STRING,
    p_target_code STRING,
    p_as_of_date  DATE
)
RETURNS STRING
COMMENT 'Resolves a source key to its target key as of a specific historical date.'
RETURN (
    SELECT kc.target_key
    FROM bridge.key_crosswalk kc
    JOIN bridge.key_domain     kd  ON kc.domain_id        = kd.domain_id
    JOIN bridge.source_registry src ON kc.source_system_id = src.source_id
    JOIN bridge.source_registry tgt ON kc.target_system_id = tgt.source_id
    WHERE kd.domain_code  = p_domain_code
      AND src.source_code = p_source_code
      AND kc.source_key   = p_source_key
      AND tgt.source_code = p_target_code
      AND p_as_of_date >= kc.effective_start_date
      AND (p_as_of_date <= kc.effective_end_date OR kc.effective_end_date IS NULL)
    ORDER BY kc.crosswalk_sk DESC
    LIMIT 1
);

-- 1.3 All target keys for a source key (TVF — handles ONE_TO_MANY splits)
CREATE OR REPLACE FUNCTION bridge.fn_resolve_key_all_targets(
    p_domain_code STRING,
    p_source_code STRING,
    p_source_key  STRING,
    p_target_code STRING
)
RETURNS TABLE (
    target_key        STRING,
    split_sequence    INT,
    split_description STRING,
    relationship_type STRING
)
COMMENT 'Returns all target keys for a source key. Useful for ONE_TO_MANY splits.'
RETURN
    SELECT
        kc.target_key,
        kc.split_sequence,
        kc.split_description,
        kc.relationship_type
    FROM bridge.key_crosswalk kc
    JOIN bridge.key_domain     kd  ON kc.domain_id        = kd.domain_id
    JOIN bridge.source_registry src ON kc.source_system_id = src.source_id
    JOIN bridge.source_registry tgt ON kc.target_system_id = tgt.source_id
    WHERE kd.domain_code  = p_domain_code
      AND src.source_code = p_source_code
      AND kc.source_key   = p_source_key
      AND tgt.source_code = p_target_code
      AND kc.is_current   = TRUE
    ORDER BY kc.split_sequence;

-- 1.4 All source keys for a target key (TVF — handles MANY_TO_ONE consolidation)
CREATE OR REPLACE FUNCTION bridge.fn_resolve_key_all_sources(
    p_domain_code STRING,
    p_target_code STRING,
    p_target_key  STRING,
    p_source_code STRING
)
RETURNS TABLE (
    source_key        STRING,
    relationship_type STRING
)
COMMENT 'Returns all source keys mapping to a target key. Useful for MANY_TO_ONE.'
RETURN
    SELECT
        kc.source_key,
        kc.relationship_type
    FROM bridge.key_crosswalk kc
    JOIN bridge.key_domain     kd  ON kc.domain_id        = kd.domain_id
    JOIN bridge.source_registry src ON kc.source_system_id = src.source_id
    JOIN bridge.source_registry tgt ON kc.target_system_id = tgt.source_id
    WHERE kd.domain_code  = p_domain_code
      AND tgt.source_code = p_target_code
      AND kc.target_key   = p_target_key
      AND src.source_code = p_source_code
      AND kc.is_current   = TRUE;

-- ============================================================================
-- SECTION 2: DIMENSION LOOKUP VIEWS
-- ============================================================================

-- Current entity with relevant external keys (State Street, Bloomberg)
CREATE OR REPLACE VIEW dim.vw_entity_current AS
SELECT
    e.entity_sk,
    e.enterprise_entity_id,
    e.entity_name,
    e.entity_type,
    e.legal_structure,
    e.jurisdiction,
    p.enterprise_portfolio_id,
    p.portfolio_name,
    ss.source_key  AS state_street_id,
    bbg.source_key AS bloomberg_id
FROM dim.entity e
LEFT JOIN dim.portfolio p
       ON e.portfolio_sk = p.portfolio_sk
      AND p.is_current = TRUE
LEFT JOIN bridge.key_crosswalk ss
       ON ss.target_key       = e.enterprise_entity_id
      AND ss.is_current        = TRUE
      AND ss.source_system_id  = (SELECT source_id FROM bridge.source_registry WHERE source_code = 'STATE_STREET')
      AND ss.domain_id         = (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'ENTITY')
LEFT JOIN bridge.key_crosswalk bbg
       ON bbg.target_key       = e.enterprise_entity_id
      AND bbg.is_current       = TRUE
      AND bbg.source_system_id = (SELECT source_id FROM bridge.source_registry WHERE source_code = 'BLOOMBERG')
      AND bbg.domain_id        = (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'ENTITY')
WHERE e.is_current = TRUE;

-- Current portfolio with hierarchy
CREATE OR REPLACE VIEW dim.vw_portfolio_hierarchy_current AS
SELECT
    p.portfolio_sk,
    p.enterprise_portfolio_id,
    p.portfolio_name,
    p.portfolio_type,
    pg.enterprise_portfolio_group_id,
    pg.group_name AS portfolio_group_name,
    pg.strategy
FROM dim.portfolio p
LEFT JOIN dim.portfolio_group pg
       ON p.portfolio_group_sk = pg.portfolio_group_sk
      AND pg.is_current = TRUE
WHERE p.is_current = TRUE;

-- Current security with asset linkage
CREATE OR REPLACE VIEW dim.vw_security_with_asset AS
SELECT
    s.security_sk,
    s.enterprise_security_id,
    s.security_name,
    s.security_type,
    s.cusip,
    s.isin,
    a.enterprise_asset_id,
    a.asset_name,
    a.asset_type,
    a.city,
    a.state_province,
    dg.group_name AS managing_team
FROM dim.security s
LEFT JOIN dim.asset a
       ON s.asset_sk = a.asset_sk
      AND a.is_current = TRUE
LEFT JOIN dim.department_group dg
       ON a.managing_group_id = dg.group_id
WHERE s.is_current = TRUE;

SELECT 'Functions and views created successfully.' AS status;
