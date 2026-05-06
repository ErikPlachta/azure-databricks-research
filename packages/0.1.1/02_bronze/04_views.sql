-- ============================================================================
-- 02_bronze/04_views.sql
-- 14 bronze v<entity> views with precedence + provenance.
--
-- Pattern:
--   1. Each view dedups source rows to "latest-wins per enterprise_key" via
--      ROW_NUMBER OVER (PARTITION BY enterprise_key ORDER BY loaded_at DESC).
--      This handles SCD2 v2 history rows where pre-bronze has multiple raw
--      rows for the same enterprise_key (e.g. entity restructurings emit
--      both an original and a _v2 row in raw_aspen.entity_master_raw).
--   2. Multi-source views LEFT JOIN secondary sources to enrich primary rows.
--   3. Crosswalk lookups translate source-system FKs to enterprise_keys.
--   4. Provenance: per-column <col>_source on multi-source views; top-level
--      _source_pref (which sources contributed); _sources_in_conflict
--      (currently always empty; conflict detection is a 0.1.1+ enhancement).
--
-- View bodies below MUST stay byte-identical to the matching mv<entity>
-- bodies in 05_materialized_views.sql. Permanent invariant — see DECISIONS.md #6.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- DIM-SHAPED VIEWS
-- ============================================================================

-- 4.1 vsecurity (aspen primary + state_street latest price) -------------------
CREATE OR REPLACE VIEW bronze.vsecurity AS
WITH aspen_latest AS (
    SELECT *
    FROM (
        SELECT
            a.*,
            ROW_NUMBER() OVER (PARTITION BY a.enterprise_key ORDER BY a.loaded_at DESC) AS _rn
        FROM raw_aspen.security_master_raw a
    )
    WHERE _rn = 1
),
ss_latest_price AS (
    SELECT *
    FROM (
        SELECT
            sp.security_source_key,
            sp.close_price_local,
            sp.currency_code AS price_currency_code,
            sp.price_date,
            ROW_NUMBER() OVER (PARTITION BY sp.security_source_key ORDER BY sp.price_date DESC, sp.loaded_at DESC) AS _rn
        FROM raw_state_street.security_price_raw sp
    )
    WHERE _rn = 1
)
SELECT
    a.enterprise_key,
    a.security_name,
    'aspen'                                 AS security_name_source,
    a.security_type,
    'aspen'                                 AS security_type_source,
    a.asset_class,
    'aspen'                                 AS asset_class_source,
    a.sub_asset_class,
    a.issue_date,
    a.maturity_date,
    a.coupon_rate,
    a.currency_code,
    'aspen'                                 AS currency_code_source,
    bronze.fn_resolve_enterprise_key('aspen', a.issuer_source_key) AS issuer_enterprise_key,
    a.isin_code,
    a.cusip_code,
    ssp.close_price_local                   AS latest_close_price,
    ssp.price_currency_code                 AS latest_close_price_currency,
    ssp.price_date                          AS latest_price_date,
    CAST(NULL AS DECIMAL(18, 2))            AS contract_total_principal,
    CASE WHEN ssp.security_source_key IS NOT NULL THEN 'aspen+state_street' ELSE 'aspen' END AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    a.loaded_at                             AS bronze_loaded_at
FROM aspen_latest a
LEFT JOIN ss_latest_price ssp ON ssp.security_source_key = a.source_key;

-- 4.2 ventity (aspen primary + efront has_contracts overlay) ------------------
CREATE OR REPLACE VIEW bronze.ventity AS
WITH aspen_latest AS (
    SELECT *
    FROM (
        SELECT
            e.*,
            ROW_NUMBER() OVER (PARTITION BY e.enterprise_key ORDER BY e.loaded_at DESC) AS _rn
        FROM raw_aspen.entity_master_raw e
    )
    WHERE _rn = 1
),
efront_entities_with_contracts AS (
    SELECT DISTINCT entity_source_key
    FROM raw_efront.contract_raw
)
SELECT
    e.enterprise_key,
    e.entity_name,
    'aspen'                                 AS entity_name_source,
    e.entity_type,
    'aspen'                                 AS entity_type_source,
    e.legal_structure,
    e.jurisdiction,
    e.tax_id,
    e.formation_date,
    e.dissolution_date,
    bronze.fn_resolve_enterprise_key('aspen', e.parent_entity_source_key) AS parent_entity_enterprise_key,
    e.is_active,
    e.address_line,
    e.city,
    e.state_region,
    e.country,
    (efc.entity_source_key IS NOT NULL)     AS has_contracts,
    CASE WHEN efc.entity_source_key IS NOT NULL THEN 'aspen+efront' ELSE 'aspen' END AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    e.loaded_at                             AS bronze_loaded_at
FROM aspen_latest e
LEFT JOIN efront_entities_with_contracts efc ON efc.entity_source_key = e.source_key;

-- 4.3 vasset (aspen sole) -----------------------------------------------------
CREATE OR REPLACE VIEW bronze.vasset AS
SELECT
    a.enterprise_key,
    a.asset_name,
    a.asset_type,
    a.asset_class,
    a.country,
    a.region,
    a.vintage_year,
    a.total_size_local,
    a.currency_code,
    a.ownership_pct,
    a.manager_name,
    a.status,
    'aspen'                                 AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    a.loaded_at                             AS bronze_loaded_at
FROM (
    SELECT
        a.*,
        ROW_NUMBER() OVER (PARTITION BY a.enterprise_key ORDER BY a.loaded_at DESC) AS _rn
    FROM raw_aspen.asset_master_raw a
) a
WHERE a._rn = 1;

-- 4.4 vportfolio (aladdin master + efront capital activity rollup) ------------
CREATE OR REPLACE VIEW bronze.vportfolio AS
WITH aladdin_portfolios AS (
    -- aladdin doesn't have a portfolio_master table; we derive identity from
    -- portfolio_risk_raw. Take the latest row per portfolio_source_key as the
    -- "master" aladdin record.
    SELECT *
    FROM (
        SELECT
            r.portfolio_source_key,
            r.enterprise_key,
            r.portfolio_name,
            r.strategy_name,
            r.loaded_at,
            ROW_NUMBER() OVER (PARTITION BY r.portfolio_source_key ORDER BY r.risk_date DESC, r.loaded_at DESC) AS _rn
        FROM raw_aladdin.portfolio_risk_raw r
    )
    WHERE _rn = 1
),
efront_capital_rollup AS (
    SELECT
        ca.portfolio_source_key,
        MAX(ca.activity_date)                                AS latest_activity_date,
        SUM(CASE WHEN ca.activity_type = 'CAPITAL_CALL'   THEN ca.amount_local ELSE 0 END) AS total_called,
        SUM(CASE WHEN ca.activity_type = 'DISTRIBUTION'   THEN ca.amount_local ELSE 0 END) AS total_distributed
    FROM raw_efront.capital_activity_raw ca
    GROUP BY ca.portfolio_source_key
)
SELECT
    p.enterprise_key,
    p.portfolio_name,
    'aladdin'                               AS portfolio_name_source,
    p.strategy_name,
    'aladdin'                               AS strategy_name_source,
    cr.latest_activity_date                 AS latest_capital_activity_date,
    cr.total_called                         AS total_capital_called,
    cr.total_distributed                    AS total_distributed,
    CASE WHEN cr.portfolio_source_key IS NOT NULL THEN 'aladdin+efront' ELSE 'aladdin' END AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    p.loaded_at                             AS bronze_loaded_at
FROM aladdin_portfolios p
LEFT JOIN efront_capital_rollup cr ON cr.portfolio_source_key = p.portfolio_source_key;

-- 4.5 vcontract (efront sole) -------------------------------------------------
CREATE OR REPLACE VIEW bronze.vcontract AS
SELECT
    c.enterprise_key,
    c.contract_name,
    bronze.fn_resolve_enterprise_key('aspen', c.entity_source_key) AS entity_enterprise_key,
    c.contract_type,
    c.signing_date,
    c.maturity_date,
    c.principal_local,
    c.currency_code,
    c.coupon_type,
    c.coupon_rate,
    c.spread_over_benchmark,
    c.benchmark_code,
    c.status,
    'efront'                                AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    c.loaded_at                             AS bronze_loaded_at
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (PARTITION BY c.enterprise_key ORDER BY c.loaded_at DESC) AS _rn
    FROM raw_efront.contract_raw c
) c
WHERE c._rn = 1;

-- 4.6 vbusiness_unit (internal_admin + aladdin risk-team overlay) -------------
CREATE OR REPLACE VIEW bronze.vbusiness_unit AS
WITH bu_latest AS (
    SELECT *
    FROM (
        SELECT
            bu.*,
            ROW_NUMBER() OVER (PARTITION BY bu.enterprise_key ORDER BY bu.loaded_at DESC) AS _rn
        FROM raw_internal_admin.business_unit_master_raw bu
    )
    WHERE _rn = 1
),
risk_team_overlay AS (
    -- Aladdin's risk_team_code is associated to a portfolio via compliance check;
    -- this overlay assigns each BU's risk team via portfolio mapping. Best-effort
    -- since we don't have a strict BU<->risk_team table; aggregate distinct codes.
    SELECT collect_set(DISTINCT risk_team_code) AS team_codes
    FROM raw_aladdin.compliance_check_raw
),
all_risk_teams AS (
    SELECT (SELECT team_codes FROM risk_team_overlay) AS team_codes
)
SELECT
    bu.enterprise_key,
    bu.bu_code,
    bu.bu_name,
    'internal_admin'                        AS bu_name_source,
    bu.bu_type,
    bronze.fn_resolve_enterprise_key('internal_admin', bu.parent_bu_code) AS parent_bu_enterprise_key,
    bu.asset_class_focus,
    bu.strategy_name,
    bu.head_employee_id,
    bu.established_date,
    bu.is_active,
    art.team_codes                          AS associated_risk_team_codes,
    CASE WHEN art.team_codes IS NOT NULL AND size(art.team_codes) > 0 THEN 'internal_admin+aladdin' ELSE 'internal_admin' END AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    bu.loaded_at                            AS bronze_loaded_at
FROM bu_latest bu
CROSS JOIN all_risk_teams art;

-- ============================================================================
-- FACT-SHAPED VIEWS
-- ============================================================================

-- 4.7 vposition (state_street sole) -------------------------------------------
CREATE OR REPLACE VIEW bronze.vposition AS
SELECT
    p.enterprise_key,
    p.position_date,
    bronze.fn_resolve_enterprise_key('state_street', p.portfolio_source_key) AS portfolio_enterprise_key,
    bronze.fn_resolve_enterprise_key('aspen', p.security_source_key)          AS security_enterprise_key,
    p.quantity,
    p.market_value_local,
    p.book_value_local,
    p.cost_basis_local,
    p.unrealized_gl_local,
    p.unit_price_local,
    p.currency_code,
    p.settlement_status,
    p.custodian_account,
    'state_street'                          AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    p.loaded_at                             AS bronze_loaded_at
FROM (
    SELECT
        p.*,
        ROW_NUMBER() OVER (PARTITION BY p.enterprise_key ORDER BY p.loaded_at DESC) AS _rn
    FROM raw_state_street.position_raw p
) p
WHERE p._rn = 1;

-- 4.8 vtransaction (state_street settled + aladdin in-flight overlay) ---------
CREATE OR REPLACE VIEW bronze.vtransaction AS
WITH ss_settled AS (
    SELECT *
    FROM (
        SELECT
            t.*,
            ROW_NUMBER() OVER (PARTITION BY t.enterprise_key ORDER BY t.loaded_at DESC) AS _rn
        FROM raw_state_street.transaction_raw t
    )
    WHERE _rn = 1
)
SELECT
    s.enterprise_key,
    s.transaction_date,
    s.settlement_date,
    bronze.fn_resolve_enterprise_key('state_street', s.portfolio_source_key) AS portfolio_enterprise_key,
    bronze.fn_resolve_enterprise_key('aspen', s.security_source_key)          AS security_enterprise_key,
    s.transaction_type,
    'state_street'                          AS transaction_type_source,
    s.quantity,
    s.price_local,
    s.gross_amount_local,
    s.fees_local,
    s.net_amount_local,
    s.currency_code,
    s.counterparty_name,
    s.custodian_account,
    CAST(NULL AS STRING)                    AS trade_status,  -- settled rows have no in-flight status
    'state_street'                          AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    s.loaded_at                             AS bronze_loaded_at
FROM ss_settled s
UNION ALL
-- Aladdin in-flight rows (PENDING / EXECUTED / CANCELLED only). Settled rows
-- in aladdin would duplicate state_street, so we exclude SETTLED here.
SELECT
    tb.enterprise_key,
    tb.trade_date                           AS transaction_date,
    CAST(NULL AS DATE)                      AS settlement_date,
    bronze.fn_resolve_enterprise_key('state_street', tb.portfolio_source_key) AS portfolio_enterprise_key,
    bronze.fn_resolve_enterprise_key('aspen', tb.security_source_key)          AS security_enterprise_key,
    tb.side                                 AS transaction_type,
    'aladdin'                               AS transaction_type_source,
    tb.quantity,
    tb.limit_price                          AS price_local,
    CAST(NULL AS DECIMAL(18, 2))            AS gross_amount_local,
    CAST(NULL AS DECIMAL(18, 2))            AS fees_local,
    CAST(NULL AS DECIMAL(18, 2))            AS net_amount_local,
    tb.currency_code,
    CAST(NULL AS STRING)                    AS counterparty_name,
    CAST(NULL AS STRING)                    AS custodian_account,
    tb.trade_status,
    'aladdin'                               AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    tb.loaded_at                            AS bronze_loaded_at
FROM raw_aladdin.trade_blotter_raw tb
WHERE tb.trade_status IN ('PENDING', 'EXECUTED', 'CANCELLED');

-- 4.9 vsecurity_price (state_street sole) -------------------------------------
CREATE OR REPLACE VIEW bronze.vsecurity_price AS
SELECT
    sp.enterprise_key,
    bronze.fn_resolve_enterprise_key('aspen', sp.security_source_key) AS security_enterprise_key,
    sp.price_date,
    sp.close_price_local,
    sp.currency_code,
    sp.price_type,
    'state_street'                          AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    sp.loaded_at                            AS bronze_loaded_at
FROM raw_state_street.security_price_raw sp;

-- 4.10 vportfolio_risk (aladdin sole) -----------------------------------------
CREATE OR REPLACE VIEW bronze.vportfolio_risk AS
SELECT
    r.enterprise_key,
    bronze.fn_resolve_enterprise_key('state_street', r.portfolio_source_key) AS portfolio_enterprise_key,
    r.risk_date,
    r.var_95,
    r.var_99,
    r.expected_shortfall,
    r.beta,
    r.tracking_error,
    r.risk_currency,
    'aladdin'                               AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    r.loaded_at                             AS bronze_loaded_at
FROM raw_aladdin.portfolio_risk_raw r;

-- 4.11 vportfolio_performance (aladdin sole) ----------------------------------
CREATE OR REPLACE VIEW bronze.vportfolio_performance AS
SELECT
    p.enterprise_key,
    bronze.fn_resolve_enterprise_key('state_street', p.portfolio_source_key) AS portfolio_enterprise_key,
    p.performance_date,
    p.period_return_pct,
    p.ytd_return_pct,
    p.since_inception_return_pct,
    p.benchmark_return_pct,
    p.benchmark_code,
    'aladdin'                               AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    p.loaded_at                             AS bronze_loaded_at
FROM raw_aladdin.portfolio_performance_raw p;

-- 4.12 vrating (aspen security + entity ratings UNIONed) ----------------------
CREATE OR REPLACE VIEW bronze.vrating AS
SELECT
    sr.enterprise_key,
    bronze.fn_resolve_enterprise_key('aspen', sr.security_source_key) AS rated_object_enterprise_key,
    'SECURITY'                              AS rated_object_type,
    sr.rating_date,
    sr.rating_agency,
    sr.rating_value,
    sr.rating_outlook,
    sr.rating_action_type,
    'aspen'                                 AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    sr.loaded_at                            AS bronze_loaded_at
FROM raw_aspen.security_rating_raw sr
UNION ALL
SELECT
    er.enterprise_key,
    bronze.fn_resolve_enterprise_key('aspen', er.entity_source_key) AS rated_object_enterprise_key,
    'ENTITY'                                AS rated_object_type,
    er.rating_date,
    er.rating_agency,
    er.rating_value,
    er.rating_outlook,
    er.rating_action_type,
    'aspen'                                 AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    er.loaded_at                            AS bronze_loaded_at
FROM raw_aspen.entity_rating_raw er;

-- 4.13 vcollateral (efront sole) ----------------------------------------------
CREATE OR REPLACE VIEW bronze.vcollateral AS
SELECT
    cx.enterprise_key,
    bronze.fn_resolve_enterprise_key('efront', cx.contract_source_key) AS contract_enterprise_key,
    cx.exposure_date,
    cx.exposure_amount_local,
    cx.currency_code,
    cx.collateral_type,
    cx.collateral_value_local,
    cx.ltv_pct,
    'efront'                                AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    cx.loaded_at                            AS bronze_loaded_at
FROM raw_efront.collateral_exposure_raw cx;

-- 4.14 vfx_rate (bloomberg sole) ----------------------------------------------
CREATE OR REPLACE VIEW bronze.vfx_rate AS
SELECT
    fx.enterprise_key,
    fx.from_currency,
    fx.to_currency,
    fx.rate_date,
    fx.fx_rate,
    fx.rate_type,
    'bloomberg'                             AS _source_pref,
    CAST(array() AS ARRAY<STRING>)          AS _sources_in_conflict,
    fx.loaded_at                            AS bronze_loaded_at
FROM raw_bloomberg.fx_rate_raw fx;

SELECT 'bronze.views complete' AS status,
       count(*) AS bronze_view_count
FROM information_schema.views
WHERE table_schema = 'bronze'
  AND table_name LIKE 'v%';
