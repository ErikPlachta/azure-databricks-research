-- ============================================================================
-- 06_demos/08_concurrency_demo.sql
-- What happens to readers when an MV refreshes?
--
-- The lesson: Delta MVs are atomic. During a refresh, concurrent readers
-- see the PRIOR committed snapshot — they don't block, don't error, don't
-- see partial state. After the refresh commits, NEW reads see the new state.
--
-- This file demonstrates the lesson two ways:
--
--   * Solo-tab (sections 1–4): use DELTA TIME TRAVEL to read the prior
--     snapshot AFTER the refresh. Conceptually equivalent to "what a
--     concurrent reader would have seen during the refresh."
--
--   * Multi-tab (section 5): the live concurrent-reader version. Requires
--     two SQL editor tabs running in parallel.
--
-- Pedagogical entity: investments.mvposition_analytics_fact (a non-trivial
-- silver MV — refresh takes ~30s–2m on Free Edition, enough time to be
-- pedagogically interesting).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Capture pre-refresh state ───────────────────────────────────────────
-- The MV's underlying Delta table has a version history. Note the current
-- version number — we'll time-travel to it later to simulate "what a
-- concurrent reader would have seen during the refresh."
DESCRIBE HISTORY investments.mvposition_analytics_fact LIMIT 5;

-- Capture the current latest version number for use in section 4.
SELECT max(version) AS pre_refresh_version,
       max(timestamp) AS pre_refresh_committed_at
FROM (DESCRIBE HISTORY investments.mvposition_analytics_fact);

-- Pre-refresh row count snapshot
SELECT count(*) AS pre_refresh_count, current_timestamp() AS captured_at
FROM investments.mvposition_analytics_fact;

-- ── 2. Mutate something upstream so the refresh produces a real diff ──────
-- Insert a fake position into raw. The refresh will pick it up.
INSERT INTO raw_state_street.position_raw (
    enterprise_key, position_date, portfolio_source_key, security_source_key,
    quantity, price_local, currency_code, settlement_status, loaded_at
)
SELECT 'CONCURRENCY_DEMO_TEST_KEY',
       current_date(),
       'state_street_portfolio_team_pd_direct_lending_001',
       'state_street_security_aspen_security_001',
       100,
       1.0,
       'USD',
       'SETTLED',
       current_timestamp();

-- ── 3. Refresh the MV — atomic commit when done ───────────────────────────
-- During this refresh, any concurrent reader (in another tab) sees the
-- prior version. Once refresh completes, the new version is committed
-- atomically and subsequent reads see the new state.
REFRESH MATERIALIZED VIEW investments.mvposition_analytics_fact;

-- Post-refresh history — version number incremented
DESCRIBE HISTORY investments.mvposition_analytics_fact LIMIT 5;

-- Post-refresh count
SELECT count(*) AS post_refresh_count, current_timestamp() AS captured_at
FROM investments.mvposition_analytics_fact;

-- ── 4. Solo-tab simulation: read prior version via time travel ────────────
-- "What would a concurrent reader have seen during the refresh?" — exactly
-- what the prior committed version contained. Time-travel to it.
--
-- Replace <PRE_REFRESH_VERSION> below with the version number from §1.
-- (Spark SQL time travel syntax: VERSION AS OF <int> or TIMESTAMP AS OF <ts>.)
--
--   SELECT count(*) AS concurrent_reader_count
--   FROM investments.mvposition_analytics_fact VERSION AS OF <PRE_REFRESH_VERSION>;
--
-- Or by timestamp (more pedagogically clear):
--
--   SELECT count(*) AS concurrent_reader_count
--   FROM investments.mvposition_analytics_fact TIMESTAMP AS OF '<PRE_REFRESH_COMMITTED_AT>';
--
-- The point: the count returned matches §1's pre_refresh_count, NOT §3's
-- post_refresh_count. A reader that started during the refresh would have
-- seen the prior atomic snapshot and finished with that result, regardless
-- of when section 3's REFRESH commits.

-- ── 5. (Optional) Multi-tab concurrent-reader demo ─────────────────────────
-- For the live version, two SQL editor tabs in parallel:
--
-- Tab A — kick off a heavier refresh (gold MV, harder cascade):
--   REFRESH MATERIALIZED VIEW gold_pd_consolidated.mvpd_position_book;
--
-- Tab B — DURING Tab A's refresh, run:
--   SELECT count(*) AS reader_count, current_timestamp() AS read_at
--   FROM gold_pd_consolidated.mvpd_position_book;
--
-- Expected: Tab B returns immediately with the pre-refresh count. Tab B
-- never blocks. After Tab A commits, re-run Tab B — count reflects the
-- new state.

-- ── 6. Cleanup — remove the test row ───────────────────────────────────────
DELETE FROM raw_state_street.position_raw
WHERE enterprise_key = 'CONCURRENCY_DEMO_TEST_KEY';
REFRESH MATERIALIZED VIEW investments.mvposition_analytics_fact;

-- ── 7. Concurrent reads on a view (no atomicity needed) ────────────────────
-- Views are stateless — multiple readers each run the body in parallel.
-- No atomicity question; no blocking; CPU/memory are the only contention.
-- This is why MVs/tables outperform views under high concurrent load:
-- they share materialized state.
SELECT count(*) AS view_count
FROM investments.vposition_analytics_fact;

-- ── 8. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'Delta MVs/tables are atomic — refreshes don''t block readers'   AS lesson_1,
    'concurrent readers see the prior snapshot until the new commit' AS lesson_2,
    'time-travel (VERSION AS OF) lets you reproduce that prior view' AS lesson_3,
    'views never have refresh atomicity questions but each reader pays body cost' AS lesson_4;
