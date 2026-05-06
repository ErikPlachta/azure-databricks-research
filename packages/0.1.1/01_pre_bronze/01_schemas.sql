-- ============================================================================
-- 01_pre_bronze/01_schemas.sql
-- 6 source-system raw landing schemas. One per source.
--
-- Per plan v5: NO clustering, NO row-tracking, NO CDF on raw_*.* tables.
-- This deliberately simulates a "data team that didn't optimize for analytics"
-- — bronze MVs cannot incrementally refresh from raw and always full-recompute.
-- That's part of the demo lesson.
--
-- Idempotent: CREATE SCHEMA IF NOT EXISTS.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

CREATE SCHEMA IF NOT EXISTS raw_state_street
    COMMENT 'Custodian. Position holdings, transaction settlements, cash flows, NAVs, security pricing.';
CREATE SCHEMA IF NOT EXISTS raw_aladdin
    COMMENT 'BlackRock Aladdin. Portfolio risk/performance, compliance attribution, cash management, trading data.';
CREATE SCHEMA IF NOT EXISTS raw_aspen
    COMMENT 'Internal research mgmt. Entity-to-asset masters, security reference, ratings. Default source-of-truth for master attributes (with holes).';
CREATE SCHEMA IF NOT EXISTS raw_efront
    COMMENT 'BlackRock eFront. Private capital fund admin, contract terms, covenants, capital activity, GP/LP records. Heavy contributor to private-debt domain. Table shapes inferred — see DECISIONS.md #4.';
CREATE SCHEMA IF NOT EXISTS raw_internal_admin
    COMMENT 'Internal org/HR system. Business-unit master, business-unit membership, employee records. Lineage source for vbusiness_unit_dim.';
CREATE SCHEMA IF NOT EXISTS raw_bloomberg
    COMMENT 'Market data. FX rates only in 0.1.0 (security pricing deferred — see DECISIONS.md #10).';

SELECT 'pre_bronze.schemas complete' AS status;
