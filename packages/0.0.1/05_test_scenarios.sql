-- ============================================================================
-- BRIDGE FRAMEWORK — Test Scenarios
--
-- Run after 04_seed_data.sql. Validates the framework end-to-end.
--
-- Translation notes:
--   * EXEC proc → CALL proc.
--   * @-params → named params on CALL (or positional).
--   * PRINT → SELECT (output appears in result panes).
--   * Sequential validation queries; each cell shows results.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- PREREQUISITE
-- ============================================================================
-- Run 04_seed_data.sql first. That file ends with a CALL that seeds the
-- framework using the current session variable values (default: 20-year
-- position window, SCD2 history on).
--
-- To re-seed with different parameters from this file, run:
--   SET VARIABLE position_start_date = DATE'2010-01-01';
--   SET VARIABLE position_end_date   = DATE'2024-12-31';
--   CALL bridge.usp_reset_setup_seed_data(
--       p_position_start_date => position_start_date,
--       p_position_end_date   => position_end_date,
--       p_simulate_history    => simulate_history,
--       p_skip_positions      => skip_positions
--   );

-- ============================================================================
-- TEST 1: Source Registry
-- ============================================================================
SELECT '=== TEST 1: Source Registry ===' AS test;

SELECT source_code, source_name, source_type, connection_type, refresh_frequency
FROM bridge.source_registry
WHERE is_active = TRUE
ORDER BY source_type, source_code;

-- ============================================================================
-- TEST 2: Key Domains
-- ============================================================================
SELECT '=== TEST 2: Key Domains ===' AS test;

SELECT
    domain_code,
    domain_name,
    concat(dimension_schema, '.', dimension_table) AS dimension_table,
    dimension_key_column
FROM bridge.key_domain
WHERE is_active = TRUE;

-- ============================================================================
-- TEST 3: Dimension Counts
-- ============================================================================
SELECT '=== TEST 3: Dimension Counts ===' AS test;

SELECT 'investors'        AS entity_type, COUNT(*) AS row_count FROM dim.investor        WHERE is_current = TRUE
UNION ALL SELECT 'portfolio_groups',      COUNT(*) FROM dim.portfolio_group WHERE is_current = TRUE
UNION ALL SELECT 'portfolios',            COUNT(*) FROM dim.portfolio       WHERE is_current = TRUE
UNION ALL SELECT 'entities',              COUNT(*) FROM dim.entity          WHERE is_current = TRUE
UNION ALL SELECT 'assets',                COUNT(*) FROM dim.asset           WHERE is_current = TRUE
UNION ALL SELECT 'securities',            COUNT(*) FROM dim.security        WHERE is_current = TRUE
UNION ALL SELECT 'crosswalk_mappings',    COUNT(*) FROM bridge.key_crosswalk WHERE is_current = TRUE
UNION ALL SELECT 'positions',             COUNT(*) FROM fact.position
UNION ALL SELECT 'investor_pg_alloc',     COUNT(*) FROM bridge.investor_portfolio_group_alloc
UNION ALL SELECT 'pg_portfolio_alloc',    COUNT(*) FROM bridge.portfolio_group_portfolio_alloc
UNION ALL SELECT 'portfolio_entity_alloc',COUNT(*) FROM bridge.portfolio_entity_alloc;

-- ============================================================================
-- TEST 4: Crosswalk Resolution (current)
-- ============================================================================
SELECT '=== TEST 4: Resolve a State Street entity ID to Enterprise ===' AS test;

-- Pick the first State Street entity mapping, resolve it
WITH sample AS (
    SELECT source_key
    FROM bridge.key_crosswalk kc
    JOIN bridge.source_registry sr ON kc.source_system_id = sr.source_id
    JOIN bridge.key_domain      kd ON kc.domain_id        = kd.domain_id
    WHERE sr.source_code = 'STATE_STREET'
      AND kd.domain_code = 'ENTITY'
      AND kc.relationship_type = 'ONE_TO_ONE'
      AND kc.is_current = TRUE
    ORDER BY kc.crosswalk_sk
    LIMIT 1
)
SELECT
    s.source_key                                                       AS state_street_id,
    bridge.fn_resolve_key_current('ENTITY','STATE_STREET',s.source_key,'ENTERPRISE') AS enterprise_id
FROM sample s;

-- ============================================================================
-- TEST 5: ONE_TO_MANY split — Bloomberg mixed-use → multiple enterprise targets
-- ============================================================================
SELECT '=== TEST 5: ONE_TO_MANY targets ===' AS test;

-- Find a BBG_MIXED_USE source key
WITH sample AS (
    SELECT source_key
    FROM bridge.key_crosswalk kc
    WHERE kc.relationship_type = 'ONE_TO_MANY'
      AND kc.source_key LIKE 'BBG_MIXED_USE_%'
      AND kc.is_current = TRUE
    GROUP BY source_key
    ORDER BY source_key
    LIMIT 1
)
SELECT t.*
FROM sample s,
     LATERAL bridge.fn_resolve_key_all_targets('ENTITY','BLOOMBERG',s.source_key,'ENTERPRISE') AS t;

-- Note: SQL UDF table functions use ANSI LATERAL join syntax (not Hive's
-- LATERAL VIEW, which is for explode-style generators only).
-- Alternative call style with literal arg:
-- SELECT * FROM bridge.fn_resolve_key_all_targets('ENTITY','BLOOMBERG','BBG_MIXED_USE_0','ENTERPRISE');

-- ============================================================================
-- TEST 6: MANY_TO_ONE consolidation — multiple State Street → one enterprise
-- ============================================================================
SELECT '=== TEST 6: MANY_TO_ONE sources ===' AS test;

WITH sample AS (
    SELECT target_key
    FROM bridge.key_crosswalk kc
    WHERE kc.relationship_type = 'MANY_TO_ONE'
      AND kc.is_current = TRUE
    GROUP BY target_key
    ORDER BY target_key
    LIMIT 1
)
SELECT t.*
FROM sample s,
     LATERAL bridge.fn_resolve_key_all_sources('ENTITY','ENTERPRISE',s.target_key,'STATE_STREET') AS t;

-- ============================================================================
-- TEST 7: Entity view with external keys (vw_entity_current)
-- ============================================================================
SELECT '=== TEST 7: vw_entity_current sample ===' AS test;

SELECT
    enterprise_entity_id,
    entity_name,
    entity_type,
    state_street_id,
    bloomberg_id
FROM dim.vw_entity_current
ORDER BY enterprise_entity_id
LIMIT 20;

-- ============================================================================
-- TEST 8: Position fact sanity — date span, totals, distribution
-- ============================================================================
SELECT '=== TEST 8: Position summary ===' AS test;

SELECT
    MIN(position_date)             AS earliest_date,
    MAX(position_date)             AS latest_date,
    COUNT(DISTINCT position_date)  AS distinct_dates,
    COUNT(*)                       AS total_rows,
    ROUND(SUM(market_value), 2)    AS total_market_value,
    ROUND(AVG(market_value), 2)    AS avg_market_value
FROM fact.position;

-- ============================================================================
-- TEST 9: Add a new mapping, then update it (SCD2 chain)
-- ============================================================================
SELECT '=== TEST 9: Add then update a mapping ===' AS test;

-- Idempotency: this test mutates state by inserting SS_ENT_TEST_999 rows.
-- A second run would collide with the existing is_current=TRUE row and trip
-- the proc's "current mapping already exists" SIGNAL. Wipe TEST_999's chain
-- first so the test can be re-run any number of times. Direct DELETE is fine
-- here — TEST_999 is purely a test artifact, no production-history concerns.
DELETE FROM bridge.key_crosswalk WHERE source_key = 'SS_ENT_TEST_999';

-- Add a new mapping
CALL bridge.usp_add_crosswalk_mapping(
    p_domain_code       => 'ENTITY',
    p_source_code       => 'STATE_STREET',
    p_source_key        => 'SS_ENT_TEST_999',
    p_target_code       => 'ENTERPRISE',
    p_target_key        => 'enterprise_entity_TEST_A',
    p_relationship_type => 'ONE_TO_ONE'
);

-- Verify it resolves
SELECT bridge.fn_resolve_key_current('ENTITY','STATE_STREET','SS_ENT_TEST_999','ENTERPRISE') AS resolved_now;

-- Supersede it with a new target. We omit p_new_relationship_type and
-- p_effective_date — both have DEFAULT values in the proc, and Databricks
-- CALL only handles trailing-omitted defaults cleanly. (Mid-list omissions
-- with named args trigger 'number of args and params must match after binding'.)
CALL bridge.usp_update_crosswalk_mapping(
    p_domain_code    => 'ENTITY',
    p_source_code    => 'STATE_STREET',
    p_source_key     => 'SS_ENT_TEST_999',
    p_target_code    => 'ENTERPRISE',
    p_new_target_key => 'enterprise_entity_TEST_B'
);

-- Verify new resolution
SELECT bridge.fn_resolve_key_current('ENTITY','STATE_STREET','SS_ENT_TEST_999','ENTERPRISE') AS resolved_after_update;

-- Inspect the SCD2 chain
SELECT
    crosswalk_sk,
    target_key,
    is_current,
    effective_start_date,
    effective_end_date,
    preceding_record_sk,
    succeeding_record_sk
FROM bridge.key_crosswalk
WHERE source_key = 'SS_ENT_TEST_999'
ORDER BY crosswalk_sk;

-- ============================================================================
-- TEST 10: Allocation tables sanity check
-- ============================================================================
SELECT '=== TEST 10: Allocation distributions ===' AS test;

-- Investors per portfolio group
SELECT
    pg.group_name,
    COUNT(DISTINCT alloc.investor_sk)        AS investors_in_group,
    ROUND(SUM(alloc.ownership_percentage),2) AS total_pct_committed
FROM dim.portfolio_group pg
LEFT JOIN bridge.investor_portfolio_group_alloc alloc
    ON pg.portfolio_group_sk = alloc.portfolio_group_sk
   AND alloc.is_current = TRUE
WHERE pg.is_current = TRUE
GROUP BY pg.group_name
ORDER BY pg.group_name;

-- Entity ownership distribution
SELECT
    ownership_percentage,
    COUNT(*) AS entity_count
FROM bridge.portfolio_entity_alloc
WHERE is_current = TRUE
GROUP BY ownership_percentage
ORDER BY ownership_percentage;
