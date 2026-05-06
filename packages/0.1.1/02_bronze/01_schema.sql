-- ============================================================================
-- 02_bronze/01_schema.sql
-- Single bronze schema. Houses the crosswalk + 14 unified entity artifacts
-- (t_<entity> + v<entity> + mv<entity>).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE SCHEMA IF NOT EXISTS bronze
    COMMENT 'Bronze layer: per-entity unification across the 6 source systems with precedence + provenance. First level of business logic (source_key -> enterprise_key bridging, basic transforms).';

SELECT 'bronze.schema complete' AS status;
