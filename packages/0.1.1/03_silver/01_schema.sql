-- ============================================================================
-- 03_silver/01_schema.sql
-- Two silver schemas (split per DECISIONS.md #12 — Free Edition 100-cap):
--   * `investments`         — 18 current entities (8 SCD2 dims + 1 fx_rate_dim + 9 base facts incl. vtransaction_fact).
--                              Mirrors user's enterprise `investments` schema.
--   * `investments_history` — 6 historical/correction entities (2 monthend + 3 cancels + 1 bridge).
--                              Mirrors user's enterprise `investments_historical` schema.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE SCHEMA IF NOT EXISTS investments
    COMMENT 'Silver — current. SCD2 dims (security/security_rating/contract/portfolio/entity/security_industry/reporting_group/business_unit) + fx_rate_dim + 9 base facts (incl. vtransaction_fact). References bronze for source.';

CREATE SCHEMA IF NOT EXISTS investments_history
    COMMENT 'Silver — history/corrections. Monthend snapshots (vposition_monthend_fact, vportfolio_analytics_monthend_fact) + cancel siblings (vcontract_details_cancels_fact, vposition_cancels_fact, vsecurity_price_cancels_fact) + vincome_bridge. Cross-references investments.* dims for SCD2 resolution.';

SELECT 'silver.schemas complete' AS status;
