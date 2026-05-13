-- ============================================================================
-- 05_validate/03_view_mv_derivability.sql
-- Decision #13: v* and mv* SELECT projections are mechanically derivable via
-- `s/v/mv/g` substitution at upstream FROM/JOIN/IN refs. Body-text parsing
-- isn't practical from SQL alone — this file uses row-count + key-aggregate
-- equivalence as a proxy. If row counts and a salient sum match for the v*
-- and mv* of the same entity, derivability is empirically holding.
--
-- Skipped-MV tolerance: bronze + silver MVs are always present after deploy
-- (deployed unconditionally by 02_bronze/05_*.sql and 03_silver/04_*.sql).
-- Gold MVs are optional (option B in plan-2 skips them; option A creates
-- all 53). Sections 3 + 4 below check `information_schema.tables` for the
-- target MV first; if missing, emit SKIP and move on rather than fail-loud.
-- EXECUTE IMMEDIATE defers compilation of the gold-MV query until runtime,
-- so the script parses cleanly even when those MVs don't exist.
--
-- For a full body-derivation check, eyeball SHOW CREATE VIEW v.<entity> and
-- SHOW CREATE MATERIALIZED VIEW mv.<entity> side-by-side; planned as a
-- programmatic 0.1.7 CI lint.
--
-- PASS criteria (per sampled entity):
--   * row_count(v*) == row_count(mv*)
--   * sum(salient numeric column)(v*) == sum(...)(mv*)
-- ============================================================================

BEGIN
    DECLARE catalog_name STRING DEFAULT 'medallion_demo';
    DECLARE gold_team_mv_count INT DEFAULT 0;
    DECLARE gold_consolidated_mv_count INT DEFAULT 0;

    EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

    -- ── 1. Bronze sample: vsecurity vs mvsecurity ─────────────────────────
    SELECT
        CASE WHEN v.rows = mv.rows THEN 'PASS' ELSE 'FAIL' END AS status,
        'bronze.vsecurity vs mvsecurity' AS sample,
        v.rows AS v_rows, mv.rows AS mv_rows
    FROM (SELECT count(*) AS rows FROM bronze.vsecurity) v
    CROSS JOIN (SELECT count(*) AS rows FROM bronze.mvsecurity) mv;

    -- ── 2. Silver sample: vposition_analytics_fact vs mvposition_analytics_fact
    SELECT
        CASE WHEN v.rows = mv.rows AND v.mv_sum = mv.mv_sum THEN 'PASS' ELSE 'FAIL' END AS status,
        'investments.vposition_analytics_fact vs mv*' AS sample,
        v.rows AS v_rows, mv.rows AS mv_rows,
        v.mv_sum AS v_market_value_sum, mv.mv_sum AS mv_market_value_sum
    FROM (
        SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
        FROM investments.vposition_analytics_fact
    ) v
    CROSS JOIN (
        SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum
        FROM investments.mvposition_analytics_fact
    ) mv;

    -- ── 3. Gold team sample (team_pd_direct_lending) — SKIP if MV not deployed
    SET gold_team_mv_count = (
        SELECT count(*) FROM information_schema.tables
        WHERE table_catalog = catalog_name
          AND table_schema  = 'team_pd_direct_lending'
          AND table_name    = 'mvposition_analytics_fact'
          AND table_type    = 'MATERIALIZED_VIEW'
    );
    IF gold_team_mv_count > 0 THEN
        -- chr(39) = single quote; Spark EXECUTE IMMEDIATE doesn't unescape '' inside the string body.
        EXECUTE IMMEDIATE concat(
            'SELECT CASE WHEN v.rows = mv.rows AND v.mv_sum = mv.mv_sum ',
            'THEN ', chr(39), 'PASS', chr(39), ' ELSE ', chr(39), 'FAIL', chr(39), ' END AS status, ',
            chr(39), 'team_pd_direct_lending v vs mv (position)', chr(39), ' AS sample, ',
            'v.rows AS v_rows, mv.rows AS mv_rows, v.mv_sum AS v_sum, mv.mv_sum AS mv_sum ',
            'FROM (SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum ',
            '      FROM team_pd_direct_lending.vposition_analytics_fact) v ',
            'CROSS JOIN (SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum ',
            '            FROM team_pd_direct_lending.mvposition_analytics_fact) mv'
        );
    ELSE
        SELECT 'SKIP' AS status,
               'team_pd_direct_lending v vs mv — gold MVs not deployed (option B; deploy via 04_gold/04_materialized_views.sql)' AS sample;
    END IF;

    -- ── 4. Gold consolidated sample (vpd_position_book) — SKIP if MV not deployed
    SET gold_consolidated_mv_count = (
        SELECT count(*) FROM information_schema.tables
        WHERE table_catalog = catalog_name
          AND table_schema  = 'gold_pd_consolidated'
          AND table_name    = 'mvpd_position_book'
          AND table_type    = 'MATERIALIZED_VIEW'
    );
    IF gold_consolidated_mv_count > 0 THEN
        EXECUTE IMMEDIATE concat(
            'SELECT CASE WHEN v.rows = mv.rows AND v.mv_sum = mv.mv_sum ',
            'THEN ', chr(39), 'PASS', chr(39), ' ELSE ', chr(39), 'FAIL', chr(39), ' END AS status, ',
            chr(39), 'gold_pd_consolidated vpd_position_book vs mv*', chr(39), ' AS sample, ',
            'v.rows AS v_rows, mv.rows AS mv_rows, v.mv_sum AS v_sum, mv.mv_sum AS mv_sum ',
            'FROM (SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum ',
            '      FROM gold_pd_consolidated.vpd_position_book) v ',
            'CROSS JOIN (SELECT count(*) AS rows, COALESCE(sum(market_value_usd), 0) AS mv_sum ',
            '            FROM gold_pd_consolidated.mvpd_position_book) mv'
        );
    ELSE
        SELECT 'SKIP' AS status,
               'gold_pd_consolidated vpd_position_book vs mv* — gold MVs not deployed' AS sample;
    END IF;

    -- ── Note: PASS here is necessary but not sufficient. A v/mv body could
    -- differ in projection (e.g. swapped column order) and still match on
    -- count+sum. For a full check: SHOW CREATE VIEW <entity>; SHOW CREATE
    -- MATERIALIZED VIEW <entity>. Programmatic body-diff lint planned for 0.1.7.
    SELECT 'view_mv_derivability complete' AS phase;
END;
