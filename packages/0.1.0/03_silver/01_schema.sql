-- ============================================================================
-- 03_silver/01_schema.sql
-- The `investments` schema. Naming matches user's enterprise convention.
--
-- Houses ~23 silver entities (8 SCD2 dims, 1 type-2-lite FX-rate dim, 8 facts,
-- 3 cancel siblings, 2 monthend siblings, ~1 bridge). Each has t_<entity>
-- table + v<entity> view + mv<entity> MV.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE SCHEMA IF NOT EXISTS investments
    COMMENT 'Silver layer (`investments`). SCD2 dims with preceding/succeeding chains; facts with temporal-resolution joins to dim_sk; currency-normalized USD companion columns; cancel-aware aggregates. Sources from bronze.v*, falling back to pre-bronze raw_* for SCD2 chain reconstruction.';

SELECT 'silver.schema complete' AS status;
