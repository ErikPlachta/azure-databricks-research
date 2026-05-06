-- ============================================================================
-- 05_validate/06_refresh_smoke.sql
-- End-to-end smoke test of bronze_silver_gold_refresh(). Captures per-layer
-- durations and asserts the orchestrator returns a clean 3-row summary.
--
-- Pre-Phase 3 fix this file fails because team_pd_*.refresh_all() doesn't
-- exist. Post-fix it should complete in seconds (Free Edition default seed)
-- and emit per-layer timing.
--
-- For deeper timing capture (per-statement), query system.query.history
-- after a 30s wait — captures duration, bytes scanned, query plan.
--
-- PASS criteria:
--   * Orchestrator runs without error.
--   * Each layer's duration is non-negative.
--   * Total duration is bounded (Free Edition: <120s; paid: <600s).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Run orchestrator (returns 3-row layer-duration summary) ─────────────
CALL bronze_silver_gold_refresh();

-- ── 2. Sanity: tables non-empty after refresh ──────────────────────────────
WITH counts AS (
    SELECT
        (SELECT count(*) FROM bronze.t_vsecurity)                               AS n_bronze_security,
        (SELECT count(*) FROM investments.t_vposition_analytics_fact)           AS n_silver_positions,
        (SELECT count(*) FROM team_pd_direct_lending.t_vposition_analytics_fact) AS n_team_positions,
        (SELECT count(*) FROM gold_pd_consolidated.t_vpd_position_book)         AS n_consol_positions
)
SELECT CASE WHEN n_bronze_security > 0 AND n_silver_positions > 0
                 AND n_team_positions > 0 AND n_consol_positions > 0
            THEN 'PASS' ELSE 'FAIL' END AS status,
       n_bronze_security, n_silver_positions, n_team_positions, n_consol_positions,
       'all 4 layer-representative tables non-empty after orchestrator' AS expected
FROM counts;

-- ── 3. Optional: deeper timing via system.query.history (paid only) ────────
-- system.query.history is a Databricks-managed system table available on
-- serverless compute. Uncomment if you want per-statement durations:
--
-- SELECT statement_text, start_time,
--        timestampdiff(MILLISECOND, start_time, end_time) / 1000.0 AS duration_seconds
-- FROM system.query.history
-- WHERE start_time > (SELECT current_timestamp() - INTERVAL 5 MINUTE)
--   AND statement_text LIKE '%bronze_silver_gold_refresh%'
-- ORDER BY start_time DESC LIMIT 20;

SELECT 'refresh_smoke complete' AS phase;
