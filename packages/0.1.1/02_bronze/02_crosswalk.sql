-- ============================================================================
-- 02_bronze/02_crosswalk.sql
-- bronze.crosswalk: source_key <-> enterprise_key bridge across all 6 sources.
-- Plus 2 helper UDFs and an inline idempotent MERGE that populates from
-- pre-bronze.
--
-- The crosswalk is the foundation of bronze unification — every bronze view
-- joins a raw_*.<source_key> to its enterprise_key via this table. Even
-- single-source entities use it (uniformity > cleverness).
--
-- 0.1.0 note: previous revision wrapped the populate logic in a CREATE
-- PROCEDURE (...) AS BEGIN MERGE ... END; -- some Databricks SQL warehouses
-- reject MERGE inside SQL-Scripting compound blocks. Inlined the MERGE here
-- for portability. Re-running this file re-runs the MERGE (idempotent via
-- WHEN NOT MATCHED).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ----------------------------------------------------------------------------
-- bronze.crosswalk
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bronze.crosswalk (
    source_system          STRING       NOT NULL COMMENT 'state_street | aladdin | aspen | efront | internal_admin | bloomberg',
    source_key             STRING       NOT NULL,
    enterprise_key         STRING       NOT NULL,
    mapping_active         BOOLEAN      NOT NULL DEFAULT TRUE,
    mapping_effective_at   TIMESTAMP    NOT NULL DEFAULT current_timestamp(),
    created_at             TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
CLUSTER BY (source_system, source_key)
COMMENT 'Source<->enterprise key bridge. Populated from pre-bronze enterprise_key columns via inline MERGE below.'
TBLPROPERTIES (
    'delta.feature.allowColumnDefaults' = 'supported',
    'delta.enableRowTracking'           = 'true',
    'delta.enableChangeDataFeed'        = 'true'
);

-- ----------------------------------------------------------------------------
-- bronze.fn_resolve_enterprise_key
-- Translates (source_system, source_key) -> enterprise_key.
-- Returns NULL if no mapping (treat as orphan / data-quality flag).
-- Heavy-use UDF: every bronze.v<entity> calls it for FK resolution.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_resolve_enterprise_key(
    p_source_system STRING,
    p_source_key    STRING
)
RETURNS STRING
RETURN (
    SELECT enterprise_key
    FROM bronze.crosswalk
    WHERE source_system = p_source_system
      AND source_key    = p_source_key
      AND mapping_active = TRUE
    ORDER BY mapping_effective_at DESC
    LIMIT 1
);

-- ----------------------------------------------------------------------------
-- bronze.fn_resolve_source_keys
-- Inverse: enterprise_key -> array of (source_system, source_key) pairs.
-- Diagnostic only.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bronze.fn_resolve_source_keys(
    p_enterprise_key STRING
)
RETURNS ARRAY<STRUCT<source_system: STRING, source_key: STRING>>
RETURN (
    SELECT collect_list(named_struct('source_system', source_system, 'source_key', source_key))
    FROM bronze.crosswalk
    WHERE enterprise_key = p_enterprise_key
      AND mapping_active = TRUE
);

-- ----------------------------------------------------------------------------
-- Inline MERGE: walks every pre-bronze raw table; UPSERTs (source_system,
-- source_key, enterprise_key) into the crosswalk. Idempotent — re-runs are
-- safe (WHEN NOT MATCHED only inserts new rows).
-- ----------------------------------------------------------------------------
MERGE INTO bronze.crosswalk t
USING (
    SELECT 'state_street' AS source_system, source_key, enterprise_key FROM raw_state_street.position_raw
    UNION SELECT 'state_street',   source_key, enterprise_key FROM raw_state_street.transaction_raw
    UNION SELECT 'state_street',   source_key, enterprise_key FROM raw_state_street.security_price_raw
    UNION SELECT 'state_street',   source_key, enterprise_key FROM raw_state_street.cash_flow_raw
    UNION SELECT 'state_street',   source_key, enterprise_key FROM raw_state_street.nav_raw
    UNION SELECT 'aladdin',        source_key, enterprise_key FROM raw_aladdin.portfolio_risk_raw
    UNION SELECT 'aladdin',        source_key, enterprise_key FROM raw_aladdin.portfolio_performance_raw
    UNION SELECT 'aladdin',        source_key, enterprise_key FROM raw_aladdin.compliance_check_raw
    UNION SELECT 'aladdin',        source_key, enterprise_key FROM raw_aladdin.trade_blotter_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.entity_master_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.security_master_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.asset_master_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.entity_rating_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.security_rating_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.industry_classification_raw
    UNION SELECT 'aspen',          source_key, enterprise_key FROM raw_aspen.reporting_group_raw
    UNION SELECT 'efront',         source_key, enterprise_key FROM raw_efront.contract_raw
    UNION SELECT 'efront',         source_key, enterprise_key FROM raw_efront.contract_summary_raw
    UNION SELECT 'efront',         source_key, enterprise_key FROM raw_efront.contract_covenant_raw
    UNION SELECT 'efront',         source_key, enterprise_key FROM raw_efront.capital_activity_raw
    UNION SELECT 'efront',         source_key, enterprise_key FROM raw_efront.collateral_exposure_raw
    UNION SELECT 'efront',         source_key, enterprise_key FROM raw_efront.collateral_position_raw
    UNION SELECT 'internal_admin', source_key, enterprise_key FROM raw_internal_admin.business_unit_master_raw
    UNION SELECT 'internal_admin', source_key, enterprise_key FROM raw_internal_admin.business_unit_membership_raw
    UNION SELECT 'internal_admin', source_key, enterprise_key FROM raw_internal_admin.employee_raw
    UNION SELECT 'bloomberg',      source_key, enterprise_key FROM raw_bloomberg.fx_rate_raw
    -- ----------------------------------------------------------------------
    -- Cross-system FK arms (DECISIONS #17): the rows above only register each
    -- raw row's PRIMARY identity. But position/transaction/cash_flow/nav rows
    -- carry FK columns (portfolio_source_key, etc.) that reference an entity
    -- defined elsewhere — and no source emits those FK strings as their own
    -- source_key. Without these arms, fn_resolve_enterprise_key returns NULL
    -- for every position's portfolio FK lookup. Canonical EK derivation:
    --   'EK_' || substr('SS_PORT_TEAM_01', 4) → 'EK_PORT_TEAM_01'
    -- Same canonical EK is used by silver vportfolio_dim so the join chain
    -- from bronze through silver agrees on portfolio identity.
    -- ----------------------------------------------------------------------
    UNION SELECT DISTINCT 'state_street', portfolio_source_key, 'EK_' || substr(portfolio_source_key, 4)
        FROM raw_state_street.position_raw     WHERE portfolio_source_key IS NOT NULL
    UNION SELECT DISTINCT 'state_street', portfolio_source_key, 'EK_' || substr(portfolio_source_key, 4)
        FROM raw_state_street.transaction_raw  WHERE portfolio_source_key IS NOT NULL
    UNION SELECT DISTINCT 'state_street', portfolio_source_key, 'EK_' || substr(portfolio_source_key, 4)
        FROM raw_state_street.cash_flow_raw    WHERE portfolio_source_key IS NOT NULL
    UNION SELECT DISTINCT 'state_street', portfolio_source_key, 'EK_' || substr(portfolio_source_key, 4)
        FROM raw_state_street.nav_raw          WHERE portfolio_source_key IS NOT NULL
    UNION SELECT DISTINCT 'aladdin',      portfolio_source_key, 'EK_' || substr(portfolio_source_key, 4)
        FROM raw_aladdin.portfolio_risk_raw    WHERE portfolio_source_key IS NOT NULL
) s
ON t.source_system = s.source_system AND t.source_key = s.source_key
WHEN NOT MATCHED THEN
    INSERT (source_system, source_key, enterprise_key, mapping_active, mapping_effective_at, created_at)
    VALUES (s.source_system, s.source_key, s.enterprise_key, TRUE, current_timestamp(), current_timestamp());

SELECT 'bronze.crosswalk complete' AS status,
       (SELECT count(*) FROM bronze.crosswalk) AS crosswalk_rows,
       (SELECT count(DISTINCT source_system) FROM bronze.crosswalk) AS distinct_sources,
       (SELECT count(DISTINCT enterprise_key) FROM bronze.crosswalk) AS distinct_enterprise_keys;
