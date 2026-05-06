-- ============================================================================
-- 00_setup/02_teardown.sql
-- Idempotent destructive reset. Drops every 0.1.0 schema and its contents
-- inside the active catalog (medallion_demo by default).
--
-- Catalog itself is NOT dropped — could be shared with other workloads.
--
-- Gated. To execute:
--   SET VARIABLE RUN_TEARDOWN = TRUE;
--   then run this file.
-- ============================================================================

DECLARE OR REPLACE VARIABLE RUN_TEARDOWN BOOLEAN DEFAULT FALSE;

-- Self-declare catalog_name so this file is runnable in a fresh session
-- (without having run 01_config.sql first). If 01_config.sql ran in this
-- session and customized catalog_name, that customization is reset here —
-- override AFTER this DECLARE if needed:
--   SET VARIABLE catalog_name = 'my_other_catalog';
DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

BEGIN
    IF NOT RUN_TEARDOWN THEN
        SELECT 'teardown SKIPPED — set RUN_TEARDOWN=TRUE to execute' AS status;
    ELSE
        -- ------------------------------------------------------------------
        -- Drop in dependency order (gold → silver → bronze → pre-bronze).
        -- DROP SCHEMA ... CASCADE removes all tables / views / MVs / procs
        -- / functions inside.
        -- ------------------------------------------------------------------

        -- Gold: 5 PD team schemas + cross-team consolidated
        DROP SCHEMA IF EXISTS team_pd_direct_lending     CASCADE;
        DROP SCHEMA IF EXISTS team_pd_distressed         CASCADE;
        DROP SCHEMA IF EXISTS team_pd_mezzanine          CASCADE;
        DROP SCHEMA IF EXISTS team_pd_real_estate_debt   CASCADE;
        DROP SCHEMA IF EXISTS team_pd_specialty_finance  CASCADE;
        DROP SCHEMA IF EXISTS gold_pd_consolidated       CASCADE;

        -- Silver (split into 2 schemas in 0.1.1)
        DROP SCHEMA IF EXISTS investments         CASCADE;
        DROP SCHEMA IF EXISTS investments_history CASCADE;

        -- Bronze
        DROP SCHEMA IF EXISTS bronze CASCADE;

        -- Pre-bronze (6 source schemas)
        DROP SCHEMA IF EXISTS raw_state_street   CASCADE;
        DROP SCHEMA IF EXISTS raw_aladdin        CASCADE;
        DROP SCHEMA IF EXISTS raw_aspen          CASCADE;
        DROP SCHEMA IF EXISTS raw_efront         CASCADE;
        DROP SCHEMA IF EXISTS raw_internal_admin CASCADE;
        DROP SCHEMA IF EXISTS raw_bloomberg      CASCADE;

        SELECT 'teardown complete' AS status;
    END IF;
END;
