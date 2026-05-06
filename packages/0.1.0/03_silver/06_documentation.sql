-- ============================================================================
-- 03_silver/06_documentation.sql
-- Heavy COMMENT ON for silver tables + key columns.
--
-- Per plan §"Documentation strategy": every silver table gets a COMMENT;
-- every business-meaningful column gets a COMMENT covering semantic meaning,
-- units, NULL semantics, source-system origin, business-logic transforms.
--
-- Audit columns (bronze_loaded_at, silver_loaded_at) and SCD2-chain columns
-- (effective_*, is_current, *_record_sk) are documented once per representative
-- table — they have identical semantics across all SCD2 dims.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- SCD2 DIMS (table comments handled inline in 02_tables.sql; key column docs)
-- ============================================================================

-- vsecurity_dim — full SCD2 column documentation (representative; same
-- semantics applied to other SCD2 dims).
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN security_sk          COMMENT 'Surrogate key. Stable per chain row. Generated via ROW_NUMBER OVER (ORDER BY enterprise_key, issue_date) so refreshes are deterministic.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN enterprise_key       COMMENT 'Internal stable identity, persists across SCD2 chain. Source: aspen.security_master_raw.enterprise_key.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN effective_start_date COMMENT 'Inclusive start of this version. = issue_date for chain head; = previous row''s effective_end_date + 1 day for successors.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN effective_end_date   COMMENT 'Inclusive end. = next chain row''s effective_start_date - 1 day; = ''9999-12-31'' for current row.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN is_current           COMMENT 'TRUE for the latest row per enterprise_key. Exactly one TRUE per enterprise_key (validated by 04_scd2_integrity).';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN preceding_record_sk  COMMENT 'security_sk of the prior chain row (NULL for chain head).';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN succeeding_record_sk COMMENT 'security_sk of the next chain row (NULL for current row).';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN security_name        COMMENT 'Aspen master attribute. Original = ''Security_NNNN''; reissued = ''Security_NNNN (Reissued)''.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN asset_class          COMMENT 'PUBLIC_EQUITY / PRIVATE_EQUITY / SENIOR_DEBT / MEZZ / DISTRESSED / RE_DEBT / SPECIALTY. Aspen master.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN currency_code        COMMENT 'ISO-4217. Currency in which security trades. Aspen master.';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN issuer_enterprise_key COMMENT 'FK to ventity_dim. Resolved via bronze.fn_resolve_enterprise_key(''aspen'', issuer_source_key).';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN bronze_loaded_at     COMMENT 'When this row landed in pre-bronze (raw_aspen.security_master_raw.loaded_at).';
ALTER TABLE investments.t_vsecurity_dim ALTER COLUMN silver_loaded_at     COMMENT 'When this silver row was computed (refresh proc invocation time).';

-- vsecurity_rating_dim — domain-specific columns
ALTER TABLE investments.t_vsecurity_rating_dim ALTER COLUMN rating_value         COMMENT 'AAA / AA / A / BBB / BB / B / CCC / D. Source: aspen.security_rating_raw.';
ALTER TABLE investments.t_vsecurity_rating_dim ALTER COLUMN rating_action_type  COMMENT 'INITIAL / UPGRADE / DOWNGRADE / AFFIRM / WITHDRAW. Each new action triggers a new SCD2 row.';
ALTER TABLE investments.t_vsecurity_rating_dim ALTER COLUMN rating_numeric_score COMMENT 'Derived: AAA=1, AA=2, ..., D=10. Use for sort/threshold logic. NULL if unmapped.';

-- vcontract_dim — domain-specific columns
ALTER TABLE investments.t_vcontract_dim ALTER COLUMN contract_type         COMMENT 'TERM_LOAN / REVOLVER / MEZZ / UNITRANCHE / EQUITY_COMMITMENT.';
ALTER TABLE investments.t_vcontract_dim ALTER COLUMN principal_local       COMMENT 'Original face amount in currency_code. Use principal_usd-equivalent in fact joins for cross-currency comparisons.';
ALTER TABLE investments.t_vcontract_dim ALTER COLUMN status                COMMENT 'ACTIVE / FULL_REPAID / DEFAULT / RESTRUCTURED / WRITTEN_OFF. Amendments emit new SCD2 rows with this column potentially changed.';
ALTER TABLE investments.t_vcontract_dim ALTER COLUMN coupon_type           COMMENT 'FIXED / FLOATING / PIK. PIK = paid-in-kind (interest accrues to principal).';

-- vportfolio_dim
ALTER TABLE investments.t_vportfolio_dim ALTER COLUMN portfolio_name              COMMENT 'Display name. Sourced from latest aladdin.portfolio_risk_raw row.';
ALTER TABLE investments.t_vportfolio_dim ALTER COLUMN business_unit_enterprise_key COMMENT 'FK to vbusiness_unit_dim via portfolio<->BU heuristic mapping (team_idx encoded in portfolio_source_key suffix). Real env would have a portfolio_to_bu master table.';

-- ventity_dim
ALTER TABLE investments.t_ventity_dim ALTER COLUMN entity_type        COMMENT 'CORPORATE / FUND / SPV / TRUST. Aspen master.';
ALTER TABLE investments.t_ventity_dim ALTER COLUMN dissolution_date   COMMENT 'NULL for active entities. Set when entity is soft-deleted (Phase 6.2 of seed). is_current may still be TRUE for dissolved entities — they''re terminal but still the latest version.';
ALTER TABLE investments.t_ventity_dim ALTER COLUMN has_contracts      COMMENT 'TRUE if this entity is referenced by at least one efront contract. Derived from contracts_per_entity LEFT JOIN.';

-- vbusiness_unit_dim
ALTER TABLE investments.t_vbusiness_unit_dim ALTER COLUMN bu_code             COMMENT 'team_pd_direct_lending / team_pd_distressed / team_pd_mezzanine / team_pd_real_estate_debt / team_pd_specialty_finance / team_re_core / team_re_value_add / team_pe_buyout / team_infra / team_public_equity.';
ALTER TABLE investments.t_vbusiness_unit_dim ALTER COLUMN is_pd_strategy      COMMENT 'TRUE for the 5 team_pd_* strategies. Identifies the gold-team subset (used by gold_pd_consolidated UNIONs and S2 cross-team-MV-reuse demo).';
ALTER TABLE investments.t_vbusiness_unit_dim ALTER COLUMN associated_risk_team_codes COMMENT 'Aladdin compliance overlay. Risk-team codes that have run compliance checks against any portfolio in this BU. Diagnostic; not authoritative.';

-- vfx_rate_dim
ALTER TABLE investments.t_vfx_rate_dim ALTER COLUMN fx_rate           COMMENT 'Multiplier: amount_in_from_currency * fx_rate = amount_in_to_currency. Sourced from raw_bloomberg.fx_rate_raw.';
ALTER TABLE investments.t_vfx_rate_dim ALTER COLUMN rate_type         COMMENT 'CLOSE / MID / BID / ASK. 0.1.0 seed populates only CLOSE.';

-- ============================================================================
-- BASE FACTS — currency normalization + dim_sk semantics
-- ============================================================================

-- vposition_analytics_fact
ALTER TABLE investments.t_vposition_analytics_fact ALTER COLUMN portfolio_sk         COMMENT 'Temporal-resolved FK: position_date BETWEEN portfolio_dim.effective_start_date AND effective_end_date. May be NULL if portfolio dim has no row covering the position_date.';
ALTER TABLE investments.t_vposition_analytics_fact ALTER COLUMN security_sk          COMMENT 'Temporal-resolved FK: position_date BETWEEN security_dim.effective_start_date AND effective_end_date. SCD2-aware — reissued securities split position records across pre/post-reissue SKs.';
ALTER TABLE investments.t_vposition_analytics_fact ALTER COLUMN business_unit_sk     COMMENT 'Resolved via portfolio_dim.business_unit_enterprise_key -> vbusiness_unit_dim (is_current = TRUE). NOT temporally resolved (BU history rarely useful at fact granularity).';
ALTER TABLE investments.t_vposition_analytics_fact ALTER COLUMN market_value_local   COMMENT 'In currency_code. Source: state_street.position_raw.market_value_local.';
ALTER TABLE investments.t_vposition_analytics_fact ALTER COLUMN market_value_usd     COMMENT 'Computed: market_value_local * fx_rate(currency_code, USD, position_date). Uses COALESCE(fx_rate, 1.0) to default-pass USD or missing-rate rows through.';
ALTER TABLE investments.t_vposition_analytics_fact ALTER COLUMN fx_rate_to_usd       COMMENT 'The FX rate applied to compute *_usd companion columns. NULL if no FX rate available for (currency_code, position_date).';

-- vposition_monthend_fact
ALTER TABLE investments.t_vposition_monthend_fact ALTER COLUMN monthend_date    COMMENT 'last_day(position_date). Pre-aggregated period-end snapshot from vposition_analytics_fact.';

-- vsecurity_master_fact
ALTER TABLE investments.t_vsecurity_master_fact ALTER COLUMN snapshot_date     COMMENT 'current_date() at refresh time. Period-end snapshot of master attrs + latest pricing.';
ALTER TABLE investments.t_vsecurity_master_fact ALTER COLUMN days_to_maturity  COMMENT 'datediff(maturity_date, snapshot_date). NEGATIVE if matured.';
ALTER TABLE investments.t_vsecurity_master_fact ALTER COLUMN is_matured        COMMENT 'TRUE if maturity_date < snapshot_date.';

-- vsecurity_price_fact
ALTER TABLE investments.t_vsecurity_price_fact ALTER COLUMN close_price_usd   COMMENT 'close_price_local * fx_rate(currency_code, USD, price_date). Defaults to close_price_local for USD-denominated rows.';

-- vcontract_details_fact
ALTER TABLE investments.t_vcontract_details_fact ALTER COLUMN has_active_breach COMMENT 'TRUE if any covenant_status = TRIPPED on detail_date. Derived from raw_efront.contract_covenant_raw.';
ALTER TABLE investments.t_vcontract_details_fact ALTER COLUMN days_to_maturity  COMMENT 'datediff(maturity_date, detail_date). Use for run-off scheduling.';

-- vcontract_summary_fact
ALTER TABLE investments.t_vcontract_summary_fact ALTER COLUMN performance_status COMMENT 'CURRENT / WATCH / NON_ACCRUAL / IMPAIRED. Source: raw_efront.contract_summary_raw.performance_status.';
ALTER TABLE investments.t_vcontract_summary_fact ALTER COLUMN outstanding_principal_local COMMENT 'Period-end principal balance. Decreases via paid_to_date.';

-- vportfolio_analytics_fact
ALTER TABLE investments.t_vportfolio_analytics_fact ALTER COLUMN var_95             COMMENT '95% Value-at-Risk (1-day, parametric). Source: aladdin. Decimal pct (0.05 = 5%).';
ALTER TABLE investments.t_vportfolio_analytics_fact ALTER COLUMN expected_shortfall COMMENT 'CVaR / Expected Shortfall at 95%. Loss conditional on VaR breach.';
ALTER TABLE investments.t_vportfolio_analytics_fact ALTER COLUMN ytd_return_pct    COMMENT 'Year-to-date return as decimal pct (0.0125 = 1.25%). Source: aladdin.portfolio_performance_raw.';

-- vtransactions_collateral_exposure_fact
ALTER TABLE investments.t_vtransactions_collateral_exposure_fact ALTER COLUMN ltv_pct COMMENT 'Loan-to-value ratio: exposure_amount / collateral_value. Decimal pct (0.75 = 75%).';

-- vtransactions_collateral_positions_fact
ALTER TABLE investments.t_vtransactions_collateral_positions_fact ALTER COLUMN collateral_role COMMENT 'PRIMARY / SUPPORTING / CROSS_COLLATERAL. Source: raw_efront.collateral_position_raw.';
ALTER TABLE investments.t_vtransactions_collateral_positions_fact ALTER COLUMN asset_enterprise_key COMMENT 'FK to vasset (real-asset master). NULL if collateral is a security rather than a real asset.';

-- ============================================================================
-- CANCELS
-- ============================================================================

ALTER TABLE investments.t_vcontract_details_cancels_fact ALTER COLUMN cancel_reason COMMENT 'AMENDMENT (in 0.1.0 — derived from _v2 contract source_keys per Phase 6.4 of seed). Future: RESTATEMENT / VOID / DUPLICATE.';
ALTER TABLE investments.t_vposition_cancels_fact ALTER COLUMN cancel_reason         COMMENT 'CROSSWALK_REMAP (in 0.1.0 — derived from REMAPPED_ enterprise_keys per Phase 6.5 of seed). Future: CUSTODIAN_RESTATEMENT.';
ALTER TABLE investments.t_vsecurity_price_cancels_fact ALTER COLUMN cancel_reason   COMMENT 'Reserved (0.1.0 emits 0 rows). Phase 6 doesn''t model price cancels yet.';

-- ============================================================================
-- BRIDGE
-- ============================================================================

ALTER TABLE investments.t_vincome_bridge ALTER COLUMN income_type COMMENT 'COUPON / DIVIDEND / FEE_INCOME / OTHER. 0.1.0 simplification: filters cash_flow_raw.cash_flow_type = INCOME, all bucketed as COUPON. Future: distinguish dividend vs coupon vs fee income.';
ALTER TABLE investments.t_vincome_bridge ALTER COLUMN security_sk COMMENT 'NULL in 0.1.0: cash_flow_raw lacks security_source_key. Future: link via (portfolio + date + amount) heuristic.';

SELECT 'silver.documentation complete' AS status;
