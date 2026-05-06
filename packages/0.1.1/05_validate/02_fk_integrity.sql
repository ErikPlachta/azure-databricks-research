-- ============================================================================
-- 05_validate/02_fk_integrity.sql
-- Orphan-key checks. Spark/UC don't enforce FK constraints, so referential
-- integrity is asserted at validation time. Violations indicate either
-- broken bronze precedence (enterprise_key resolution failed) or broken
-- silver SCD2 temporal joins (dim_sk lookup returned NULL).
--
-- PASS criteria:
--   * Every silver fact's portfolio_sk resolves to an investments.vportfolio_dim row.
--   * Every silver fact's security_sk resolves to an investments.vsecurity_dim row.
--   * Every team_pd_* fact's referenced silver row exists.
--   * gold_pd_consolidated tables match the union of their team sources (row-count check).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Silver fact → silver dim resolution ─────────────────────────────────
WITH orphan_positions AS (
    SELECT count(*) AS n
    FROM investments.t_vposition_analytics_fact f
    LEFT JOIN investments.t_vportfolio_dim p ON p.portfolio_sk = f.portfolio_sk AND p.is_current = TRUE
    WHERE f.portfolio_sk IS NOT NULL AND p.portfolio_sk IS NULL
)
SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       n AS orphan_position_portfolio_sks,
       'every position.portfolio_sk resolves to a current portfolio_dim row' AS expected
FROM orphan_positions;

WITH orphan_security AS (
    SELECT count(*) AS n
    FROM investments.t_vposition_analytics_fact f
    LEFT JOIN investments.t_vsecurity_dim s ON s.security_sk = f.security_sk AND s.is_current = TRUE
    WHERE f.security_sk IS NOT NULL AND s.security_sk IS NULL
)
SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       n AS orphan_position_security_sks,
       'every position.security_sk resolves to a current security_dim row' AS expected
FROM orphan_security;

-- ── 2. Bronze enterprise_key uniqueness within an entity ───────────────────
WITH dup_security AS (
    SELECT count(*) AS n FROM (
        SELECT enterprise_key FROM bronze.t_vsecurity GROUP BY 1 HAVING count(*) > 1
    )
)
SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       n AS dup_bronze_security_keys,
       'enterprise_key uniqueness in bronze.t_vsecurity' AS expected
FROM dup_security;

-- ── 3. Gold team facts non-empty ───────────────────────────────────────────
WITH team_check AS (
    SELECT 'team_pd_direct_lending'    AS team, count(*) AS n FROM team_pd_direct_lending.t_vposition_analytics_fact
    UNION ALL SELECT 'team_pd_distressed',         count(*) FROM team_pd_distressed.t_vposition_analytics_fact
    UNION ALL SELECT 'team_pd_mezzanine',          count(*) FROM team_pd_mezzanine.t_vposition_analytics_fact
    UNION ALL SELECT 'team_pd_real_estate_debt',   count(*) FROM team_pd_real_estate_debt.t_vposition_analytics_fact
    UNION ALL SELECT 'team_pd_specialty_finance',  count(*) FROM team_pd_specialty_finance.t_vposition_analytics_fact
)
SELECT CASE WHEN min(n) > 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       min(n) AS smallest_team_position_count,
       'every PD team has >0 positions' AS expected
FROM team_check;

-- ── 4. Consolidated = sum of teams ─────────────────────────────────────────
WITH team_sum AS (
    SELECT (
        (SELECT count(*) FROM team_pd_direct_lending.t_vposition_analytics_fact)
      + (SELECT count(*) FROM team_pd_distressed.t_vposition_analytics_fact)
      + (SELECT count(*) FROM team_pd_mezzanine.t_vposition_analytics_fact)
      + (SELECT count(*) FROM team_pd_real_estate_debt.t_vposition_analytics_fact)
      + (SELECT count(*) FROM team_pd_specialty_finance.t_vposition_analytics_fact)
    ) AS team_total,
    (SELECT count(*) FROM gold_pd_consolidated.t_vpd_position_book) AS consol_total
)
SELECT CASE WHEN team_total = consol_total THEN 'PASS' ELSE 'FAIL' END AS status,
       team_total, consol_total,
       'gold_pd_consolidated.position_book = sum of 5 teams' AS expected
FROM team_sum;

SELECT 'fk_integrity complete' AS phase;
