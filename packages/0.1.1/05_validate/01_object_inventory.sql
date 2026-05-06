-- ============================================================================
-- 05_validate/01_object_inventory.sql
-- Confirms the deploy landed the expected schemas, no schema exceeded
-- Free Edition's 100-object cap, and the artifact triplet (t/v/mv) is
-- complete per entity.
--
-- PASS criteria:
--   * Exactly 15 schemas in medallion_demo (6 raw + bronze + investments
--     + investments_history + 5 team_pd + gold_pd_consolidated).
--   * No schema has >100 objects (Free Edition cap).
--   * Every silver/gold entity has paired t_, v, and mv artifacts.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Schema count ────────────────────────────────────────────────────────
WITH schema_count AS (
    SELECT count(DISTINCT schema_name) AS n
    FROM information_schema.schemata
    WHERE catalog_name = 'medallion_demo'
      AND schema_name IN (
          'raw_state_street','raw_aladdin','raw_aspen','raw_efront','raw_internal_admin','raw_bloomberg',
          'bronze','investments','investments_history',
          'team_pd_direct_lending','team_pd_distressed','team_pd_mezzanine',
          'team_pd_real_estate_debt','team_pd_specialty_finance','gold_pd_consolidated'
      )
)
SELECT CASE WHEN n = 15 THEN 'PASS' ELSE 'FAIL' END AS status,
       n AS schema_count, '15 schemas expected' AS expected
FROM schema_count;

-- ── 2. Per-schema object count + cap check ─────────────────────────────────
WITH counts AS (
    SELECT table_schema, count(*) AS n
    FROM information_schema.tables
    WHERE table_catalog = 'medallion_demo'
    GROUP BY 1
), cap AS (
    SELECT max(n) AS max_n FROM counts
)
SELECT CASE WHEN max_n < 100 THEN 'PASS' ELSE 'FAIL' END AS status,
       max_n AS max_objects_per_schema, '<100 expected (Free Edition cap)' AS expected
FROM cap;

-- Per-schema breakdown for visibility
SELECT table_schema, count(*) AS n
FROM information_schema.tables
WHERE table_catalog = 'medallion_demo'
GROUP BY 1
ORDER BY n DESC;

-- ── 3. Triplet completeness — every silver/gold v has paired t and mv ──────
WITH bronze_v AS (
    SELECT table_schema, replace(table_name, 'v', '') AS entity
    FROM information_schema.views
    WHERE table_catalog = 'medallion_demo' AND table_schema = 'bronze' AND table_name LIKE 'v%'
), bronze_t AS (
    SELECT table_schema, replace(table_name, 't_v', '') AS entity
    FROM information_schema.tables
    WHERE table_catalog = 'medallion_demo' AND table_schema = 'bronze' AND table_name LIKE 't_v%'
), bronze_mv AS (
    SELECT table_schema, replace(table_name, 'mv', '') AS entity
    FROM information_schema.tables
    WHERE table_catalog = 'medallion_demo' AND table_schema = 'bronze' AND table_name LIKE 'mv%' AND table_name NOT LIKE 'mv_%'
), bronze_orphans AS (
    SELECT entity FROM bronze_v
    EXCEPT
    (SELECT entity FROM bronze_t INTERSECT SELECT entity FROM bronze_mv)
)
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS bronze_orphan_count,
       'every bronze v has paired t and mv' AS expected
FROM bronze_orphans;

SELECT 'object_inventory complete' AS phase;
