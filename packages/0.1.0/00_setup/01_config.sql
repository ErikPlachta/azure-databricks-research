-- ============================================================================
-- 00_setup/01_config.sql
-- Session-scoped configuration. Re-run at the top of every SQL editor session.
--
-- Sets every shared variable downstream files reference. Defaults are sized
-- for Databricks Free Edition compute. Paid-workspace overrides are noted
-- inline; flip via SET VARIABLE after running this file.
--
-- This file ends with USE CATALOG so subsequent files inherit the active
-- catalog. Subsequent files use schema-qualified two-part names (e.g.
-- `bronze.crosswalk`, not `medallion_demo.bronze.crosswalk`).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Catalog target
-- ----------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';

-- ----------------------------------------------------------------------------
-- Position window (5y default; 20y on paid)
-- ----------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE position_start_date DATE    DEFAULT date_sub(current_date(), 365 * 5);
DECLARE OR REPLACE VARIABLE position_end_date   DATE    DEFAULT current_date();
DECLARE OR REPLACE VARIABLE simulate_history    BOOLEAN DEFAULT TRUE;
DECLARE OR REPLACE VARIABLE skip_positions      BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_transactions   BOOLEAN DEFAULT FALSE;

-- ----------------------------------------------------------------------------
-- Source toggles
-- Skipping a source means seed populates 0 rows for that raw_<source>.*; bronze
-- precedence falls back automatically (provenance columns reflect missing source).
-- ----------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE skip_state_street   BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_aladdin        BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_aspen          BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_efront         BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_internal_admin BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_bloomberg      BOOLEAN DEFAULT FALSE;

-- ----------------------------------------------------------------------------
-- Team toggles (skip seeding a team's allocations + facts)
-- ----------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE skip_team_pd_direct_lending    BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_pd_distressed        BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_pd_mezzanine         BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_pd_real_estate_debt  BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_pd_specialty_finance BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_re_core              BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_re_value_add         BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_pe_buyout            BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_infra                BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_team_public_equity        BOOLEAN DEFAULT FALSE;

-- ----------------------------------------------------------------------------
-- Seed sizes (Free Edition defaults; paid overrides commented inline)
-- ----------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE seed_n_securities                INT DEFAULT 200;   -- 700 on paid
DECLARE OR REPLACE VARIABLE seed_n_entities                  INT DEFAULT 100;   -- 200 on paid
DECLARE OR REPLACE VARIABLE seed_n_assets                    INT DEFAULT 60;    -- 300 on paid
DECLARE OR REPLACE VARIABLE seed_n_contracts                 INT DEFAULT 100;   -- 500 on paid
DECLARE OR REPLACE VARIABLE seed_positions_per_team_per_year INT DEFAULT 2000;  -- 10000 on paid
DECLARE OR REPLACE VARIABLE seed_txns_per_security_per_year  INT DEFAULT 8;     -- 20 on paid

-- ----------------------------------------------------------------------------
-- SCD2 history simulation counts (Phase 6 of seed; gated by simulate_history)
-- ----------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE history_entity_restructurings   INT DEFAULT 25;
DECLARE OR REPLACE VARIABLE history_entity_soft_deletes     INT DEFAULT 5;
DECLARE OR REPLACE VARIABLE history_security_renames        INT DEFAULT 10;
DECLARE OR REPLACE VARIABLE history_contract_amendments     INT DEFAULT 15;
DECLARE OR REPLACE VARIABLE history_business_unit_renames   INT DEFAULT 3;
DECLARE OR REPLACE VARIABLE history_crosswalk_supersessions INT DEFAULT 20;

-- ----------------------------------------------------------------------------
-- Activate catalog. All downstream DDL/DML uses two-part names that resolve
-- through this active catalog.
-- ----------------------------------------------------------------------------
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

SELECT 'config_load complete' AS status, current_catalog() AS active_catalog;
