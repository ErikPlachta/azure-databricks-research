-- ============================================================================
-- 06_demos/07_refresh_cost_demo.sql
-- Where do MV refresh costs show up, and what strategy did Databricks pick?
--
-- DECISIONS.md #5 introduces the three refresh strategies Enzyme can choose:
--   * ROW_BASED            — incremental: process only changed source rows.
--   * PARTITION_OVERWRITE  — recompute only affected partitions.
--   * COMPLETE_RECOMPUTE   — full rebuild from scratch.
--
-- The strategy depends on the body shape (does it have aggregates? joins?
-- window functions?), the upstream change shape, and Databricks-internal
-- heuristics. event_log() exposes which strategy actually fired.
--
-- What to watch:
--   * Section 1 — refresh an MV; observe the strategy in event_log.
--   * Section 2 — system.query.history shows the refresh as a query with
--     duration + bytes_scanned + rows_produced.
--   * Section 3 — for an MV with non-trivial body, you'll see which fired.
--
-- Free Edition: serverless compute is fine for these queries. event_log
-- requires the warehouse to have UC catalog access (default for medallion_demo).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Refresh a simple MV (bronze layer — body is byte-identical to view) ─
REFRESH MATERIALIZED VIEW bronze.mvsecurity;

-- ── 2. Inspect event_log for the refresh ──────────────────────────────────
-- event_log() is a table-valued function scoped to a single MV. Returns
-- one row per refresh event including chosen strategy + duration.
-- Note: results may take 30s–2m to populate; if empty, wait and re-run.
SELECT
    timestamp,
    event_type,
    details:plan_information:refresh_strategy AS refresh_strategy,
    details:plan_information:execution_duration_ms AS duration_ms,
    details:plan_information:num_output_rows AS rows_produced
FROM event_log(table => 'bronze.mvsecurity')
WHERE event_type = 'refresh_completed'
ORDER BY timestamp DESC
LIMIT 5;

-- ── 3. Refresh a heavier MV (silver layer — has aggregates + joins) ────────
-- A silver fact MV is more interesting because the body is non-trivial,
-- so Enzyme has more strategy options.
REFRESH MATERIALIZED VIEW investments.mvposition_analytics_fact;

SELECT
    timestamp,
    event_type,
    details:plan_information:refresh_strategy,
    details:plan_information:execution_duration_ms AS duration_ms,
    details:plan_information:num_output_rows
FROM event_log(table => 'investments.mvposition_analytics_fact')
WHERE event_type = 'refresh_completed'
ORDER BY timestamp DESC
LIMIT 5;

-- ── 4. Cross-MV cost view via system.query.history ────────────────────────
-- system.query.history is a Databricks-managed view for serverless workspaces.
-- After a 30s–2m delay it shows query text + duration + bytes scanned.
SELECT
    statement_text,
    start_time,
    timestampdiff(MILLISECOND, start_time, end_time) / 1000.0 AS duration_seconds,
    total_task_duration_ms / 1000.0                            AS total_task_seconds
FROM system.query.history
WHERE start_time > current_timestamp() - INTERVAL 10 MINUTE
  AND statement_text LIKE 'REFRESH MATERIALIZED VIEW%'
ORDER BY start_time DESC
LIMIT 20;

-- ── 5. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'event_log() exposes per-MV refresh strategy + duration'    AS lesson_1,
    'system.query.history aggregates across MVs for the warehouse' AS lesson_2,
    'simple bodies → ROW_BASED; complex aggregates → COMPLETE_RECOMPUTE' AS rule_of_thumb,
    'paid SCHEDULE clauses (0.1.4) reduce manual refresh overhead' AS forward_looking;
