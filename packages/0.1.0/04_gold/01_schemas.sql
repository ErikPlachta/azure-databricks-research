-- ============================================================================
-- 04_gold/01_schemas.sql
-- 5 PD-strategy team schemas + gold_pd_consolidated (cross-team UNION layer).
--
-- Each team schema houses team-specific filtered views over silver
-- `investments.*` plus team-derived columns (concentration, rank, vintage).
-- gold_pd_consolidated UNIONs all 5 teams for cross-team analytics — powers
-- the headline cross-team activity demo (06_demos/02_query_a_*).
--
-- Non-PD teams (5: re_core, re_value_add, pe_buyout, infra, public_equity)
-- exist in vbusiness_unit_dim with seed data but no gold schemas in 0.1.0
-- (PLAN.md flags 0.1.1 milestone).
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE SCHEMA IF NOT EXISTS team_pd_direct_lending
    COMMENT 'Private Debt — Direct Lending. Mid-market direct corporate lending. Filters silver to bu_code = team_pd_direct_lending.';
CREATE SCHEMA IF NOT EXISTS team_pd_distressed
    COMMENT 'Private Debt — Distressed. Distressed debt and special situations.';
CREATE SCHEMA IF NOT EXISTS team_pd_mezzanine
    COMMENT 'Private Debt — Mezzanine. Subordinated/mezzanine financing.';
CREATE SCHEMA IF NOT EXISTS team_pd_real_estate_debt
    COMMENT 'Private Debt — Real Estate Debt. CRE lending and mortgages.';
CREATE SCHEMA IF NOT EXISTS team_pd_specialty_finance
    COMMENT 'Private Debt — Specialty Finance. Royalties, litigation finance, esoteric debt.';
CREATE SCHEMA IF NOT EXISTS gold_pd_consolidated
    COMMENT 'Cross-team consolidated views UNIONing all 5 PD-strategy teams. Powers the cross-team headline demo query.';

SELECT 'gold.schemas complete' AS status;
