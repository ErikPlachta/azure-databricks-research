-- ============================================================================
-- 06_demos/06_freshness_demo.sql
-- THE LOAD-BEARING DEMO: what does each artifact see when raw data mutates?
--
-- The whole v vs mv vs t conversation is really about freshness. View sees
-- everything immediately. MV sees nothing until refresh. Table sees nothing
-- until proc runs. This is the cost you pay for materialization speed.
--
-- What to watch:
--   * Section 1 — baseline row count for v, mv, t — all equal.
--   * Section 2 — insert one new row into raw. Pause and observe:
--     - v* increases by 1 immediately (next query reflects the new row).
--     - mv* still shows the OLD count (not refreshed).
--     - t_* still shows the OLD count (proc hasn't run).
--   * Section 3 — REFRESH MATERIALIZED VIEW. Now mv* sees the new row.
--   * Section 4 — CALL refresh proc. Now t_* sees the new row.
--   * Section 5 — DELETE the test row from raw. Repeat the cycle.
--
-- Pedagogical entity: bronze.security (single source, simple shape, easy
-- to mutate without breaking other demos).
--
-- Cleanup: section 5 removes the test row.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ── 1. Baseline — v / mv / t should agree ──────────────────────────────────
SELECT 'v'  AS kind, count(*) AS n FROM bronze.vsecurity
UNION ALL SELECT 'mv', count(*) FROM bronze.mvsecurity
UNION ALL SELECT 't',  count(*) FROM bronze.t_vsecurity
ORDER BY kind;

-- ── 2. Insert one fake row into raw ────────────────────────────────────────
-- This row exists only in raw_aspen.security_master_raw. The bronze v*
-- (which reads raw) will see it on next query. mv* and t_* will not.
INSERT INTO raw_aspen.security_master_raw (
    enterprise_key, security_name, asset_class, sub_asset_class,
    issue_date, maturity_date, coupon_rate, currency_code, loaded_at
)
VALUES (
    'TEST_FRESHNESS_DEMO_ROW', 'Test Security — DEMO 06', 'Equity', 'Common Stock',
    DATE'2024-01-01', DATE'2034-01-01', 0.05, 'USD', current_timestamp()
);

-- ── 3. Query v / mv / t — observe the divergence ──────────────────────────
-- What should happen:
--   * v_count = baseline + 1   (view sees raw immediately)
--   * mv_count = baseline      (MV is stale)
--   * t_count = baseline       (table is stale)
SELECT 'v_after_insert'  AS kind, count(*) AS n FROM bronze.vsecurity
UNION ALL SELECT 'mv_still_stale', count(*) FROM bronze.mvsecurity
UNION ALL SELECT 't_still_stale',  count(*) FROM bronze.t_vsecurity
ORDER BY kind;

-- Confirm v sees the test row by name
SELECT 'v sees TEST row?' AS check, enterprise_key
FROM bronze.vsecurity WHERE enterprise_key = 'TEST_FRESHNESS_DEMO_ROW';

-- Confirm mv does NOT see it yet
SELECT 'mv sees TEST row?' AS check, enterprise_key
FROM bronze.mvsecurity WHERE enterprise_key = 'TEST_FRESHNESS_DEMO_ROW';

-- ── 4. Refresh MV — now it sees the new row ────────────────────────────────
REFRESH MATERIALIZED VIEW bronze.mvsecurity;

SELECT 'mv_after_refresh' AS kind, count(*) AS n FROM bronze.mvsecurity;
SELECT 'mv sees TEST row now?' AS check, enterprise_key
FROM bronze.mvsecurity WHERE enterprise_key = 'TEST_FRESHNESS_DEMO_ROW';

-- ── 5. Call refresh proc — now table sees the new row ─────────────────────
CALL bronze.refresh_security();

SELECT 't_after_refresh' AS kind, count(*) AS n FROM bronze.t_vsecurity;
SELECT 't sees TEST row now?' AS check, enterprise_key
FROM bronze.t_vsecurity WHERE enterprise_key = 'TEST_FRESHNESS_DEMO_ROW';

-- ── 6. Cleanup — delete the test row ───────────────────────────────────────
DELETE FROM raw_aspen.security_master_raw
WHERE enterprise_key = 'TEST_FRESHNESS_DEMO_ROW';

-- After cleanup: v sees it gone immediately; mv/t still see it until
-- the next refresh. That's the same lesson, mirrored.
SELECT 'v_after_cleanup' AS kind, count(*) AS n FROM bronze.vsecurity;

-- Optional: re-refresh mv + t to restore baseline state
REFRESH MATERIALIZED VIEW bronze.mvsecurity;
CALL bronze.refresh_security();

-- ── 7. Key takeaway ───────────────────────────────────────────────────────
SELECT
    'v reflects upstream changes immediately'                     AS lesson_1,
    'mv stays stale until REFRESH MATERIALIZED VIEW'              AS lesson_2,
    't stays stale until refresh proc runs'                       AS lesson_3,
    'staleness is the price you pay for materialization speed'   AS core_tradeoff;
