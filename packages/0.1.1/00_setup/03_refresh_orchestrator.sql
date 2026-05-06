-- ============================================================================
-- 00_setup/03_refresh_orchestrator.sql
-- Single-entry-point procedure to refresh every t_<entity> across all layers
-- in dependency order: bronze → silver → gold.
--
-- Per-leaf procs live in <layer>/05_refresh_procs.sql (or 06 in bronze).
-- Each leaf is independent; this orchestrator just calls them in order and
-- returns one summary row per layer.
--
-- Use this when you want to materialize tables (operationally distinct from
-- MVs — see DECISIONS.md #5). For MV refresh, use REFRESH MATERIALIZED VIEW
-- per-MV or rely on the (TBD 0.1.4) SCHEDULE clauses.
--
-- Idempotent. Safe to re-run.
-- ============================================================================

-- Self-declare catalog_name for fresh-session compatibility (see notes in 02_teardown.sql).
DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE OR REPLACE PROCEDURE bronze_silver_gold_refresh()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    DECLARE bronze_start TIMESTAMP DEFAULT current_timestamp();
    DECLARE silver_start TIMESTAMP;
    DECLARE gold_start   TIMESTAMP;
    DECLARE done_at      TIMESTAMP;

    -- ------------------------------------------------------------------
    -- Bronze depends on raw only — no inter-bronze ordering required.
    -- ------------------------------------------------------------------
    CALL bronze.refresh_all();
    SET silver_start = current_timestamp();

    -- ------------------------------------------------------------------
    -- Silver: SCD2 dims first (must be current before facts can resolve
    -- their dim_sks via temporal-join), then bridges, then facts, then
    -- cancels, then monthend snapshots.
    -- ------------------------------------------------------------------
    CALL investments.refresh_all();
    SET gold_start = current_timestamp();

    -- ------------------------------------------------------------------
    -- Gold: per-team refreshes are independent and run in any order;
    -- consolidated cross-team views land last.
    -- ------------------------------------------------------------------
    CALL team_pd_direct_lending.refresh_all();
    CALL team_pd_distressed.refresh_all();
    CALL team_pd_mezzanine.refresh_all();
    CALL team_pd_real_estate_debt.refresh_all();
    CALL team_pd_specialty_finance.refresh_all();
    CALL gold_pd_consolidated.refresh_all();
    SET done_at = current_timestamp();

    -- ------------------------------------------------------------------
    -- Summary.
    -- ------------------------------------------------------------------
    SELECT
        layer,
        duration_seconds
    FROM (
        VALUES
            ('bronze', bigint(timestampdiff(SECOND, bronze_start, silver_start))),
            ('silver', bigint(timestampdiff(SECOND, silver_start, gold_start))),
            ('gold',   bigint(timestampdiff(SECOND, gold_start,   done_at)))
    ) AS t(layer, duration_seconds);
END;

SELECT 'refresh_orchestrator created' AS status;
