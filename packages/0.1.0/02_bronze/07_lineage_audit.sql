-- ============================================================================
-- 02_bronze/07_lineage_audit.sql
-- bronze.bronze_lineage_audit — diagnostic view summarizing per-entity row
-- counts and source-contribution breakdown.
--
-- Purpose: surface holes/conflicts at runtime so misalignments show up as
-- data observations, not silent bugs. Run after bronze.refresh_all() or
-- after bronze.usp_seed_crosswalk() to verify precedence rules are
-- exercising the data (not always-aspen).
--
-- Conflict tracking (_sources_in_conflict) is currently always empty — full
-- conflict detection deferred to 0.1.1+. The "sources contributed" columns
-- below are the primary diagnostic signal in 0.1.0.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE OR REPLACE VIEW bronze.bronze_lineage_audit AS
SELECT 'vsecurity'              AS entity,
       count(*)                                                                          AS total_rows,
       SUM(CASE WHEN _source_pref LIKE 'aspen%'              THEN 1 ELSE 0 END)           AS aspen_contributed,
       SUM(CASE WHEN _source_pref LIKE '%state_street%'      THEN 1 ELSE 0 END)           AS state_street_contributed,
       SUM(CASE WHEN _source_pref LIKE '%efront%'            THEN 1 ELSE 0 END)           AS efront_contributed,
       SUM(CASE WHEN _source_pref LIKE '%aladdin%'           THEN 1 ELSE 0 END)           AS aladdin_contributed,
       SUM(CASE WHEN _source_pref LIKE '%internal_admin%'    THEN 1 ELSE 0 END)           AS internal_admin_contributed,
       SUM(CASE WHEN _source_pref LIKE '%bloomberg%'         THEN 1 ELSE 0 END)           AS bloomberg_contributed,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)           AS rows_with_conflicts
FROM bronze.vsecurity
UNION ALL
SELECT 'ventity', count(*),
       SUM(CASE WHEN _source_pref LIKE 'aspen%'              THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE '%state_street%'      THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE '%efront%'            THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE '%aladdin%'           THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE '%internal_admin%'    THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE '%bloomberg%'         THEN 1 ELSE 0 END),
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.ventity
UNION ALL
SELECT 'vasset', count(*),
       SUM(CASE WHEN _source_pref LIKE 'aspen%'              THEN 1 ELSE 0 END), 0, 0, 0, 0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vasset
UNION ALL
SELECT 'vportfolio', count(*),
       0,
       0,
       SUM(CASE WHEN _source_pref LIKE '%efront%'            THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE 'aladdin%'            THEN 1 ELSE 0 END),
       0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vportfolio
UNION ALL
SELECT 'vcontract', count(*),
       0, 0,
       SUM(CASE WHEN _source_pref LIKE 'efront%'             THEN 1 ELSE 0 END),
       0, 0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vcontract
UNION ALL
SELECT 'vbusiness_unit', count(*),
       0, 0, 0,
       SUM(CASE WHEN _source_pref LIKE '%aladdin%'           THEN 1 ELSE 0 END),
       SUM(CASE WHEN _source_pref LIKE 'internal_admin%'     THEN 1 ELSE 0 END),
       0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vbusiness_unit
UNION ALL
SELECT 'vposition', count(*),
       0,
       SUM(CASE WHEN _source_pref LIKE 'state_street%'       THEN 1 ELSE 0 END),
       0, 0, 0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vposition
UNION ALL
SELECT 'vtransaction', count(*),
       0,
       SUM(CASE WHEN _source_pref LIKE 'state_street%'       THEN 1 ELSE 0 END),
       0,
       SUM(CASE WHEN _source_pref LIKE 'aladdin%'            THEN 1 ELSE 0 END),
       0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vtransaction
UNION ALL
SELECT 'vsecurity_price', count(*),
       0,
       SUM(CASE WHEN _source_pref LIKE 'state_street%'       THEN 1 ELSE 0 END),
       0, 0, 0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vsecurity_price
UNION ALL
SELECT 'vportfolio_risk', count(*),
       0, 0, 0,
       SUM(CASE WHEN _source_pref LIKE 'aladdin%'            THEN 1 ELSE 0 END),
       0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vportfolio_risk
UNION ALL
SELECT 'vportfolio_performance', count(*),
       0, 0, 0,
       SUM(CASE WHEN _source_pref LIKE 'aladdin%'            THEN 1 ELSE 0 END),
       0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vportfolio_performance
UNION ALL
SELECT 'vrating', count(*),
       SUM(CASE WHEN _source_pref LIKE 'aspen%'              THEN 1 ELSE 0 END),
       0, 0, 0, 0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vrating
UNION ALL
SELECT 'vcollateral', count(*),
       0, 0,
       SUM(CASE WHEN _source_pref LIKE 'efront%'             THEN 1 ELSE 0 END),
       0, 0, 0,
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vcollateral
UNION ALL
SELECT 'vfx_rate', count(*),
       0, 0, 0, 0, 0,
       SUM(CASE WHEN _source_pref LIKE 'bloomberg%'          THEN 1 ELSE 0 END),
       SUM(CASE WHEN size(_sources_in_conflict) > 0          THEN 1 ELSE 0 END)
FROM bronze.vfx_rate;

SELECT 'bronze.lineage_audit complete' AS status;
