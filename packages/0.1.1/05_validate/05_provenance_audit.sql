-- ============================================================================
-- 05_validate/05_provenance_audit.sql
-- Bronze provenance audit. Decision #3 enforces per-entity precedence with
-- _source_pref and _sources_in_conflict columns; bronze.bronze_lineage_audit
-- (defined in 02_bronze/07_lineage_audit.sql) summarizes per-source row
-- contributions per entity.
--
-- PASS criteria:
--   * Every bronze entity has rows from each non-skipped expected source.
--   * No entity is empty.
--   * _sources_in_conflict counts are bounded (high values indicate
--     precedence rule mismatch).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Lineage audit summary ───────────────────────────────────────────────
SELECT * FROM bronze.bronze_lineage_audit ORDER BY entity;

-- ── 2. No entity is empty ──────────────────────────────────────────────────
WITH entity_counts AS (
    SELECT 'vsecurity'          AS entity, count(*) AS n FROM bronze.vsecurity
    UNION ALL SELECT 'ventity',           count(*) FROM bronze.ventity
    UNION ALL SELECT 'vasset',            count(*) FROM bronze.vasset
    UNION ALL SELECT 'vportfolio',        count(*) FROM bronze.vportfolio
    UNION ALL SELECT 'vcontract',         count(*) FROM bronze.vcontract
    UNION ALL SELECT 'vbusiness_unit',    count(*) FROM bronze.vbusiness_unit
    UNION ALL SELECT 'vposition',         count(*) FROM bronze.vposition
    UNION ALL SELECT 'vtransaction',      count(*) FROM bronze.vtransaction
    UNION ALL SELECT 'vsecurity_price',   count(*) FROM bronze.vsecurity_price
    UNION ALL SELECT 'vfx_rate',          count(*) FROM bronze.vfx_rate
)
SELECT CASE WHEN min(n) > 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       min(n) AS min_entity_rows,
       'every bronze entity has >0 rows' AS expected
FROM entity_counts;

-- Per-entity counts for visibility
WITH entity_counts AS (
    SELECT 'vsecurity'          AS entity, count(*) AS n FROM bronze.vsecurity
    UNION ALL SELECT 'ventity',           count(*) FROM bronze.ventity
    UNION ALL SELECT 'vasset',            count(*) FROM bronze.vasset
    UNION ALL SELECT 'vportfolio',        count(*) FROM bronze.vportfolio
    UNION ALL SELECT 'vcontract',         count(*) FROM bronze.vcontract
    UNION ALL SELECT 'vbusiness_unit',    count(*) FROM bronze.vbusiness_unit
    UNION ALL SELECT 'vposition',         count(*) FROM bronze.vposition
    UNION ALL SELECT 'vtransaction',      count(*) FROM bronze.vtransaction
    UNION ALL SELECT 'vsecurity_price',   count(*) FROM bronze.vsecurity_price
    UNION ALL SELECT 'vfx_rate',          count(*) FROM bronze.vfx_rate
)
SELECT * FROM entity_counts ORDER BY n;

-- ── 3. Conflict density check (sample: vsecurity) ──────────────────────────
WITH conflict_density AS (
    SELECT
        count(*) AS total,
        sum(CASE WHEN cardinality(_sources_in_conflict) > 0 THEN 1 ELSE 0 END) AS conflict_rows,
        sum(CASE WHEN cardinality(_sources_in_conflict) > 0 THEN 1 ELSE 0 END) / nullif(count(*), 0) AS conflict_pct
    FROM bronze.vsecurity
)
SELECT CASE WHEN conflict_pct < 0.5 THEN 'PASS' ELSE 'FAIL' END AS status,
       total, conflict_rows, conflict_pct,
       'sources_in_conflict density <50% in bronze.vsecurity' AS expected
FROM conflict_density;

SELECT 'provenance_audit complete' AS phase;
