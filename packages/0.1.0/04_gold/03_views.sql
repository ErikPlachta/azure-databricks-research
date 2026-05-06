-- ============================================================================
-- 04_gold/03_views.sql
-- Gold per-team views: 50 v<entity> across 5 PD teams.
--
-- Pattern per team:
--   Filter silver investments.* to team's bu_code; add team-derived columns
--   where applicable (concentration_pct, portfolio_rank on position;
--   vintage_year on contract_details).
--
-- Bodies MUST stay byte-identical to mv<entity> in 04_materialized_views.sql.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- team_pd_direct_lending (10 views)
-- ============================================================================

CREATE OR REPLACE VIEW team_pd_direct_lending.vposition_analytics_fact AS
WITH team_positions AS (
    SELECT p.*
    FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu
        ON bu.business_unit_sk = p.business_unit_sk
       AND bu.is_current = TRUE
       AND bu.bu_code = 'team_pd_direct_lending'
)
SELECT
    position_sk, enterprise_key, position_date, portfolio_sk, security_sk, business_unit_sk,
    quantity, market_value_usd, book_value_usd, cost_basis_usd, unrealized_gl_usd,
    market_value_usd / NULLIF(SUM(market_value_usd) OVER (PARTITION BY position_date), 0) AS concentration_pct,
    CAST(DENSE_RANK() OVER (PARTITION BY position_date ORDER BY market_value_usd DESC) AS INT) AS portfolio_rank,
    currency_code, silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM team_positions;

CREATE OR REPLACE VIEW team_pd_direct_lending.vcontract_details_fact AS
SELECT
    c.contract_details_sk, c.enterprise_key, c.detail_date, c.contract_sk, c.entity_sk,
    c.contract_type, c.principal_usd, c.coupon_rate, c.spread_over_benchmark,
    c.days_to_maturity, c.status, c.has_active_breach,
    YEAR(cd.signing_date) AS vintage_year,
    c.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_details_fact c
LEFT JOIN investments.vcontract_dim cd ON cd.contract_sk = c.contract_sk AND cd.is_current = TRUE
JOIN investments.ventity_dim e ON e.entity_sk = c.entity_sk AND e.is_current = TRUE
JOIN investments.vposition_analytics_fact p ON p.security_sk IN (
    SELECT DISTINCT security_sk FROM investments.vposition_analytics_fact pp
    JOIN investments.vbusiness_unit_dim bu
        ON bu.business_unit_sk = pp.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_direct_lending'
);

CREATE OR REPLACE VIEW team_pd_direct_lending.vcontract_summary_fact AS
SELECT cs.contract_summary_sk, cs.enterprise_key, cs.summary_date, cs.contract_sk,
    cs.outstanding_principal_usd, cs.accrued_interest_usd, cs.paid_to_date_usd,
    cs.performance_status, cs.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_summary_fact cs
WHERE cs.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_direct_lending.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_direct_lending.vportfolio_analytics_fact AS
SELECT pa.portfolio_analytics_sk, pa.analytics_date, pa.portfolio_sk, pa.business_unit_sk,
    pa.var_95, pa.var_99, pa.expected_shortfall, pa.period_return_pct, pa.ytd_return_pct,
    pa.benchmark_return_pct, pa.benchmark_code, pa.silver_loaded_at,
    current_timestamp() AS gold_loaded_at
FROM investments.vportfolio_analytics_fact pa
JOIN investments.vbusiness_unit_dim bu
    ON bu.business_unit_sk = pa.business_unit_sk AND bu.is_current = TRUE
   AND bu.bu_code = 'team_pd_direct_lending';

CREATE OR REPLACE VIEW team_pd_direct_lending.vsecurity_dim AS
WITH team_secs AS (
    SELECT DISTINCT p.security_sk
    FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu
        ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE
       AND bu.bu_code = 'team_pd_direct_lending'
)
SELECT s.security_sk, s.enterprise_key, s.effective_start_date, s.effective_end_date, s.is_current,
    s.security_name, s.asset_class, s.sub_asset_class, s.issue_date, s.maturity_date,
    s.coupon_rate, s.currency_code, s.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_dim s
JOIN team_secs ts ON ts.security_sk = s.security_sk;

CREATE OR REPLACE VIEW team_pd_direct_lending.vsecurity_master_fact AS
SELECT m.security_master_sk, m.snapshot_date, m.security_sk, m.enterprise_key, m.security_name,
    m.asset_class, m.latest_close_price_usd, m.days_to_maturity, m.is_matured,
    m.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_master_fact m
WHERE m.security_sk IN (SELECT security_sk FROM team_pd_direct_lending.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_direct_lending.vsecurity_price_fact AS
SELECT sp.security_price_sk, sp.enterprise_key, sp.price_date, sp.security_sk,
    sp.close_price_usd, sp.currency_code, sp.price_type,
    sp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_price_fact sp
WHERE sp.security_sk IN (SELECT security_sk FROM team_pd_direct_lending.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_direct_lending.vsecurity_rating_dim AS
SELECT sr.security_rating_sk, sr.enterprise_key, sr.effective_start_date, sr.effective_end_date,
    sr.is_current, sr.security_enterprise_key, sr.rating_agency, sr.rating_value,
    sr.rating_outlook, sr.rating_numeric_score,
    sr.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_rating_dim sr
WHERE sr.security_enterprise_key IN (SELECT enterprise_key FROM team_pd_direct_lending.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_direct_lending.vtransactions_collateral_exposure_fact AS
SELECT ce.collateral_exposure_sk, ce.enterprise_key, ce.exposure_date, ce.contract_sk,
    ce.exposure_amount_usd, ce.collateral_value_usd, ce.collateral_type, ce.ltv_pct,
    ce.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_exposure_fact ce
WHERE ce.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_direct_lending.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_direct_lending.vtransactions_collateral_positions_fact AS
SELECT cp.collateral_position_sk, cp.enterprise_key, cp.position_date, cp.contract_sk,
    cp.security_sk, cp.position_value_usd, cp.collateral_role,
    cp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_positions_fact cp
WHERE cp.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_direct_lending.vcontract_details_fact);

-- ============================================================================
-- Other 4 teams: identical bodies modulo bu_code filter literal.
-- ============================================================================

CREATE OR REPLACE VIEW team_pd_distressed.vposition_analytics_fact AS
WITH team_positions AS (
    SELECT p.* FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_distressed'
)
SELECT position_sk, enterprise_key, position_date, portfolio_sk, security_sk, business_unit_sk,
    quantity, market_value_usd, book_value_usd, cost_basis_usd, unrealized_gl_usd,
    market_value_usd / NULLIF(SUM(market_value_usd) OVER (PARTITION BY position_date), 0) AS concentration_pct,
    CAST(DENSE_RANK() OVER (PARTITION BY position_date ORDER BY market_value_usd DESC) AS INT) AS portfolio_rank,
    currency_code, silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM team_positions;

CREATE OR REPLACE VIEW team_pd_distressed.vcontract_details_fact AS
SELECT c.contract_details_sk, c.enterprise_key, c.detail_date, c.contract_sk, c.entity_sk,
    c.contract_type, c.principal_usd, c.coupon_rate, c.spread_over_benchmark,
    c.days_to_maturity, c.status, c.has_active_breach,
    YEAR(cd.signing_date) AS vintage_year,
    c.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_details_fact c
LEFT JOIN investments.vcontract_dim cd ON cd.contract_sk = c.contract_sk AND cd.is_current = TRUE
WHERE c.contract_sk IN (
    SELECT DISTINCT cp.contract_sk FROM investments.vtransactions_collateral_positions_fact cp
    JOIN investments.vposition_analytics_fact p ON p.security_sk = cp.security_sk
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_distressed'
);

CREATE OR REPLACE VIEW team_pd_distressed.vcontract_summary_fact AS
SELECT cs.contract_summary_sk, cs.enterprise_key, cs.summary_date, cs.contract_sk,
    cs.outstanding_principal_usd, cs.accrued_interest_usd, cs.paid_to_date_usd,
    cs.performance_status, cs.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_summary_fact cs
WHERE cs.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_distressed.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_distressed.vportfolio_analytics_fact AS
SELECT pa.portfolio_analytics_sk, pa.analytics_date, pa.portfolio_sk, pa.business_unit_sk,
    pa.var_95, pa.var_99, pa.expected_shortfall, pa.period_return_pct, pa.ytd_return_pct,
    pa.benchmark_return_pct, pa.benchmark_code, pa.silver_loaded_at,
    current_timestamp() AS gold_loaded_at
FROM investments.vportfolio_analytics_fact pa
JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = pa.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_distressed';

CREATE OR REPLACE VIEW team_pd_distressed.vsecurity_dim AS
WITH team_secs AS (
    SELECT DISTINCT p.security_sk FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_distressed'
)
SELECT s.security_sk, s.enterprise_key, s.effective_start_date, s.effective_end_date, s.is_current,
    s.security_name, s.asset_class, s.sub_asset_class, s.issue_date, s.maturity_date,
    s.coupon_rate, s.currency_code, s.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_dim s JOIN team_secs ts ON ts.security_sk = s.security_sk;

CREATE OR REPLACE VIEW team_pd_distressed.vsecurity_master_fact AS
SELECT m.security_master_sk, m.snapshot_date, m.security_sk, m.enterprise_key, m.security_name,
    m.asset_class, m.latest_close_price_usd, m.days_to_maturity, m.is_matured,
    m.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_master_fact m
WHERE m.security_sk IN (SELECT security_sk FROM team_pd_distressed.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_distressed.vsecurity_price_fact AS
SELECT sp.security_price_sk, sp.enterprise_key, sp.price_date, sp.security_sk,
    sp.close_price_usd, sp.currency_code, sp.price_type,
    sp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_price_fact sp
WHERE sp.security_sk IN (SELECT security_sk FROM team_pd_distressed.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_distressed.vsecurity_rating_dim AS
SELECT sr.security_rating_sk, sr.enterprise_key, sr.effective_start_date, sr.effective_end_date,
    sr.is_current, sr.security_enterprise_key, sr.rating_agency, sr.rating_value,
    sr.rating_outlook, sr.rating_numeric_score,
    sr.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_rating_dim sr
WHERE sr.security_enterprise_key IN (SELECT enterprise_key FROM team_pd_distressed.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_distressed.vtransactions_collateral_exposure_fact AS
SELECT ce.collateral_exposure_sk, ce.enterprise_key, ce.exposure_date, ce.contract_sk,
    ce.exposure_amount_usd, ce.collateral_value_usd, ce.collateral_type, ce.ltv_pct,
    ce.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_exposure_fact ce
WHERE ce.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_distressed.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_distressed.vtransactions_collateral_positions_fact AS
SELECT cp.collateral_position_sk, cp.enterprise_key, cp.position_date, cp.contract_sk,
    cp.security_sk, cp.position_value_usd, cp.collateral_role,
    cp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_positions_fact cp
WHERE cp.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_distressed.vcontract_details_fact);

-- team_pd_mezzanine ----------------------------------------------------------
CREATE OR REPLACE VIEW team_pd_mezzanine.vposition_analytics_fact AS
WITH team_positions AS (
    SELECT p.* FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_mezzanine'
)
SELECT position_sk, enterprise_key, position_date, portfolio_sk, security_sk, business_unit_sk,
    quantity, market_value_usd, book_value_usd, cost_basis_usd, unrealized_gl_usd,
    market_value_usd / NULLIF(SUM(market_value_usd) OVER (PARTITION BY position_date), 0) AS concentration_pct,
    CAST(DENSE_RANK() OVER (PARTITION BY position_date ORDER BY market_value_usd DESC) AS INT) AS portfolio_rank,
    currency_code, silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM team_positions;

CREATE OR REPLACE VIEW team_pd_mezzanine.vcontract_details_fact AS
SELECT c.contract_details_sk, c.enterprise_key, c.detail_date, c.contract_sk, c.entity_sk,
    c.contract_type, c.principal_usd, c.coupon_rate, c.spread_over_benchmark,
    c.days_to_maturity, c.status, c.has_active_breach,
    YEAR(cd.signing_date) AS vintage_year,
    c.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_details_fact c
LEFT JOIN investments.vcontract_dim cd ON cd.contract_sk = c.contract_sk AND cd.is_current = TRUE
WHERE c.contract_sk IN (
    SELECT DISTINCT cp.contract_sk FROM investments.vtransactions_collateral_positions_fact cp
    JOIN investments.vposition_analytics_fact p ON p.security_sk = cp.security_sk
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_mezzanine'
);

CREATE OR REPLACE VIEW team_pd_mezzanine.vcontract_summary_fact AS
SELECT cs.contract_summary_sk, cs.enterprise_key, cs.summary_date, cs.contract_sk,
    cs.outstanding_principal_usd, cs.accrued_interest_usd, cs.paid_to_date_usd,
    cs.performance_status, cs.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_summary_fact cs
WHERE cs.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_mezzanine.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_mezzanine.vportfolio_analytics_fact AS
SELECT pa.portfolio_analytics_sk, pa.analytics_date, pa.portfolio_sk, pa.business_unit_sk,
    pa.var_95, pa.var_99, pa.expected_shortfall, pa.period_return_pct, pa.ytd_return_pct,
    pa.benchmark_return_pct, pa.benchmark_code, pa.silver_loaded_at,
    current_timestamp() AS gold_loaded_at
FROM investments.vportfolio_analytics_fact pa
JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = pa.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_mezzanine';

CREATE OR REPLACE VIEW team_pd_mezzanine.vsecurity_dim AS
WITH team_secs AS (
    SELECT DISTINCT p.security_sk FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_mezzanine'
)
SELECT s.security_sk, s.enterprise_key, s.effective_start_date, s.effective_end_date, s.is_current,
    s.security_name, s.asset_class, s.sub_asset_class, s.issue_date, s.maturity_date,
    s.coupon_rate, s.currency_code, s.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_dim s JOIN team_secs ts ON ts.security_sk = s.security_sk;

CREATE OR REPLACE VIEW team_pd_mezzanine.vsecurity_master_fact AS
SELECT m.security_master_sk, m.snapshot_date, m.security_sk, m.enterprise_key, m.security_name,
    m.asset_class, m.latest_close_price_usd, m.days_to_maturity, m.is_matured,
    m.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_master_fact m
WHERE m.security_sk IN (SELECT security_sk FROM team_pd_mezzanine.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_mezzanine.vsecurity_price_fact AS
SELECT sp.security_price_sk, sp.enterprise_key, sp.price_date, sp.security_sk,
    sp.close_price_usd, sp.currency_code, sp.price_type,
    sp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_price_fact sp
WHERE sp.security_sk IN (SELECT security_sk FROM team_pd_mezzanine.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_mezzanine.vsecurity_rating_dim AS
SELECT sr.security_rating_sk, sr.enterprise_key, sr.effective_start_date, sr.effective_end_date,
    sr.is_current, sr.security_enterprise_key, sr.rating_agency, sr.rating_value,
    sr.rating_outlook, sr.rating_numeric_score,
    sr.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_rating_dim sr
WHERE sr.security_enterprise_key IN (SELECT enterprise_key FROM team_pd_mezzanine.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_mezzanine.vtransactions_collateral_exposure_fact AS
SELECT ce.collateral_exposure_sk, ce.enterprise_key, ce.exposure_date, ce.contract_sk,
    ce.exposure_amount_usd, ce.collateral_value_usd, ce.collateral_type, ce.ltv_pct,
    ce.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_exposure_fact ce
WHERE ce.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_mezzanine.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_mezzanine.vtransactions_collateral_positions_fact AS
SELECT cp.collateral_position_sk, cp.enterprise_key, cp.position_date, cp.contract_sk,
    cp.security_sk, cp.position_value_usd, cp.collateral_role,
    cp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_positions_fact cp
WHERE cp.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_mezzanine.vcontract_details_fact);

-- team_pd_real_estate_debt ----------------------------------------------------
CREATE OR REPLACE VIEW team_pd_real_estate_debt.vposition_analytics_fact AS
WITH team_positions AS (
    SELECT p.* FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_real_estate_debt'
)
SELECT position_sk, enterprise_key, position_date, portfolio_sk, security_sk, business_unit_sk,
    quantity, market_value_usd, book_value_usd, cost_basis_usd, unrealized_gl_usd,
    market_value_usd / NULLIF(SUM(market_value_usd) OVER (PARTITION BY position_date), 0) AS concentration_pct,
    CAST(DENSE_RANK() OVER (PARTITION BY position_date ORDER BY market_value_usd DESC) AS INT) AS portfolio_rank,
    currency_code, silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM team_positions;

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vcontract_details_fact AS
SELECT c.contract_details_sk, c.enterprise_key, c.detail_date, c.contract_sk, c.entity_sk,
    c.contract_type, c.principal_usd, c.coupon_rate, c.spread_over_benchmark,
    c.days_to_maturity, c.status, c.has_active_breach,
    YEAR(cd.signing_date) AS vintage_year,
    c.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_details_fact c
LEFT JOIN investments.vcontract_dim cd ON cd.contract_sk = c.contract_sk AND cd.is_current = TRUE
WHERE c.contract_sk IN (
    SELECT DISTINCT cp.contract_sk FROM investments.vtransactions_collateral_positions_fact cp
    JOIN investments.vposition_analytics_fact p ON p.security_sk = cp.security_sk
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_real_estate_debt'
);

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vcontract_summary_fact AS
SELECT cs.contract_summary_sk, cs.enterprise_key, cs.summary_date, cs.contract_sk,
    cs.outstanding_principal_usd, cs.accrued_interest_usd, cs.paid_to_date_usd,
    cs.performance_status, cs.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_summary_fact cs
WHERE cs.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_real_estate_debt.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vportfolio_analytics_fact AS
SELECT pa.portfolio_analytics_sk, pa.analytics_date, pa.portfolio_sk, pa.business_unit_sk,
    pa.var_95, pa.var_99, pa.expected_shortfall, pa.period_return_pct, pa.ytd_return_pct,
    pa.benchmark_return_pct, pa.benchmark_code, pa.silver_loaded_at,
    current_timestamp() AS gold_loaded_at
FROM investments.vportfolio_analytics_fact pa
JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = pa.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_real_estate_debt';

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vsecurity_dim AS
WITH team_secs AS (
    SELECT DISTINCT p.security_sk FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_real_estate_debt'
)
SELECT s.security_sk, s.enterprise_key, s.effective_start_date, s.effective_end_date, s.is_current,
    s.security_name, s.asset_class, s.sub_asset_class, s.issue_date, s.maturity_date,
    s.coupon_rate, s.currency_code, s.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_dim s JOIN team_secs ts ON ts.security_sk = s.security_sk;

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vsecurity_master_fact AS
SELECT m.security_master_sk, m.snapshot_date, m.security_sk, m.enterprise_key, m.security_name,
    m.asset_class, m.latest_close_price_usd, m.days_to_maturity, m.is_matured,
    m.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_master_fact m
WHERE m.security_sk IN (SELECT security_sk FROM team_pd_real_estate_debt.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vsecurity_price_fact AS
SELECT sp.security_price_sk, sp.enterprise_key, sp.price_date, sp.security_sk,
    sp.close_price_usd, sp.currency_code, sp.price_type,
    sp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_price_fact sp
WHERE sp.security_sk IN (SELECT security_sk FROM team_pd_real_estate_debt.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vsecurity_rating_dim AS
SELECT sr.security_rating_sk, sr.enterprise_key, sr.effective_start_date, sr.effective_end_date,
    sr.is_current, sr.security_enterprise_key, sr.rating_agency, sr.rating_value,
    sr.rating_outlook, sr.rating_numeric_score,
    sr.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_rating_dim sr
WHERE sr.security_enterprise_key IN (SELECT enterprise_key FROM team_pd_real_estate_debt.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vtransactions_collateral_exposure_fact AS
SELECT ce.collateral_exposure_sk, ce.enterprise_key, ce.exposure_date, ce.contract_sk,
    ce.exposure_amount_usd, ce.collateral_value_usd, ce.collateral_type, ce.ltv_pct,
    ce.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_exposure_fact ce
WHERE ce.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_real_estate_debt.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_real_estate_debt.vtransactions_collateral_positions_fact AS
SELECT cp.collateral_position_sk, cp.enterprise_key, cp.position_date, cp.contract_sk,
    cp.security_sk, cp.position_value_usd, cp.collateral_role,
    cp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_positions_fact cp
WHERE cp.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_real_estate_debt.vcontract_details_fact);

-- team_pd_specialty_finance ---------------------------------------------------
CREATE OR REPLACE VIEW team_pd_specialty_finance.vposition_analytics_fact AS
WITH team_positions AS (
    SELECT p.* FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_specialty_finance'
)
SELECT position_sk, enterprise_key, position_date, portfolio_sk, security_sk, business_unit_sk,
    quantity, market_value_usd, book_value_usd, cost_basis_usd, unrealized_gl_usd,
    market_value_usd / NULLIF(SUM(market_value_usd) OVER (PARTITION BY position_date), 0) AS concentration_pct,
    CAST(DENSE_RANK() OVER (PARTITION BY position_date ORDER BY market_value_usd DESC) AS INT) AS portfolio_rank,
    currency_code, silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM team_positions;

CREATE OR REPLACE VIEW team_pd_specialty_finance.vcontract_details_fact AS
SELECT c.contract_details_sk, c.enterprise_key, c.detail_date, c.contract_sk, c.entity_sk,
    c.contract_type, c.principal_usd, c.coupon_rate, c.spread_over_benchmark,
    c.days_to_maturity, c.status, c.has_active_breach,
    YEAR(cd.signing_date) AS vintage_year,
    c.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_details_fact c
LEFT JOIN investments.vcontract_dim cd ON cd.contract_sk = c.contract_sk AND cd.is_current = TRUE
WHERE c.contract_sk IN (
    SELECT DISTINCT cp.contract_sk FROM investments.vtransactions_collateral_positions_fact cp
    JOIN investments.vposition_analytics_fact p ON p.security_sk = cp.security_sk
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_specialty_finance'
);

CREATE OR REPLACE VIEW team_pd_specialty_finance.vcontract_summary_fact AS
SELECT cs.contract_summary_sk, cs.enterprise_key, cs.summary_date, cs.contract_sk,
    cs.outstanding_principal_usd, cs.accrued_interest_usd, cs.paid_to_date_usd,
    cs.performance_status, cs.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vcontract_summary_fact cs
WHERE cs.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_specialty_finance.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_specialty_finance.vportfolio_analytics_fact AS
SELECT pa.portfolio_analytics_sk, pa.analytics_date, pa.portfolio_sk, pa.business_unit_sk,
    pa.var_95, pa.var_99, pa.expected_shortfall, pa.period_return_pct, pa.ytd_return_pct,
    pa.benchmark_return_pct, pa.benchmark_code, pa.silver_loaded_at,
    current_timestamp() AS gold_loaded_at
FROM investments.vportfolio_analytics_fact pa
JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = pa.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_specialty_finance';

CREATE OR REPLACE VIEW team_pd_specialty_finance.vsecurity_dim AS
WITH team_secs AS (
    SELECT DISTINCT p.security_sk FROM investments.vposition_analytics_fact p
    JOIN investments.vbusiness_unit_dim bu ON bu.business_unit_sk = p.business_unit_sk AND bu.is_current = TRUE AND bu.bu_code = 'team_pd_specialty_finance'
)
SELECT s.security_sk, s.enterprise_key, s.effective_start_date, s.effective_end_date, s.is_current,
    s.security_name, s.asset_class, s.sub_asset_class, s.issue_date, s.maturity_date,
    s.coupon_rate, s.currency_code, s.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_dim s JOIN team_secs ts ON ts.security_sk = s.security_sk;

CREATE OR REPLACE VIEW team_pd_specialty_finance.vsecurity_master_fact AS
SELECT m.security_master_sk, m.snapshot_date, m.security_sk, m.enterprise_key, m.security_name,
    m.asset_class, m.latest_close_price_usd, m.days_to_maturity, m.is_matured,
    m.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_master_fact m
WHERE m.security_sk IN (SELECT security_sk FROM team_pd_specialty_finance.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_specialty_finance.vsecurity_price_fact AS
SELECT sp.security_price_sk, sp.enterprise_key, sp.price_date, sp.security_sk,
    sp.close_price_usd, sp.currency_code, sp.price_type,
    sp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_price_fact sp
WHERE sp.security_sk IN (SELECT security_sk FROM team_pd_specialty_finance.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_specialty_finance.vsecurity_rating_dim AS
SELECT sr.security_rating_sk, sr.enterprise_key, sr.effective_start_date, sr.effective_end_date,
    sr.is_current, sr.security_enterprise_key, sr.rating_agency, sr.rating_value,
    sr.rating_outlook, sr.rating_numeric_score,
    sr.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vsecurity_rating_dim sr
WHERE sr.security_enterprise_key IN (SELECT enterprise_key FROM team_pd_specialty_finance.vsecurity_dim);

CREATE OR REPLACE VIEW team_pd_specialty_finance.vtransactions_collateral_exposure_fact AS
SELECT ce.collateral_exposure_sk, ce.enterprise_key, ce.exposure_date, ce.contract_sk,
    ce.exposure_amount_usd, ce.collateral_value_usd, ce.collateral_type, ce.ltv_pct,
    ce.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_exposure_fact ce
WHERE ce.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_specialty_finance.vcontract_details_fact);

CREATE OR REPLACE VIEW team_pd_specialty_finance.vtransactions_collateral_positions_fact AS
SELECT cp.collateral_position_sk, cp.enterprise_key, cp.position_date, cp.contract_sk,
    cp.security_sk, cp.position_value_usd, cp.collateral_role,
    cp.silver_loaded_at, current_timestamp() AS gold_loaded_at
FROM investments.vtransactions_collateral_positions_fact cp
WHERE cp.contract_sk IN (SELECT DISTINCT contract_sk FROM team_pd_specialty_finance.vcontract_details_fact);

SELECT 'gold.views complete' AS status,
       count(*) AS gold_view_count
FROM information_schema.views
WHERE table_schema IN ('team_pd_direct_lending','team_pd_distressed','team_pd_mezzanine',
                       'team_pd_real_estate_debt','team_pd_specialty_finance')
  AND table_name LIKE 'v%';
