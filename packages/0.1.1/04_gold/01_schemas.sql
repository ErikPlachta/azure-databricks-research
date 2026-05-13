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
-- exist in vbusiness_unit_dim with seed data but no gold schemas in 0.1.1
-- (PLAN.md flags 0.1.2 milestone).
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

-- ----------------------------------------------------------------------------
-- 0.1.2: 5 non-PD team schemas. Mirrors the PD-team structure; seeded teams
-- 6–10 in vbusiness_unit_dim. Strengthens cross-team-MV-reuse demo (S2).
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS team_re_core
    COMMENT 'Real Estate — Core. Core real estate equity strategies.';
CREATE SCHEMA IF NOT EXISTS team_re_value_add
    COMMENT 'Real Estate — Value Add. Value-add real estate strategies.';
CREATE SCHEMA IF NOT EXISTS team_pe_buyout
    COMMENT 'Private Equity — Buyout. Mid-market and large-cap buyout.';
CREATE SCHEMA IF NOT EXISTS team_infra
    COMMENT 'Infrastructure. Infrastructure equity and debt.';
CREATE SCHEMA IF NOT EXISTS team_public_equity
    COMMENT 'Public Equity. Listed-equity strategies.';

SELECT 'gold.schemas complete' AS status;
