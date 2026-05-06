-- ============================================================================
-- 03_silver/04_materialized_views.sql
-- 23 silver mv<entity> materialized views.
--
-- Bodies are byte-identical to investments.v<entity> in 03_views.sql (modulo
-- `CREATE OR REPLACE VIEW <name>` -> `CREATE OR REPLACE MATERIALIZED VIEW
-- <name>`). DECISIONS.md #6 contract.
--
-- Note on cascading: each MV's internal body still references the v* upstream
-- artifacts (NOT mv*), to keep view/MV body equality. The cascading speedup
-- comes from queries hitting the MV at their target layer, not from MVs
-- referencing other MVs internally.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 4.1 mvsecurity_dim -----------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvsecurity_dim AS
WITH ordered AS (
    SELECT s.*,
        ROW_NUMBER() OVER (PARTITION BY s.enterprise_key ORDER BY s.issue_date NULLS LAST, s.loaded_at) AS chain_pos,
        COUNT(*)     OVER (PARTITION BY s.enterprise_key) AS chain_len,
        ROW_NUMBER() OVER (ORDER BY s.enterprise_key, s.issue_date NULLS LAST, s.loaded_at) AS security_sk
    FROM raw_aspen.security_master_raw s
)
SELECT o.security_sk, o.enterprise_key,
    COALESCE(o.issue_date, DATE'1900-01-01') AS effective_start_date,
    COALESCE(date_sub(LEAD(o.issue_date) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos), 1), DATE'9999-12-31') AS effective_end_date,
    (o.chain_pos = o.chain_len) AS is_current,
    LAG(o.security_sk)  OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS preceding_record_sk,
    LEAD(o.security_sk) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS succeeding_record_sk,
    o.security_name, o.security_type, o.asset_class, o.sub_asset_class, o.issue_date, o.maturity_date,
    o.coupon_rate, o.currency_code,
    bronze.fn_resolve_enterprise_key('aspen', o.issuer_source_key) AS issuer_enterprise_key,
    o.isin_code, o.cusip_code,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o;

-- 4.2 mvsecurity_rating_dim ----------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvsecurity_rating_dim AS
WITH ordered AS (
    SELECT sr.*,
        ROW_NUMBER() OVER (PARTITION BY sr.enterprise_key ORDER BY sr.rating_date, sr.loaded_at) AS chain_pos,
        COUNT(*)     OVER (PARTITION BY sr.enterprise_key) AS chain_len,
        ROW_NUMBER() OVER (ORDER BY sr.enterprise_key, sr.rating_date, sr.loaded_at) AS security_rating_sk
    FROM raw_aspen.security_rating_raw sr
)
SELECT o.security_rating_sk, o.enterprise_key,
    o.rating_date AS effective_start_date,
    COALESCE(date_sub(LEAD(o.rating_date) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos), 1), DATE'9999-12-31') AS effective_end_date,
    (o.chain_pos = o.chain_len) AS is_current,
    LAG(o.security_rating_sk)  OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS preceding_record_sk,
    LEAD(o.security_rating_sk) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS succeeding_record_sk,
    bronze.fn_resolve_enterprise_key('aspen', o.security_source_key) AS security_enterprise_key,
    o.rating_agency, o.rating_value, o.rating_outlook, o.rating_action_type,
    CASE o.rating_value
        WHEN 'AAA' THEN 1 WHEN 'AA' THEN 2 WHEN 'A' THEN 3 WHEN 'BBB' THEN 4
        WHEN 'BB'  THEN 5 WHEN 'B'  THEN 6 WHEN 'CCC' THEN 7 WHEN 'D' THEN 10
        ELSE NULL
    END AS rating_numeric_score,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o;

-- 4.3 mvcontract_dim -----------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvcontract_dim AS
WITH ordered AS (
    SELECT c.*,
        ROW_NUMBER() OVER (PARTITION BY c.enterprise_key ORDER BY c.signing_date NULLS LAST, c.loaded_at) AS chain_pos,
        COUNT(*)     OVER (PARTITION BY c.enterprise_key) AS chain_len,
        ROW_NUMBER() OVER (ORDER BY c.enterprise_key, c.signing_date NULLS LAST, c.loaded_at) AS contract_sk
    FROM raw_efront.contract_raw c
)
SELECT o.contract_sk, o.enterprise_key,
    COALESCE(o.signing_date, DATE'1900-01-01') AS effective_start_date,
    COALESCE(date_sub(LEAD(o.signing_date) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos), 1), DATE'9999-12-31') AS effective_end_date,
    (o.chain_pos = o.chain_len) AS is_current,
    LAG(o.contract_sk)  OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS preceding_record_sk,
    LEAD(o.contract_sk) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS succeeding_record_sk,
    o.contract_name,
    bronze.fn_resolve_enterprise_key('aspen', o.entity_source_key) AS entity_enterprise_key,
    o.contract_type, o.signing_date, o.maturity_date, o.principal_local, o.currency_code,
    o.coupon_type, o.coupon_rate, o.spread_over_benchmark, o.benchmark_code, o.status,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o;

-- 4.4 mvportfolio_dim ----------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvportfolio_dim AS
WITH portfolios AS (
    SELECT r.portfolio_source_key, r.enterprise_key, r.portfolio_name, r.strategy_name, r.loaded_at,
        ROW_NUMBER() OVER (PARTITION BY r.portfolio_source_key ORDER BY r.risk_date DESC, r.loaded_at DESC) AS _rn
    FROM raw_aladdin.portfolio_risk_raw r
),
ordered AS (
    SELECT p.*, DATE'2010-01-01' AS effective_start_date,
        ROW_NUMBER() OVER (ORDER BY p.enterprise_key) AS portfolio_sk
    FROM portfolios p WHERE p._rn = 1
)
SELECT o.portfolio_sk, o.enterprise_key, o.effective_start_date,
    DATE'9999-12-31' AS effective_end_date, TRUE AS is_current,
    CAST(NULL AS BIGINT) AS preceding_record_sk, CAST(NULL AS BIGINT) AS succeeding_record_sk,
    o.portfolio_name, o.strategy_name,
    bronze.fn_resolve_enterprise_key('internal_admin',
        element_at(array('BU_PD_DL','BU_PD_DI','BU_PD_MZ','BU_PD_RE','BU_PD_SF','BU_RE_C','BU_RE_VA','BU_PE_BO','BU_INFRA','BU_PUB'),
                   try_cast(substr(o.portfolio_source_key, length(o.portfolio_source_key) - 1) AS INT))
    ) AS business_unit_enterprise_key,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o;

-- 4.5 mventity_dim -------------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mventity_dim AS
WITH ordered AS (
    SELECT e.*,
        ROW_NUMBER() OVER (PARTITION BY e.enterprise_key ORDER BY e.formation_date NULLS LAST, e.loaded_at) AS chain_pos,
        COUNT(*)     OVER (PARTITION BY e.enterprise_key) AS chain_len,
        ROW_NUMBER() OVER (ORDER BY e.enterprise_key, e.formation_date NULLS LAST, e.loaded_at) AS entity_sk
    FROM raw_aspen.entity_master_raw e
),
contracts_per_entity AS (SELECT DISTINCT entity_source_key FROM raw_efront.contract_raw)
SELECT o.entity_sk, o.enterprise_key,
    COALESCE(o.formation_date, DATE'1900-01-01') AS effective_start_date,
    COALESCE(date_sub(LEAD(o.formation_date) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos), 1), DATE'9999-12-31') AS effective_end_date,
    (o.chain_pos = o.chain_len) AS is_current,
    LAG(o.entity_sk)  OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS preceding_record_sk,
    LEAD(o.entity_sk) OVER (PARTITION BY o.enterprise_key ORDER BY o.chain_pos) AS succeeding_record_sk,
    o.entity_name, o.entity_type, o.legal_structure, o.jurisdiction, o.tax_id,
    o.formation_date, o.dissolution_date,
    bronze.fn_resolve_enterprise_key('aspen', o.parent_entity_source_key) AS parent_entity_enterprise_key,
    o.is_active, o.country, (cpe.entity_source_key IS NOT NULL) AS has_contracts,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o
LEFT JOIN contracts_per_entity cpe ON cpe.entity_source_key = o.source_key;

-- 4.6 mvsecurity_industry_dim --------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvsecurity_industry_dim AS
WITH ordered AS (
    SELECT ic.*,
        ROW_NUMBER() OVER (ORDER BY ic.classification_system, ic.classification_level, ic.classification_code) AS industry_sk
    FROM raw_aspen.industry_classification_raw ic
)
SELECT o.industry_sk, o.enterprise_key,
    DATE'1900-01-01' AS effective_start_date, DATE'9999-12-31' AS effective_end_date, TRUE AS is_current,
    CAST(NULL AS BIGINT) AS preceding_record_sk, CAST(NULL AS BIGINT) AS succeeding_record_sk,
    o.classification_code, o.classification_name, o.parent_code, o.classification_level, o.classification_system,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o;

-- 4.7 mvreporting_group_dim ----------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvreporting_group_dim AS
WITH ordered AS (
    SELECT rg.*,
        ROW_NUMBER() OVER (ORDER BY rg.group_type, rg.group_level, rg.group_code) AS reporting_group_sk
    FROM raw_aspen.reporting_group_raw rg
)
SELECT o.reporting_group_sk, o.enterprise_key,
    DATE'1900-01-01' AS effective_start_date, DATE'9999-12-31' AS effective_end_date, TRUE AS is_current,
    CAST(NULL AS BIGINT) AS preceding_record_sk, CAST(NULL AS BIGINT) AS succeeding_record_sk,
    o.group_code, o.group_name, o.parent_group_code, o.group_level, o.group_type,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o;

-- 4.8 mvbusiness_unit_dim ------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvbusiness_unit_dim AS
WITH ordered AS (
    SELECT bu.*,
        ROW_NUMBER() OVER (PARTITION BY bu.enterprise_key ORDER BY bu.established_date, bu.loaded_at) AS chain_pos,
        COUNT(*)     OVER (PARTITION BY bu.enterprise_key) AS chain_len,
        ROW_NUMBER() OVER (ORDER BY bu.established_date, bu.bu_code) AS business_unit_sk
    FROM raw_internal_admin.business_unit_master_raw bu
),
risk_team_codes AS (SELECT collect_set(DISTINCT risk_team_code) AS team_codes FROM raw_aladdin.compliance_check_raw)
SELECT o.business_unit_sk, o.enterprise_key,
    o.established_date AS effective_start_date, DATE'9999-12-31' AS effective_end_date,
    (o.chain_pos = o.chain_len) AS is_current,
    CAST(NULL AS BIGINT) AS preceding_record_sk, CAST(NULL AS BIGINT) AS succeeding_record_sk,
    o.bu_code, o.bu_name, o.bu_type,
    bronze.fn_resolve_enterprise_key('internal_admin', o.parent_bu_code) AS parent_bu_enterprise_key,
    o.asset_class_focus, o.strategy_name, (o.bu_code LIKE 'team_pd_%') AS is_pd_strategy,
    o.head_employee_id, o.established_date, o.is_active, rtc.team_codes AS associated_risk_team_codes,
    o.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM ordered o CROSS JOIN risk_team_codes rtc;

-- 4.9 mvfx_rate_dim ------------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvfx_rate_dim AS
SELECT
    ROW_NUMBER() OVER (ORDER BY fx.rate_date, fx.from_currency, fx.to_currency) AS fx_rate_sk,
    fx.enterprise_key, fx.from_currency, fx.to_currency, fx.rate_date, fx.fx_rate, fx.rate_type,
    fx.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM raw_bloomberg.fx_rate_raw fx;

-- 4.10 mvposition_analytics_fact -----------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvposition_analytics_fact AS
WITH bp_latest AS (
    SELECT * FROM (
        SELECT bp.*, ROW_NUMBER() OVER (PARTITION BY bp.enterprise_key ORDER BY bp.bronze_loaded_at DESC) AS _rn
        FROM bronze.mvposition bp
    ) WHERE _rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY bp.enterprise_key) AS position_sk,
    bp.enterprise_key, bp.position_date, p_dim.portfolio_sk, s_dim.security_sk, p_dim_bu.business_unit_sk,
    bp.quantity, bp.market_value_local,
    CAST(bp.market_value_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS market_value_usd,
    bp.book_value_local,
    CAST(bp.book_value_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2))   AS book_value_usd,
    bp.cost_basis_local,
    CAST(bp.cost_basis_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2))   AS cost_basis_usd,
    bp.unrealized_gl_local,
    CAST(bp.unrealized_gl_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS unrealized_gl_usd,
    bp.unit_price_local, bp.currency_code, fx.fx_rate AS fx_rate_to_usd, bp.settlement_status,
    bp.bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM bp_latest bp
LEFT JOIN investments.mvportfolio_dim p_dim
    ON p_dim.enterprise_key = bp.portfolio_enterprise_key
   AND bp.position_date BETWEEN p_dim.effective_start_date AND p_dim.effective_end_date
LEFT JOIN investments.mvsecurity_dim s_dim
    ON s_dim.enterprise_key = bp.security_enterprise_key
   AND bp.position_date BETWEEN s_dim.effective_start_date AND s_dim.effective_end_date
LEFT JOIN investments.mvbusiness_unit_dim p_dim_bu
    ON p_dim_bu.enterprise_key = p_dim.business_unit_enterprise_key
   AND p_dim_bu.is_current = TRUE
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = bp.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = bp.position_date;

-- 4.11 mvposition_monthend_fact ------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvposition_monthend_fact AS
WITH monthends AS (
    SELECT last_day(position_date) AS monthend_date, portfolio_sk, security_sk, business_unit_sk, currency_code,
        SUM(quantity) AS quantity, SUM(market_value_local) AS market_value_local,
        SUM(market_value_usd) AS market_value_usd, SUM(book_value_local) AS book_value_local,
        SUM(cost_basis_usd) AS cost_basis_usd, SUM(unrealized_gl_usd) AS unrealized_gl_usd,
        MAX(bronze_loaded_at) AS bronze_loaded_at
    FROM investments.mvposition_analytics_fact
    WHERE position_date = last_day(position_date)
    GROUP BY last_day(position_date), portfolio_sk, security_sk, business_unit_sk, currency_code
)
SELECT
    ROW_NUMBER() OVER (ORDER BY monthend_date, portfolio_sk, security_sk) AS position_monthend_sk,
    monthend_date, portfolio_sk, security_sk, business_unit_sk, quantity,
    market_value_local, market_value_usd, book_value_local, cost_basis_usd, unrealized_gl_usd,
    currency_code, bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM monthends;

-- 4.12 mvsecurity_master_fact --------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvsecurity_master_fact AS
SELECT
    ROW_NUMBER() OVER (ORDER BY s.enterprise_key) AS security_master_sk,
    current_date() AS snapshot_date, s.security_sk, s.enterprise_key, s.security_name,
    s.asset_class, s.sub_asset_class, s.issue_date, s.maturity_date, s.coupon_rate, s.currency_code,
    s.issuer_enterprise_key,
    bs.latest_close_price AS latest_close_price_local,
    CAST(bs.latest_close_price * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 6)) AS latest_close_price_usd,
    datediff(s.maturity_date, current_date()) AS days_to_maturity,
    (s.maturity_date < current_date()) AS is_matured,
    s.bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM investments.mvsecurity_dim s
LEFT JOIN bronze.mvsecurity bs ON bs.enterprise_key = s.enterprise_key
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = bs.latest_close_price_currency AND fx.to_currency = 'USD' AND fx.rate_date = bs.latest_price_date
WHERE s.is_current = TRUE;

-- 4.13 mvsecurity_price_fact ---------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvsecurity_price_fact AS
SELECT
    ROW_NUMBER() OVER (ORDER BY bsp.enterprise_key) AS security_price_sk,
    bsp.enterprise_key, bsp.price_date, s_dim.security_sk, bsp.close_price_local,
    CAST(bsp.close_price_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 6)) AS close_price_usd,
    bsp.currency_code, fx.fx_rate AS fx_rate_to_usd, bsp.price_type,
    bsp.bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM bronze.mvsecurity_price bsp
LEFT JOIN investments.mvsecurity_dim s_dim
    ON s_dim.enterprise_key = bsp.security_enterprise_key
   AND bsp.price_date BETWEEN s_dim.effective_start_date AND s_dim.effective_end_date
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = bsp.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = bsp.price_date;

-- 4.14 mvcontract_details_fact -------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvcontract_details_fact AS
WITH covenant_breaches AS (
    SELECT contract_source_key, covenant_date,
        MAX(CASE WHEN covenant_status = 'TRIPPED' THEN 1 ELSE 0 END) > 0 AS has_active_breach
    FROM raw_efront.contract_covenant_raw GROUP BY contract_source_key, covenant_date
),
contract_key_map AS (
    SELECT DISTINCT enterprise_key, source_key AS contract_source_key
    FROM raw_efront.contract_raw
    WHERE source_key NOT LIKE '%\\_v2' ESCAPE '\\'
)
SELECT
    ROW_NUMBER() OVER (ORDER BY bc.enterprise_key) AS contract_details_sk,
    bc.enterprise_key, current_date() AS detail_date, c_dim.contract_sk, e_dim.entity_sk,
    bc.contract_type, bc.principal_local,
    CAST(bc.principal_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS principal_usd,
    bc.coupon_rate, bc.spread_over_benchmark, datediff(bc.maturity_date, current_date()) AS days_to_maturity,
    bc.status, COALESCE(cb.has_active_breach, FALSE) AS has_active_breach,
    bc.bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM bronze.mvcontract bc
LEFT JOIN investments.mvcontract_dim c_dim ON c_dim.enterprise_key = bc.enterprise_key AND c_dim.is_current = TRUE
LEFT JOIN investments.mventity_dim e_dim ON e_dim.enterprise_key = bc.entity_enterprise_key AND e_dim.is_current = TRUE
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = bc.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = current_date()
LEFT JOIN contract_key_map ckm ON ckm.enterprise_key = bc.enterprise_key
LEFT JOIN covenant_breaches cb
    ON cb.contract_source_key = ckm.contract_source_key
   AND cb.covenant_date = current_date();

-- 4.15 mvcontract_summary_fact -------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvcontract_summary_fact AS
WITH cs_resolved AS (
    SELECT cs.*, cw.enterprise_key AS contract_enterprise_key
    FROM raw_efront.contract_summary_raw cs
    LEFT JOIN bronze.crosswalk cw
        ON cw.source_system = 'efront'
       AND cw.source_key    = cs.contract_source_key
       AND cw.mapping_active = TRUE
)
SELECT
    ROW_NUMBER() OVER (ORDER BY cs.enterprise_key, cs.summary_date) AS contract_summary_sk,
    cs.enterprise_key, cs.summary_date, c_dim.contract_sk,
    cs.outstanding_principal_local,
    CAST(cs.outstanding_principal_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS outstanding_principal_usd,
    cs.accrued_interest_local,
    CAST(cs.accrued_interest_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS accrued_interest_usd,
    cs.paid_to_date_local,
    CAST(cs.paid_to_date_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS paid_to_date_usd,
    cs.currency_code, fx.fx_rate AS fx_rate_to_usd, cs.performance_status,
    cs.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM cs_resolved cs
LEFT JOIN investments.mvcontract_dim c_dim
    ON c_dim.enterprise_key = cs.contract_enterprise_key
   AND cs.summary_date BETWEEN c_dim.effective_start_date AND c_dim.effective_end_date
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = cs.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = cs.summary_date;

-- 4.16 mvportfolio_analytics_fact ----------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvportfolio_analytics_fact AS
SELECT
    ROW_NUMBER() OVER (ORDER BY r.enterprise_key, r.risk_date) AS portfolio_analytics_sk,
    r.risk_date AS analytics_date, p_dim.portfolio_sk, p_dim_bu.business_unit_sk,
    r.var_95, r.var_99, r.expected_shortfall, r.beta, r.tracking_error,
    perf.period_return_pct, perf.ytd_return_pct, perf.since_inception_return_pct,
    perf.benchmark_return_pct, perf.benchmark_code,
    r.bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM bronze.mvportfolio_risk r
LEFT JOIN bronze.mvportfolio_performance perf
    ON perf.portfolio_enterprise_key = r.portfolio_enterprise_key AND perf.performance_date = r.risk_date
LEFT JOIN investments.mvportfolio_dim p_dim
    ON p_dim.enterprise_key = r.portfolio_enterprise_key
   AND r.risk_date BETWEEN p_dim.effective_start_date AND p_dim.effective_end_date
LEFT JOIN investments.mvbusiness_unit_dim p_dim_bu
    ON p_dim_bu.enterprise_key = p_dim.business_unit_enterprise_key AND p_dim_bu.is_current = TRUE;

-- 4.17 mvportfolio_analytics_monthend_fact -------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvportfolio_analytics_monthend_fact AS
WITH aggregated AS (
    SELECT
        last_day(analytics_date) AS monthend_date,
        portfolio_sk,
        business_unit_sk,
        MAX(var_95)               AS monthend_var_95,
        MAX(var_99)               AS monthend_var_99,
        AVG(period_return_pct)    AS period_return_pct,
        MAX(ytd_return_pct)       AS ytd_return_pct,
        AVG(benchmark_return_pct) AS benchmark_return_pct,
        MAX(bronze_loaded_at)     AS bronze_loaded_at
    FROM investments.mvportfolio_analytics_fact
    WHERE analytics_date = last_day(analytics_date)
    GROUP BY last_day(analytics_date), portfolio_sk, business_unit_sk
)
SELECT
    ROW_NUMBER() OVER (ORDER BY portfolio_sk, monthend_date) AS portfolio_analytics_monthend_sk,
    monthend_date, portfolio_sk, business_unit_sk,
    monthend_var_95, monthend_var_99, period_return_pct, ytd_return_pct, benchmark_return_pct,
    bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM aggregated;

-- 4.18 mvtransactions_collateral_exposure_fact ---------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvtransactions_collateral_exposure_fact AS
SELECT
    ROW_NUMBER() OVER (ORDER BY bcx.enterprise_key) AS collateral_exposure_sk,
    bcx.enterprise_key, bcx.exposure_date, c_dim.contract_sk,
    bcx.exposure_amount_local,
    CAST(bcx.exposure_amount_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS exposure_amount_usd,
    bcx.collateral_value_local,
    CAST(bcx.collateral_value_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS collateral_value_usd,
    bcx.currency_code, fx.fx_rate AS fx_rate_to_usd, bcx.collateral_type, bcx.ltv_pct,
    bcx.bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM bronze.mvcollateral bcx
LEFT JOIN investments.mvcontract_dim c_dim
    ON c_dim.enterprise_key = bcx.contract_enterprise_key
   AND bcx.exposure_date BETWEEN c_dim.effective_start_date AND c_dim.effective_end_date
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = bcx.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = bcx.exposure_date;

-- 4.19 mvtransactions_collateral_positions_fact --------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvtransactions_collateral_positions_fact AS
WITH cp_resolved AS (
    SELECT cp.*,
           cw_c.enterprise_key AS contract_enterprise_key,
           cw_s.enterprise_key AS security_enterprise_key
    FROM raw_efront.collateral_position_raw cp
    LEFT JOIN bronze.crosswalk cw_c
        ON cw_c.source_system = 'efront'
       AND cw_c.source_key    = cp.contract_source_key
       AND cw_c.mapping_active = TRUE
    LEFT JOIN bronze.crosswalk cw_s
        ON cw_s.source_system = 'aspen'
       AND cw_s.source_key    = cp.security_source_key
       AND cw_s.mapping_active = TRUE
)
SELECT
    ROW_NUMBER() OVER (ORDER BY cp.enterprise_key) AS collateral_position_sk,
    cp.enterprise_key, cp.position_date, c_dim.contract_sk, s_dim.security_sk,
    bronze.fn_resolve_enterprise_key('aspen', cp.asset_source_key) AS asset_enterprise_key,
    cp.position_value_local,
    CAST(cp.position_value_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS position_value_usd,
    cp.currency_code, fx.fx_rate AS fx_rate_to_usd, cp.collateral_role,
    cp.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM cp_resolved cp
LEFT JOIN investments.mvcontract_dim c_dim
    ON c_dim.enterprise_key = cp.contract_enterprise_key
   AND cp.position_date BETWEEN c_dim.effective_start_date AND c_dim.effective_end_date
LEFT JOIN investments.mvsecurity_dim s_dim
    ON s_dim.enterprise_key = cp.security_enterprise_key
   AND cp.position_date BETWEEN s_dim.effective_start_date AND s_dim.effective_end_date
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = cp.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = cp.position_date;

-- 4.20 mvcontract_details_cancels_fact -----------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvcontract_details_cancels_fact AS
WITH amendments AS (
    SELECT regexp_replace(c2.source_key, '_v2$', '') AS original_source_key,
        c2.signing_date AS amendment_date,
        c1.principal_local AS original_principal_local, c1.currency_code AS original_currency_code,
        c2.loaded_at,
        cw.enterprise_key AS original_enterprise_key
    FROM raw_efront.contract_raw c2
    JOIN raw_efront.contract_raw c1 ON c1.source_key = regexp_replace(c2.source_key, '_v2$', '')
    LEFT JOIN bronze.crosswalk cw
        ON cw.source_system = 'efront'
       AND cw.source_key    = regexp_replace(c2.source_key, '_v2$', '')
       AND cw.mapping_active = TRUE
    WHERE c2.source_key LIKE '%\\_v2' ESCAPE '\\'
)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.amendment_date) AS cancel_sk,
    c1_dim.contract_sk AS cancelled_contract_details_sk, c1_dim.contract_sk AS contract_sk,
    a.amendment_date AS cancel_event_date, CAST(NULL AS DATE) AS original_detail_date,
    'AMENDMENT' AS cancel_reason,
    CAST(a.original_principal_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS cancelled_principal_usd,
    a.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM amendments a
LEFT JOIN investments.mvcontract_dim c1_dim
    ON c1_dim.enterprise_key = a.original_enterprise_key
   AND c1_dim.is_current = FALSE
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = a.original_currency_code AND fx.to_currency = 'USD' AND fx.rate_date = a.amendment_date;

-- 4.21 mvposition_cancels_fact -------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvposition_cancels_fact AS
WITH p_resolved AS (
    SELECT p.*,
           cw_p.enterprise_key AS portfolio_enterprise_key,
           cw_s.enterprise_key AS security_enterprise_key
    FROM raw_state_street.position_raw p
    LEFT JOIN bronze.crosswalk cw_p
        ON cw_p.source_system = 'state_street'
       AND cw_p.source_key    = p.portfolio_source_key
       AND cw_p.mapping_active = TRUE
    LEFT JOIN bronze.crosswalk cw_s
        ON cw_s.source_system = 'aspen'
       AND cw_s.source_key    = p.security_source_key
       AND cw_s.mapping_active = TRUE
    WHERE p.enterprise_key LIKE 'REMAPPED\\_%' ESCAPE '\\'
)
SELECT
    ROW_NUMBER() OVER (ORDER BY p.position_date) AS cancel_sk,
    CAST(p.source_key AS BIGINT) AS cancelled_position_sk,
    p_dim.portfolio_sk, s_dim.security_sk, p.position_date AS cancel_event_date,
    p.position_date AS original_position_date, 'CROSSWALK_REMAP' AS cancel_reason,
    CAST(p.market_value_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS cancelled_market_value_usd,
    p.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM p_resolved p
LEFT JOIN investments.mvportfolio_dim p_dim
    ON p_dim.enterprise_key = p.portfolio_enterprise_key
   AND p_dim.is_current = TRUE
LEFT JOIN investments.mvsecurity_dim s_dim
    ON s_dim.enterprise_key = p.security_enterprise_key
   AND p.position_date BETWEEN s_dim.effective_start_date AND s_dim.effective_end_date
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = p.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = p.position_date;

-- 4.22 mvsecurity_price_cancels_fact -------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvsecurity_price_cancels_fact AS
SELECT
    CAST(NULL AS BIGINT) AS cancel_sk, CAST(NULL AS BIGINT) AS cancelled_security_price_sk,
    CAST(NULL AS BIGINT) AS security_sk, CAST(NULL AS DATE) AS cancel_event_date,
    CAST(NULL AS DATE) AS original_price_date, CAST(NULL AS STRING) AS cancel_reason,
    CAST(NULL AS DECIMAL(18, 6)) AS cancelled_close_price_usd,
    CAST(NULL AS TIMESTAMP) AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
WHERE 1 = 0;

-- 4.23 mvincome_bridge ---------------------------------------------------------
CREATE OR REPLACE MATERIALIZED VIEW investments.mvincome_bridge AS
WITH cf_resolved AS (
    SELECT cf.*, cw.enterprise_key AS portfolio_enterprise_key
    FROM raw_state_street.cash_flow_raw cf
    LEFT JOIN bronze.crosswalk cw
        ON cw.source_system = 'state_street'
       AND cw.source_key    = cf.portfolio_source_key
       AND cw.mapping_active = TRUE
    WHERE cf.cash_flow_type = 'INCOME'
)
SELECT
    ROW_NUMBER() OVER (ORDER BY cf.cash_flow_date, cf.portfolio_source_key) AS income_bridge_sk,
    p_dim.portfolio_sk, CAST(NULL AS BIGINT) AS security_sk, CAST(NULL AS BIGINT) AS contract_sk,
    cf.cash_flow_date AS income_date, 'COUPON' AS income_type, cf.amount_local AS income_amount_local,
    CAST(cf.amount_local * COALESCE(fx.fx_rate, 1.0) AS DECIMAL(18, 2)) AS income_amount_usd,
    cf.currency_code, cf.loaded_at AS bronze_loaded_at, current_timestamp() AS silver_loaded_at
FROM cf_resolved cf
LEFT JOIN investments.mvportfolio_dim p_dim
    ON p_dim.enterprise_key = cf.portfolio_enterprise_key
   AND p_dim.is_current = TRUE
LEFT JOIN investments.mvfx_rate_dim fx
    ON fx.from_currency = cf.currency_code AND fx.to_currency = 'USD' AND fx.rate_date = cf.cash_flow_date;

SELECT 'silver.materialized_views complete' AS status,
       count(*) AS silver_mv_count
FROM information_schema.tables
WHERE table_schema = 'investments' AND table_name LIKE 'mv%';
