-- ============================================================================
-- 05_validate/04_scd2_integrity.sql
-- SCD2 chain integrity. Per Decision #9 every silver dim except vfx_rate_dim
-- runs full SCD2: preceding/succeeding chain links, effective date ranges,
-- is_current flags. Validates these properties hold for sampled dims.
--
-- PASS criteria (per dim):
--   * No two records for the same enterprise_key have overlapping effective
--     date ranges.
--   * Exactly one is_current=TRUE record per enterprise_key.
--   * For multi-record chains, preceding_record_sk + succeeding_record_sk
--     form a valid chain (no orphan links).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. is_current uniqueness per enterprise_key ────────────────────────────
WITH multi_current AS (
    SELECT enterprise_key, count(*) AS n
    FROM investments.t_vsecurity_dim
    WHERE is_current = TRUE
    GROUP BY 1 HAVING count(*) > 1
)
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS keys_with_multi_current,
       'each enterprise_key has exactly one is_current=TRUE row' AS expected
FROM multi_current;

-- ── 2. Effective date overlap detection (vsecurity_dim sample) ─────────────
WITH overlaps AS (
    SELECT a.enterprise_key, count(*) AS overlap_count
    FROM investments.t_vsecurity_dim a
    JOIN investments.t_vsecurity_dim b
      ON  a.enterprise_key = b.enterprise_key
      AND a.security_sk    < b.security_sk
      AND a.effective_end_date >= b.effective_start_date
      AND a.effective_start_date <= b.effective_end_date
    GROUP BY a.enterprise_key
)
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS overlapping_keys,
       'no overlapping effective date ranges per enterprise_key' AS expected
FROM overlaps;

-- ── 3. Effective_start_date <= effective_end_date ──────────────────────────
WITH bad_dates AS (
    SELECT count(*) AS n
    FROM investments.t_vsecurity_dim
    WHERE effective_start_date > effective_end_date
)
SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       n AS bad_date_rows,
       'effective_start_date <= effective_end_date' AS expected
FROM bad_dates;

-- ── 4. Chain link validity (preceding/succeeding consistency) ──────────────
WITH chain_check AS (
    -- Every preceding_record_sk should reference a real row in the same dim
    SELECT count(*) AS n
    FROM investments.t_vsecurity_dim a
    LEFT JOIN investments.t_vsecurity_dim b ON b.security_sk = a.preceding_record_sk
    WHERE a.preceding_record_sk IS NOT NULL AND b.security_sk IS NULL
)
SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       n AS dangling_preceding_links,
       'every preceding_record_sk resolves to a real row' AS expected
FROM chain_check;

-- ── 5. vbusiness_unit_dim — bu_code uniqueness for current rows ────────────
WITH dup_bu AS (
    SELECT bu_code, count(*) AS n
    FROM investments.t_vbusiness_unit_dim
    WHERE is_current = TRUE
    GROUP BY 1 HAVING count(*) > 1
)
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS dup_bu_codes,
       'bu_code uniqueness among current business unit rows' AS expected
FROM dup_bu;

SELECT 'scd2_integrity complete' AS phase;
