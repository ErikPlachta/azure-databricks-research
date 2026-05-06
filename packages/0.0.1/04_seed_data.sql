-- ============================================================================
-- BRIDGE FRAMEWORK — Idempotent Setup & Seed Data
--
-- Run after 03_procedures.sql.
--
-- =============================================================================
-- WHAT THIS FILE DOES
-- =============================================================================
-- This file does three things, in order:
--
--   1. Declares Databricks SQL session variables that act as parameters for
--      the seed (position window, history simulation toggles, etc.). The
--      user can override these with SET VARIABLE before re-running, or edit
--      the DEFAULTs in place.
--
--   2. Defines the bridge.usp_reset_setup_seed_data procedure that does the
--      actual work: purges all related tables, inserts metadata, generates
--      dimensions, allocations, crosswalks, simulates SCD2 history, and
--      generates fact.position rows.
--
--   3. Calls the procedure once with the current session variable values.
--
-- The procedure runs in seven phases:
--
--   Phase 1: Purge ALL tables in reverse-dependency order. We always start
--            fresh so the seed is fully reproducible.
--   Phase 2: Insert metadata (source_registry, key_domain, departments, etc.).
--            This is "config" data — small, stable, hand-curated.
--   Phase 3: Generate dimensional data (investors, portfolios, etc.) at their
--            current state. effective_start_date is set to v_position_start
--            so every dim record exists from the beginning of the position
--            window — even for a 20-year history.
--   Phase 4: Generate ownership allocations (who owns what %).
--   Phase 5: Generate crosswalk mappings (1:1, many:1, 1:many) between
--            external systems and the enterprise golden keys. effective_start
--            is also v_position_start.
--   Phase 6: (Optional) Simulate SCD2 history — close out some dimension
--            records and replace them with new versions, soft-delete a few,
--            and supersede some crosswalk mappings. Events are DISTRIBUTED
--            across the position window with deterministic jitter, so over a
--            20-year history you get changes happening throughout.
--   Phase 7: Generate fact.position rows across the position window. For
--            each (date, security), the dim chain (security → asset →
--            entity → portfolio) is resolved temporally — anchor SK gives
--            the enterprise_xxx_id; the version current at that date is
--            joined by enterprise_id + effective range. This is the
--            canonical Kimball SCD2 resolution pattern.
--
-- =============================================================================
-- SESSION VARIABLES (act as the SQL Parameters for this seed)
-- =============================================================================
-- position_start_date  DATE    — first position_date to generate.
--                                Default: 20 years before today.
-- position_end_date    DATE    — last position_date to generate.
--                                Default: today.
-- simulate_history     BOOLEAN — if TRUE, Phase 6 produces SCD2 chains and
--                                soft-deletes spread across the position
--                                window. Default TRUE.
-- skip_positions       BOOLEAN — if TRUE, skip Phase 7 entirely. Useful for
--                                fast iteration on dimensional data without
--                                regenerating millions of position rows.
--                                Default FALSE.
--
-- To override, run before this file (or in the same session):
--   SET VARIABLE position_start_date = DATE'2010-01-01';
--   SET VARIABLE position_end_date   = DATE'2024-12-31';
--   SET VARIABLE simulate_history    = TRUE;
-- Then re-run the file. The CALL at the bottom will pick up the new values.
--
-- =============================================================================
-- HOW TO MODIFY
-- =============================================================================
-- "I want positions for the past 20 years (default):"
--    -> Just run the file. Default is current_date() - (365 * 20).
--
-- "I want positions for 2010-01-01 through 2024-12-31:"
--    -> SET VARIABLE position_start_date = DATE'2010-01-01';
--       SET VARIABLE position_end_date   = DATE'2024-12-31';
--       Then re-run.
--
-- "I want a different number of investors / portfolios / entities / assets:"
--    -> Each generator in Phase 3 has a row-count cap (e.g. WHERE n <= 50).
--       Change the constant. Downstream cascades proportionally.
--
-- "I want more or fewer SCD2 history events:"
--    -> Phase 6 has constants for each scenario (10 investor renames, 25
--       entity restructurings, 5 soft-deletes, 20 crosswalk supersessions).
--       Edit the LIMIT clauses at the top of each sub-phase.
--
-- "I want to add another SCD2 history scenario (e.g., asset reclassifications):"
--    -> Phase 6 has one block per scenario. Copy a block, change the table
--       name and modification logic. Pattern is:
--         a) Compute event dates spread across the window with hash jitter
--         b) INSERT new versions with preceding_record_sk pointing back
--         c) MERGE old versions to set is_current=FALSE, effective_end_date
--            (= one day before new effective_start), succeeding_record_sk
--
-- =============================================================================
-- DATABRICKS-SPECIFIC NOTES
-- =============================================================================
-- * range() requires a foldable BIGINT, so it can't accept procedure parameters
--   directly. We use sequence() with explode() for the date generator.
-- * Procedure variables (DECLARE) and session variables (DECLARE OR REPLACE
--   VARIABLE) are different. Session variables persist for the connection;
--   procedure variables are scoped to the BEGIN/END block.
-- * SET = (SELECT ...) for variable assignment from queries (no SELECT INTO).
-- * SIGNAL SQLSTATE for raising errors (no THROW).
-- * No early RETURN inside compound statements; structure with IF/ELSE.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- SESSION VARIABLES (Databricks SQL Parameters)
-- ============================================================================
-- DECLARE OR REPLACE VARIABLE makes these idempotent — re-running the file
-- resets them to defaults unless the user SETs them between runs.
DECLARE OR REPLACE VARIABLE position_start_date DATE    DEFAULT date_sub(current_date(), 365 * 20);
DECLARE OR REPLACE VARIABLE position_end_date   DATE    DEFAULT current_date();
DECLARE OR REPLACE VARIABLE simulate_history    BOOLEAN DEFAULT TRUE;
DECLARE OR REPLACE VARIABLE skip_positions      BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- PROCEDURE DEFINITION
-- ============================================================================
CREATE OR REPLACE PROCEDURE bridge.usp_reset_setup_seed_data(
    IN p_position_start_date DATE    DEFAULT NULL,
    IN p_position_end_date   DATE    DEFAULT NULL,
    IN p_simulate_history    BOOLEAN DEFAULT TRUE,
    IN p_skip_positions      BOOLEAN DEFAULT FALSE
)
COMMENT 'Idempotent full-reset seed for the bridge framework. See file header for parameter docs.'
LANGUAGE SQL
SQL SECURITY INVOKER
BEGIN

    -- ====================================================================
    -- Resolve effective date parameters once, up front. These procedure-
    -- local variables are referenced throughout the body.
    -- ====================================================================
    DECLARE v_position_start DATE;
    DECLARE v_position_end   DATE;
    DECLARE v_window_days    INT;

    SET v_position_start = COALESCE(p_position_start_date, date_sub(current_date(), 365 * 20));
    SET v_position_end   = COALESCE(p_position_end_date,   current_date());
    SET v_window_days    = datediff(v_position_end, v_position_start);

    IF v_position_start > v_position_end THEN
        SIGNAL SQLSTATE '45100' SET MESSAGE_TEXT = 'p_position_start_date must be <= p_position_end_date';
    END IF;

    -- ====================================================================
    -- PHASE 1: PURGE ALL TABLES
    -- Reverse-dependency order. Delta DELETE just tombstones existing files;
    -- it's fast even for tables with millions of rows.
    -- ====================================================================

    DELETE FROM bridge.execution_detail_log;
    DELETE FROM bridge.execution_log;
    DELETE FROM fact.position;
    DELETE FROM bridge.portfolio_entity_alloc;
    DELETE FROM bridge.portfolio_group_portfolio_alloc;
    DELETE FROM bridge.investor_portfolio_group_alloc;
    DELETE FROM bridge.key_crosswalk;
    DELETE FROM dim.security;
    DELETE FROM dim.asset;
    DELETE FROM dim.entity;
    DELETE FROM dim.portfolio;
    DELETE FROM dim.portfolio_group;
    DELETE FROM dim.investor;
    DELETE FROM dim.department_group;
    DELETE FROM dim.department;
    DELETE FROM bridge.bridge_category;
    DELETE FROM bridge.tag;
    DELETE FROM bridge.key_domain;
    DELETE FROM bridge.source_registry;

    -- ====================================================================
    -- PHASE 2: INSERT METADATA
    -- Tables are empty after Phase 1, so plain INSERT (no MERGE needed).
    -- ====================================================================

    -- 2.1 SOURCE REGISTRY -----------------------------------------------------
    INSERT INTO bridge.source_registry
        (source_code, source_name, source_type, description, connection_type, refresh_frequency)
    VALUES
        ('ENTERPRISE',     'Enterprise System',  'INTERNAL', 'Internal golden source of truth', 'DATABASE', 'REALTIME'),
        ('STATE_STREET',   'State Street',       'EXTERNAL', 'Custodian bank',                  'SFTP',     'DAILY'),
        ('BNY_MELLON',     'BNY Mellon',         'EXTERNAL', 'Custodian bank',                  'API',      'DAILY'),
        ('NORTHERN_TRUST', 'Northern Trust',     'EXTERNAL', 'Custodian bank',                  'SFTP',     'DAILY'),
        ('BLOOMBERG',      'Bloomberg',          'EXTERNAL', 'Market data and analytics',       'API',      'REALTIME'),
        ('MSCI',           'MSCI',               'EXTERNAL', 'Real estate indexes',             'API',      'DAILY'),
        ('COSTAR',         'CoStar Group',       'EXTERNAL', 'Commercial real estate data',     'API',      'DAILY'),
        ('YARDI',          'Yardi Voyager',      'EXTERNAL', 'Property management system',      'DATABASE', 'DAILY'),
        ('MRI',            'MRI Software',       'EXTERNAL', 'Property management system',      'API',      'DAILY'),
        ('INVESTRAN',      'Investran',          'EXTERNAL', 'Fund administration',             'API',      'WEEKLY'),
        ('ALTUS',          'Altus Group',        'EXTERNAL', 'Property valuation',              'MANUAL',   'QUARTERLY');

    -- 2.2 KEY DOMAIN ----------------------------------------------------------
    INSERT INTO bridge.key_domain
        (domain_code, domain_name, description, dimension_schema, dimension_table, dimension_key_column)
    VALUES
        ('INVESTOR',        'Investor',         'Investors / capital sources',          'dim', 'investor',        'enterprise_investor_id'),
        ('PORTFOLIO_GROUP', 'Portfolio Group',  'Groupings of portfolios',              'dim', 'portfolio_group', 'enterprise_portfolio_group_id'),
        ('PORTFOLIO',       'Portfolio',        'Investment portfolios',                'dim', 'portfolio',       'enterprise_portfolio_id'),
        ('ENTITY',          'Entity',           'Legal entities (SPVs, holdcos)',       'dim', 'entity',          'enterprise_entity_id'),
        ('ASSET',           'Asset',            'Underlying real estate / loan assets', 'dim', 'asset',           'enterprise_asset_id'),
        ('SECURITY',        'Security',         'Financial instruments',                'dim', 'security',        'enterprise_security_id');

    -- 2.3 DEPARTMENTS ---------------------------------------------------------
    INSERT INTO dim.department
        (enterprise_department_id, department_code, department_name, description)
    VALUES
        ('DEPT_RE_EQUITY', 'RE_EQ',  'Real Estate Equity', 'Equity investments in real assets'),
        ('DEPT_RE_DEBT',   'RE_DBT', 'Real Estate Debt',   'Debt instruments collateralized by real assets'),
        ('DEPT_INFRA',     'INFRA',  'Infrastructure',     'Infrastructure investments'),
        ('DEPT_PE',        'PE',     'Private Equity',     'Private equity investments');

    -- 2.4 DEPARTMENT GROUPS (TEAMS) -------------------------------------------
    INSERT INTO dim.department_group
        (enterprise_group_id, department_id, group_code, group_name, description)
    SELECT
        v.enterprise_group_id, d.department_id,
        v.group_code, v.group_name, v.description
    FROM (
        SELECT * FROM VALUES
            ('GRP_OFFICE',      'DEPT_RE_EQUITY', 'OFFICE',     'Office Team',          'Office property investments'),
            ('GRP_RETAIL',      'DEPT_RE_EQUITY', 'RETAIL',     'Retail Team',          'Retail property investments'),
            ('GRP_INDUSTRIAL',  'DEPT_RE_EQUITY', 'INDUSTRIAL', 'Industrial Team',      'Industrial property investments'),
            ('GRP_MULTIFAMILY', 'DEPT_RE_EQUITY', 'MULTIFAMILY','Multifamily Team',     'Multifamily property investments'),
            ('GRP_HOTEL',       'DEPT_RE_EQUITY', 'HOTEL',      'Hotel Team',           'Hotel/hospitality investments'),
            ('GRP_SENIOR_DEBT', 'DEPT_RE_DEBT',   'SR_DEBT',    'Senior Debt Team',     'Senior secured lending'),
            ('GRP_MEZZ',        'DEPT_RE_DEBT',   'MEZZ',       'Mezzanine Team',       'Mezzanine debt investments'),
            ('GRP_INFRA_EQ',    'DEPT_INFRA',     'INFRA_EQ',   'Infrastructure Equity','Infrastructure equity investments'),
            ('GRP_PE_BUYOUT',   'DEPT_PE',        'BUYOUT',     'Buyout Team',          'PE buyout investments')
        AS t(enterprise_group_id, parent_dept_code, group_code, group_name, description)
    ) v
    JOIN dim.department d ON d.enterprise_department_id = v.parent_dept_code;

    -- 2.5 BRIDGE CATEGORY -----------------------------------------------------
    INSERT INTO bridge.bridge_category
        (category_code, category_name, description, source_table, target_table, delta_strategy, delta_column)
    VALUES
        ('XWALK_ENTITY',   'Entity Crosswalk',   'Crosswalk for entity keys',   'staging.entity_xwalk',   'bridge.key_crosswalk', 'HASH',      NULL),
        ('XWALK_SECURITY', 'Security Crosswalk', 'Crosswalk for security keys', 'staging.security_xwalk', 'bridge.key_crosswalk', 'HASH',      NULL),
        ('XWALK_ASSET',    'Asset Crosswalk',    'Crosswalk for asset keys',    'staging.asset_xwalk',    'bridge.key_crosswalk', 'HASH',      NULL),
        ('FACT_POSITION',  'Position Fact Load', 'Daily position snapshots',    'staging.position',       'fact.position',        'WATERMARK', 'position_date');

    -- 2.6 TAGS ---------------------------------------------------------------
    INSERT INTO bridge.tag
        (tag_code, tag_name, tag_group, description)
    VALUES
        ('NIGHTLY',    'Nightly Run',      'SCHEDULE',   'Run during nightly batch'),
        ('INTRADAY',   'Intraday Run',     'SCHEDULE',   'Run during business hours'),
        ('CRITICAL',   'Critical',         'PRIORITY',   'High priority - must succeed'),
        ('REGULATORY', 'Regulatory',       'COMPLIANCE', 'Required for regulatory reporting'),
        ('POC',        'Proof of Concept', 'LIFECYCLE',  'Development / POC only');

    -- ====================================================================
    -- PHASE 3: GENERATE DIMENSIONS (current state, anchored at v_position_start)
    -- All initial records get effective_start_date = v_position_start. This
    -- means every dim record "exists" from the beginning of the position
    -- window. Phase 6 may later close some of these and insert new versions
    -- at points within the window.
    -- ====================================================================

    -- 3.1 INVESTORS (50) ------------------------------------------------------
    INSERT INTO dim.investor (
        enterprise_investor_id, investor_name, investor_type, investor_category, country_code,
        effective_start_date
    )
    WITH base AS (
        SELECT * FROM VALUES
            ('INSTITUTIONAL', 'PENSION'),
            ('INSTITUTIONAL', 'PENSION'),
            ('INSTITUTIONAL', 'ENDOWMENT'),
            ('INSTITUTIONAL', 'INSURANCE'),
            ('INSTITUTIONAL', 'INSURANCE'),
            ('SOVEREIGN',     'SOVEREIGN_WEALTH'),
            ('FUND',          'FUND_OF_FUNDS'),
            ('FUND',          'FUND_OF_FUNDS'),
            ('INDIVIDUAL',    'FAMILY_OFFICE'),
            ('INDIVIDUAL',    'FAMILY_OFFICE')
        AS t(investor_type, investor_category)
    ),
    multiplied AS (
        SELECT
            row_number() OVER (ORDER BY mult.x, b.investor_type, b.investor_category) AS n,
            b.investor_type,
            b.investor_category
        FROM base b
        CROSS JOIN (SELECT id + 1 AS x FROM range(5)) mult
    )
    SELECT
        'enterprise_investor_' || lpad(cast(n AS STRING), 4, '0'),
        CASE investor_category
            WHEN 'PENSION'          THEN element_at(array('CalPERS','NYSTRS','Texas Teachers','Ohio PERS','Florida SBA'), 1 + n % 5)
            WHEN 'ENDOWMENT'        THEN element_at(array('Harvard Endowment','Yale Investments','Stanford Management'), 1 + n % 3)
            WHEN 'INSURANCE'        THEN element_at(array('MetLife','Prudential','AIG','Allianz'), 1 + n % 4)
            WHEN 'SOVEREIGN_WEALTH' THEN element_at(array('GIC Singapore','ADIA','Norway GPF'), 1 + n % 3)
            WHEN 'FUND_OF_FUNDS'    THEN concat('Partners Group Fund ', cast(n AS STRING))
            WHEN 'FAMILY_OFFICE'    THEN concat('Family Office ', cast(n AS STRING))
            ELSE concat('Investor ', cast(n AS STRING))
        END || ' - ' || cast(n AS STRING),
        investor_type,
        investor_category,
        CASE
            WHEN investor_category = 'SOVEREIGN_WEALTH'
                THEN element_at(array('SGP','ARE','NOR'), 1 + n % 3)
            ELSE 'USA'
        END,
        v_position_start
    FROM multiplied
    WHERE n <= 50;

    -- 3.2 PORTFOLIO GROUPS (20) -----------------------------------------------
    INSERT INTO dim.portfolio_group (
        enterprise_portfolio_group_id, group_name, group_type, strategy,
        vintage_year, target_size, currency_code, effective_start_date
    )
    WITH base AS (
        SELECT * FROM VALUES
            ('CORE',          'Core Income',               2000000000.00),
            ('CORE',          'Core Income',               1500000000.00),
            ('CORE_PLUS',     'Core Plus Growth',          1000000000.00),
            ('CORE_PLUS',     'Core Plus Growth',           800000000.00),
            ('VALUE_ADD',     'Value Add Repositioning',    750000000.00),
            ('VALUE_ADD',     'Value Add Development',      500000000.00),
            ('OPPORTUNISTIC', 'Opportunistic',              400000000.00),
            ('DEBT',          'Senior Lending',            1200000000.00),
            ('DEBT',          'Mezzanine',                  300000000.00),
            ('DEBT',          'Bridge Lending',             250000000.00)
        AS t(group_type, strategy, target_size)
    ),
    multiplied AS (
        SELECT
            row_number() OVER (ORDER BY mult.x, b.group_type, b.strategy) AS n,
            b.group_type, b.strategy, b.target_size,
            2018 + ((row_number() OVER (ORDER BY mult.x, b.group_type, b.strategy)) % 7) AS vintage
        FROM base b
        CROSS JOIN (SELECT id + 1 AS x FROM range(2)) mult
    )
    SELECT
        'enterprise_pg_' || lpad(cast(n AS STRING), 3, '0'),
        concat(group_type, ' Fund ', cast(vintage AS STRING), ' - ', cast(n AS STRING)),
        group_type, strategy, vintage, target_size, 'USD',
        v_position_start
    FROM multiplied
    WHERE n <= 20;

    -- 3.3 PORTFOLIOS (5 per group = 100) --------------------------------------
    INSERT INTO dim.portfolio (
        enterprise_portfolio_id, portfolio_group_sk, portfolio_name, portfolio_type,
        legal_structure, inception_date, currency_code, effective_start_date
    )
    WITH portfolio_seq AS (
        SELECT id + 1 AS p_idx FROM range(5)
    ),
    candidates AS (
        SELECT
            row_number() OVER (ORDER BY pg.portfolio_group_sk, ps.p_idx) AS n,
            pg.portfolio_group_sk, pg.group_name, pg.group_type, ps.p_idx
        FROM dim.portfolio_group pg
        CROSS JOIN portfolio_seq ps
        WHERE pg.is_current = TRUE
    )
    SELECT
        'enterprise_portfolio_' || lpad(cast(n AS STRING), 4, '0'),
        portfolio_group_sk,
        concat(group_name, ' - Portfolio ', cast(n AS STRING)),
        CASE WHEN group_type = 'DEBT' THEN 'DEBT' ELSE 'EQUITY' END,
        element_at(array('LP','LLC','REIT','FUND'), 1 + n % 4),
        date_add(date('2024-01-01'), -n * 30),
        'USD',
        v_position_start
    FROM candidates;

    -- 3.4 ENTITIES (2 per portfolio = 200) ------------------------------------
    INSERT INTO dim.entity (
        enterprise_entity_id, portfolio_sk, entity_name, entity_type,
        legal_structure, jurisdiction, formation_date, effective_start_date
    )
    WITH entity_seq AS (
        SELECT id + 1 AS e_idx FROM range(2)
    ),
    candidates AS (
        SELECT
            row_number() OVER (ORDER BY p.portfolio_sk, es.e_idx) AS n,
            p.portfolio_sk, p.portfolio_name, p.inception_date, es.e_idx
        FROM dim.portfolio p
        CROSS JOIN entity_seq es
        WHERE p.is_current = TRUE
    )
    SELECT
        'enterprise_entity_' || lpad(cast(n AS STRING), 4, '0'),
        portfolio_sk,
        concat(portfolio_name, ' - Entity ', cast(n AS STRING)),
        element_at(array('SPV','HOLDCO','JV','OPERATING'), 1 + n % 4),
        element_at(array('LLC','LP','CORP'), 1 + n % 3),
        element_at(array('Delaware','Delaware','Cayman Islands','Luxembourg','Texas'), 1 + n % 5),
        date_add(inception_date, n * 10),
        v_position_start
    FROM candidates;

    -- 3.5 ASSETS (300) --------------------------------------------------------
    INSERT INTO dim.asset (
        enterprise_asset_id, entity_sk, managing_group_id, asset_name, asset_type,
        property_subtype, city, state_province, country_code,
        square_feet, acquisition_date, acquisition_price, effective_start_date
    )
    WITH asset_types AS (
        SELECT * FROM VALUES
            ('OFFICE',      'CLASS_A',          'New York',  'NY',  'USA', 500000, 250000000.00),
            ('OFFICE',      'CLASS_B',          'Chicago',   'IL',  'USA', 300000, 120000000.00),
            ('RETAIL',      'GROCERY_ANCHORED', 'Dallas',    'TX',  'USA', 150000,  45000000.00),
            ('INDUSTRIAL',  'LOGISTICS',        'Atlanta',   'GA',  'USA', 750000,  85000000.00),
            ('MULTIFAMILY', 'GARDEN',           'Phoenix',   'AZ',  'USA', 200000,  65000000.00),
            ('HOTEL',       'FULL_SERVICE',     'Miami',     'FL',  'USA', 180000, 110000000.00),
            ('OFFICE',      'CLASS_A',          'Toronto',   'ON',  'CAN', 450000, 180000000.00),
            ('RETAIL',      'GROCERY_ANCHORED', 'London',    NULL,  'GBR', 120000,  90000000.00),
            ('INDUSTRIAL',  'LOGISTICS',        'Berlin',    NULL,  'DEU', 600000,  70000000.00),
            ('MULTIFAMILY', 'HIGH_RISE',        'Tokyo',     NULL,  'JPN', 220000,  95000000.00)
        AS t(asset_type, subtype, city, state_code, country_code, sqft, price)
    ),
    groups_lookup AS (
        SELECT
            MAX(CASE WHEN enterprise_group_id = 'GRP_OFFICE'      THEN group_id END) AS office_grp,
            MAX(CASE WHEN enterprise_group_id = 'GRP_RETAIL'      THEN group_id END) AS retail_grp,
            MAX(CASE WHEN enterprise_group_id = 'GRP_INDUSTRIAL'  THEN group_id END) AS industrial_grp,
            MAX(CASE WHEN enterprise_group_id = 'GRP_MULTIFAMILY' THEN group_id END) AS mf_grp,
            MAX(CASE WHEN enterprise_group_id = 'GRP_HOTEL'       THEN group_id END) AS hotel_grp
        FROM dim.department_group
    ),
    candidates AS (
        SELECT
            e.entity_sk, e.formation_date,
            at.asset_type, at.subtype, at.city, at.state_code, at.country_code, at.sqft, at.price,
            row_number() OVER (PARTITION BY e.entity_sk ORDER BY at.asset_type) AS entity_asset_num,
            row_number() OVER (ORDER BY e.entity_sk, at.asset_type)             AS global_row_num
        FROM dim.entity e
        CROSS JOIN asset_types at
        WHERE e.is_current = TRUE
    )
    SELECT
        'enterprise_asset_' || lpad(cast(c.global_row_num AS STRING), 4, '0'),
        c.entity_sk,
        CASE c.asset_type
            WHEN 'OFFICE'      THEN g.office_grp
            WHEN 'RETAIL'      THEN g.retail_grp
            WHEN 'INDUSTRIAL'  THEN g.industrial_grp
            WHEN 'MULTIFAMILY' THEN g.mf_grp
            WHEN 'HOTEL'       THEN g.hotel_grp
        END,
        concat(c.city, ' ', c.asset_type, ' - ', cast(c.global_row_num AS STRING)),
        c.asset_type, c.subtype, c.city, c.state_code, c.country_code, c.sqft,
        date_add(c.formation_date, c.global_row_num * 5),
        c.price,
        v_position_start
    FROM candidates c
    CROSS JOIN groups_lookup g
    WHERE c.entity_asset_num <= 2
    ORDER BY c.global_row_num
    LIMIT 300;

    -- 3.6 SECURITIES (~700: 600 equity/preferred + 100 senior debt) -----------

    -- Equity + Preferred (600)
    INSERT INTO dim.security (
        enterprise_security_id, asset_sk, security_name, security_type,
        cusip, par_value, currency_code, effective_start_date
    )
    WITH sec_types AS (
        SELECT * FROM VALUES
            ('EQUITY',    1000000.00),
            ('PREFERRED',  500000.00)
        AS t(sec_type, par_value)
    ),
    candidates AS (
        SELECT
            row_number() OVER (ORDER BY a.asset_sk, st.sec_type) AS rn,
            a.asset_sk, a.asset_name, st.sec_type, st.par_value
        FROM dim.asset a
        CROSS JOIN sec_types st
        WHERE a.is_current = TRUE
    )
    SELECT
        'enterprise_security_' || lpad(cast(rn AS STRING), 4, '0'),
        asset_sk,
        concat(asset_name, ' - ', sec_type),
        sec_type,
        substring(replace(uuid(), '-', ''), 1, 9),
        par_value,
        'USD',
        v_position_start
    FROM candidates;

    -- Senior debt (100)
    INSERT INTO dim.security (
        enterprise_security_id, asset_sk, security_name, security_type,
        cusip, par_value, coupon_rate, maturity_date, currency_code,
        effective_start_date
    )
    WITH ranked_assets AS (
        SELECT a.asset_sk, a.asset_name,
               row_number() OVER (ORDER BY a.asset_sk) AS rn
        FROM dim.asset a
        WHERE a.is_current = TRUE
    )
    SELECT
        'enterprise_security_' || lpad(cast(600 + rn AS STRING), 4, '0'),
        asset_sk,
        concat(asset_name, ' - SENIOR_DEBT'),
        'SENIOR_DEBT',
        substring(replace(uuid(), '-', ''), 1, 9),
        10000000.00,
        0.055 + (rn % 20) * 0.001,
        add_months(current_date(), 12 * (5 + rn % 5)),
        'USD',
        v_position_start
    FROM ranked_assets
    WHERE rn <= 100;

    -- ====================================================================
    -- PHASE 4: GENERATE ALLOCATIONS
    -- (No SCD2 columns on alloc tables; these are point-in-time facts.)
    -- ====================================================================

    -- 4.1 Investor → Portfolio Group ------------------------------------------
    INSERT INTO bridge.investor_portfolio_group_alloc (
        investor_sk, portfolio_group_sk, ownership_percentage
    )
    WITH paired AS (
        SELECT
            i.investor_sk, pg.portfolio_group_sk,
            pmod(hash(i.investor_sk, pg.portfolio_group_sk), 5)                                    AS slot,
            round(0.5 + pmod(abs(hash(i.investor_sk, pg.portfolio_group_sk, 'pct')), 245) * 0.1, 2) AS pct
        FROM dim.investor i
        CROSS JOIN dim.portfolio_group pg
        WHERE i.is_current = TRUE AND pg.is_current = TRUE
    )
    SELECT investor_sk, portfolio_group_sk, pct
    FROM paired
    WHERE slot = 0;

    -- 4.2 Portfolio Group → Portfolio -----------------------------------------
    INSERT INTO bridge.portfolio_group_portfolio_alloc (
        portfolio_group_sk, portfolio_sk, ownership_percentage
    )
    SELECT p.portfolio_group_sk, p.portfolio_sk, 100.00
    FROM dim.portfolio p
    WHERE p.is_current = TRUE AND p.portfolio_group_sk IS NOT NULL;

    -- 4.3 Portfolio → Entity --------------------------------------------------
    INSERT INTO bridge.portfolio_entity_alloc (
        portfolio_sk, entity_sk, ownership_percentage
    )
    SELECT
        e.portfolio_sk, e.entity_sk,
        CASE
            WHEN pmod(abs(hash(e.entity_sk)), 10) = 0 THEN 50.00
            WHEN pmod(abs(hash(e.entity_sk)), 10) = 1 THEN 75.00
            ELSE 100.00
        END
    FROM dim.entity e
    WHERE e.is_current = TRUE AND e.portfolio_sk IS NOT NULL;

    -- ====================================================================
    -- PHASE 5: GENERATE CROSSWALK MAPPINGS
    -- All crosswalks have effective_start_date = v_position_start so they
    -- exist from the beginning of the position window.
    -- ====================================================================

    -- 5.1 Entity ONE_TO_ONE: State Street → Enterprise ------------------------
    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, effective_start_date
    )
    SELECT
        kd.domain_id, ss.source_id,
        'SS_ENT_' || lpad(cast(e.entity_sk AS STRING), 5, '0'),
        ent.source_id, e.enterprise_entity_id,
        'ONE_TO_ONE',
        v_position_start
    FROM dim.entity e
    CROSS JOIN (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'ENTITY')      kd
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'STATE_STREET') ss
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'ENTERPRISE')   ent
    WHERE e.is_current = TRUE;

    -- 5.2 Entity MANY_TO_ONE -------------------------------------------------
    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, effective_start_date
    )
    WITH first_10 AS (
        SELECT entity_sk, enterprise_entity_id
        FROM dim.entity
        WHERE is_current = TRUE
        ORDER BY entity_sk
        LIMIT 10
    ),
    fanout AS (
        SELECT id + 1 AS n FROM range(3)
    )
    SELECT
        kd.domain_id, ss.source_id,
        concat('SS_ENT_CONSOL_', cast(f.entity_sk AS STRING), '_', cast(fan.n AS STRING)),
        ent.source_id, f.enterprise_entity_id,
        'MANY_TO_ONE',
        v_position_start
    FROM first_10 f
    CROSS JOIN fanout fan
    CROSS JOIN (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'ENTITY')      kd
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'STATE_STREET') ss
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'ENTERPRISE')   ent;

    -- 5.3 Entity ONE_TO_MANY -------------------------------------------------
    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, split_sequence, split_description, effective_start_date
    )
    WITH ranked AS (
        SELECT
            entity_sk, enterprise_entity_id,
            row_number() OVER (ORDER BY entity_sk) AS rn
        FROM dim.entity
        WHERE is_current = TRUE
    ),
    splits AS (
        SELECT
            entity_sk, enterprise_entity_id, rn,
            cast((rn - 11) / 2 AS INT) AS pair_idx,
            CASE rn % 2 WHEN 1 THEN 1 ELSE 2 END AS seq,
            CASE rn % 2 WHEN 1 THEN 'Office Component' ELSE 'Retail Component' END AS split_desc
        FROM ranked
        WHERE rn BETWEEN 11 AND 30
    )
    SELECT
        kd.domain_id, bbg.source_id,
        concat('BBG_MIXED_USE_', cast(s.pair_idx AS STRING)),
        ent.source_id, s.enterprise_entity_id,
        'ONE_TO_MANY', s.seq, s.split_desc,
        v_position_start
    FROM splits s
    CROSS JOIN (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'ENTITY')    kd
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'BLOOMBERG') bbg
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'ENTERPRISE') ent;

    -- 5.4 Security ONE_TO_ONE: Bloomberg → Enterprise -------------------------
    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, effective_start_date
    )
    SELECT
        kd.domain_id, bbg.source_id,
        concat('BBG_SEC_', s.cusip),
        ent.source_id, s.enterprise_security_id,
        'ONE_TO_ONE',
        v_position_start
    FROM dim.security s
    CROSS JOIN (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'SECURITY')  kd
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'BLOOMBERG') bbg
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'ENTERPRISE') ent
    WHERE s.is_current = TRUE AND s.cusip IS NOT NULL;

    -- 5.5 Asset ONE_TO_ONE: Yardi → Enterprise --------------------------------
    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, effective_start_date
    )
    SELECT
        kd.domain_id, y.source_id,
        'YARDI_PROP_' || lpad(cast(a.asset_sk AS STRING), 5, '0'),
        ent.source_id, a.enterprise_asset_id,
        'ONE_TO_ONE',
        v_position_start
    FROM dim.asset a
    CROSS JOIN (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = 'ASSET')      kd
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'YARDI')      y
    CROSS JOIN (SELECT source_id FROM bridge.source_registry WHERE source_code = 'ENTERPRISE') ent
    WHERE a.is_current = TRUE;

    -- ====================================================================
    -- PHASE 6: SIMULATE SCD2 HISTORY (controlled by p_simulate_history)
    --
    -- Events are DISTRIBUTED across the position window. For each scenario:
    --   - Pick N records (deterministic by SK)
    --   - Compute event_date = v_position_start + window_days * idx / (N + 1)
    --     plus a deterministic ±60-day jitter from hash(record_sk).
    --   - INSERT new versions with effective_start_date = event_date
    --   - MERGE old versions: is_current=FALSE,
    --                         effective_end_date = event_date - 1 day,
    --                         succeeding_record_sk = new_sk
    --
    -- Scale of events is fixed counts (10/25/5/20). For long windows the
    -- events spread out; for short windows they cluster more densely. Either
    -- way you get the same SHAPE of history to query against.
    -- ====================================================================
    IF p_simulate_history THEN

        -- 6.1 INVESTOR RENAMES (10 events) ------------------------------------
        -- New version: INSERT with preceding_record_sk pointing to old.
        INSERT INTO dim.investor (
            enterprise_investor_id, investor_name, investor_type, investor_category, country_code,
            is_current, effective_start_date, preceding_record_sk
        )
        WITH picks AS (
            SELECT *, row_number() OVER (ORDER BY investor_sk) AS event_idx
            FROM (
                SELECT *
                FROM dim.investor
                WHERE is_current = TRUE
                ORDER BY investor_sk
                LIMIT 10
            )
        )
        SELECT
            enterprise_investor_id,
            concat(investor_name, ' (Renamed ', cast(event_idx AS STRING), ')'),
            investor_type, investor_category, country_code,
            TRUE,
            -- Spread events evenly with deterministic jitter, clamped to
            -- stay inside (v_position_start, v_position_end).
            date_add(
                v_position_start,
                GREATEST(1, LEAST(v_window_days - 1,
                    cast(v_window_days * event_idx / 11 AS INT)
                    + (pmod(abs(hash(investor_sk)), 121) - 60)
                ))
            ),
            investor_sk
        FROM picks;

        -- Close out old versions
        MERGE INTO dim.investor AS tgt
        USING (
            SELECT
                old.investor_sk            AS old_sk,
                new.investor_sk            AS new_sk,
                new.effective_start_date   AS new_start
            FROM dim.investor old
            JOIN dim.investor new
                 ON new.preceding_record_sk = old.investor_sk
                AND new.is_current = TRUE
            WHERE old.is_current = TRUE
              AND old.succeeding_record_sk IS NULL
        ) AS chain
        ON tgt.investor_sk = chain.old_sk
        WHEN MATCHED THEN UPDATE SET
            is_current           = FALSE,
            effective_end_date   = date_sub(chain.new_start, 1),
            succeeding_record_sk = chain.new_sk,
            modified_at          = current_timestamp(),
            modified_by          = current_user();

        -- 6.2 ENTITY RESTRUCTURINGS (25 events) -------------------------------
        INSERT INTO dim.entity (
            enterprise_entity_id, portfolio_sk, entity_name, entity_type,
            legal_structure, jurisdiction, formation_date,
            is_current, effective_start_date, preceding_record_sk
        )
        WITH picks AS (
            SELECT *, row_number() OVER (ORDER BY entity_sk) AS event_idx
            FROM (
                SELECT *
                FROM dim.entity
                WHERE is_current = TRUE
                ORDER BY entity_sk
                LIMIT 25
            )
        )
        SELECT
            enterprise_entity_id, portfolio_sk,
            concat(entity_name, ' (Restructured ', cast(event_idx AS STRING), ')'),
            entity_type, legal_structure, jurisdiction, formation_date,
            TRUE,
            date_add(
                v_position_start,
                GREATEST(1, LEAST(v_window_days - 1,
                    cast(v_window_days * event_idx / 26 AS INT)
                    + (pmod(abs(hash(entity_sk)), 121) - 60)
                ))
            ),
            entity_sk
        FROM picks;

        MERGE INTO dim.entity AS tgt
        USING (
            SELECT
                old.entity_sk            AS old_sk,
                new.entity_sk            AS new_sk,
                new.effective_start_date AS new_start
            FROM dim.entity old
            JOIN dim.entity new
                 ON new.preceding_record_sk = old.entity_sk
                AND new.is_current = TRUE
            WHERE old.is_current = TRUE
              AND old.succeeding_record_sk IS NULL
        ) AS chain
        ON tgt.entity_sk = chain.old_sk
        WHEN MATCHED THEN UPDATE SET
            is_current           = FALSE,
            effective_end_date   = date_sub(chain.new_start, 1),
            succeeding_record_sk = chain.new_sk,
            modified_at          = current_timestamp(),
            modified_by          = current_user();

        -- 6.3 SOFT-DELETED ENTITIES (5 events) --------------------------------
        -- Pick 5 entities still is_current=TRUE after 6.2 (those with no
        -- preceding_record_sk and no successor — i.e., never restructured).
        -- Close them WITHOUT inserting a successor: SCD2 representation of
        -- a dissolution / sell-off.
        --
        -- Spark UPDATE doesn't support a FROM clause, so we use MERGE with
        -- a derived source CTE that pre-computes each dissolution_date.
        MERGE INTO dim.entity AS tgt
        USING (
            SELECT
                entity_sk,
                date_add(
                    v_position_start,
                    GREATEST(1, LEAST(v_window_days - 1,
                        cast(v_window_days * dissolution_idx / 6 AS INT)
                        + (pmod(abs(hash(entity_sk)), 121) - 60)
                    ))
                ) AS dissolution_date
            FROM (
                SELECT entity_sk,
                       row_number() OVER (ORDER BY entity_sk) AS dissolution_idx
                FROM dim.entity
                WHERE is_current = TRUE
                  AND succeeding_record_sk IS NULL
                  AND preceding_record_sk IS NULL  -- skip 6.2's newly inserted rows
                ORDER BY entity_sk
                LIMIT 5
            )
        ) AS picks
        ON tgt.entity_sk = picks.entity_sk
        WHEN MATCHED THEN UPDATE SET
            is_current         = FALSE,
            effective_end_date = picks.dissolution_date,
            modified_at        = current_timestamp(),
            modified_by        = current_user();

        -- 6.4 CROSSWALK MAPPING UPDATES (20 events) ---------------------------
        INSERT INTO bridge.key_crosswalk (
            domain_id, source_system_id, source_key, target_system_id, target_key,
            relationship_type, is_current, effective_start_date, preceding_record_sk
        )
        WITH picks AS (
            SELECT *, row_number() OVER (ORDER BY crosswalk_sk) AS event_idx
            FROM (
                SELECT kc.*
                FROM bridge.key_crosswalk kc
                JOIN bridge.key_domain      kd ON kc.domain_id        = kd.domain_id  AND kd.domain_code  = 'ENTITY'
                JOIN bridge.source_registry sr ON kc.source_system_id = sr.source_id  AND sr.source_code  = 'STATE_STREET'
                WHERE kc.is_current = TRUE
                  AND kc.relationship_type = 'ONE_TO_ONE'
                ORDER BY kc.crosswalk_sk
                LIMIT 20
            )
        )
        SELECT
            domain_id, source_system_id, source_key, target_system_id,
            concat('REMAPPED_', target_key),
            relationship_type,
            TRUE,
            date_add(
                v_position_start,
                GREATEST(1, LEAST(v_window_days - 1,
                    cast(v_window_days * event_idx / 21 AS INT)
                    + (pmod(abs(hash(crosswalk_sk)), 121) - 60)
                ))
            ),
            crosswalk_sk
        FROM picks;

        MERGE INTO bridge.key_crosswalk AS tgt
        USING (
            SELECT
                old.crosswalk_sk         AS old_sk,
                new.crosswalk_sk         AS new_sk,
                new.effective_start_date AS new_start
            FROM bridge.key_crosswalk old
            JOIN bridge.key_crosswalk new
                 ON new.preceding_record_sk = old.crosswalk_sk
                AND new.is_current = TRUE
            WHERE old.is_current = TRUE
              AND old.succeeding_record_sk IS NULL
        ) AS chain
        ON tgt.crosswalk_sk = chain.old_sk
        WHEN MATCHED THEN UPDATE SET
            is_current           = FALSE,
            effective_end_date   = date_sub(chain.new_start, 1),
            succeeding_record_sk = chain.new_sk,
            modified_at          = current_timestamp(),
            modified_by          = current_user();

    END IF;

    -- ====================================================================
    -- PHASE 7: GENERATE FACT.POSITION (canonical Kimball SCD2 resolution)
    --
    -- For each (position_date d, enterprise_security_id), resolve the dim
    -- chain to whichever VERSION of each level was current at date d. This
    -- is the standard pattern in production warehouses.
    --
    -- THE ANCHOR PATTERN
    -- ------------------
    -- FK columns (security.asset_sk, asset.entity_sk, entity.portfolio_sk)
    -- point to a SPECIFIC SCD2 version — typically the version current when
    -- the parent record was created. We call that the "anchor". The anchor
    -- gives us the durable enterprise_xxx_id (the natural key); the temporal
    -- join then picks whichever SCD2 version of that enterprise_id is valid
    -- at date d.
    --
    -- For each level we do a two-step join:
    --     1. JOIN to anchor   (by SK — gets the enterprise_xxx_id)
    --     2. JOIN to version  (by enterprise_xxx_id + temporal filter)
    --
    -- BEHAVIOR
    -- --------
    --   Restructured entity (Phase 6.2):
    --     Positions BEFORE the event reference the OLD entity_sk; positions
    --     AFTER the event reference the NEW entity_sk. Same enterprise_entity_id
    --     throughout. Both SKs receive fact rows over their respective ranges.
    --
    --   Soft-deleted entity (Phase 6.3):
    --     For dates after dissolution, no e_at_d row matches the temporal
    --     filter. Those positions are NOT generated. fact.position naturally
    --     stops at the dissolution date — exactly what real ETL emits when
    --     the source system stops sending positions.
    --
    --   Investor renames (Phase 6.1) and crosswalk supersessions (Phase 6.4):
    --     Have no effect on this fact table; investors and crosswalks aren't
    --     part of the position grain. They're resolved by downstream joins.
    --
    -- VOLUME ESTIMATE
    -- ---------------
    -- Default 20-year window with 700 securities, minus the 5 soft-deleted
    -- entities × ~14 securities/entity × ~half their lifetime missing ≈
    -- 5.0–5.1M rows. Restructured entities don't reduce volume; their
    -- positions just split across old + new SKs.
    -- ====================================================================
    IF NOT p_skip_positions THEN

        INSERT INTO fact.position (
            position_date, portfolio_sk, entity_sk, security_sk,
            quantity, market_value, book_value, cost_basis,
            unrealized_gain_loss, unit_price, price_source,
            local_currency_code, reporting_currency_code, fx_rate,
            record_source
        )
        WITH dates AS (
            -- sequence() accepts non-foldable args, unlike range().
            SELECT explode(sequence(v_position_start, v_position_end, interval 1 day)) AS d
        ),
        distinct_securities AS (
            -- One row per durable enterprise_security_id, regardless of how
            -- many SCD2 versions exist for that natural key. Currently each
            -- chain has length 1 (Phase 6 doesn't restructure securities)
            -- but this generalizes to length N.
            SELECT DISTINCT enterprise_security_id FROM dim.security
        )
        SELECT
            d.d                                                                AS position_date,
            p_at_d.portfolio_sk,
            e_at_d.entity_sk,
            s_at_d.security_sk,
            1000 + (s_at_d.security_sk % 100) * 10                              AS quantity,
            s_at_d.par_value * (1 + (cast(rand() * 21 AS INT) - 10) / 100.0)    AS market_value,
            s_at_d.par_value                                                    AS book_value,
            s_at_d.par_value * 0.95                                             AS cost_basis,
            s_at_d.par_value * (cast(rand() * 21 AS INT) - 10) / 100.0          AS unrealized_gain_loss,
            s_at_d.par_value / NULLIF(1000 + (s_at_d.security_sk % 100) * 10, 0) AS unit_price,
            'BLOOMBERG'                                                         AS price_source,
            'USD'                                                               AS local_currency_code,
            'USD'                                                               AS reporting_currency_code,
            1.0                                                                 AS fx_rate,
            'STATE_STREET'                                                      AS record_source
        FROM dates d
        CROSS JOIN distinct_securities ds
        -- SECURITY: pick version current at d
        JOIN dim.security s_at_d
            ON s_at_d.enterprise_security_id = ds.enterprise_security_id
           AND s_at_d.effective_start_date <= d.d
           AND (s_at_d.effective_end_date IS NULL OR s_at_d.effective_end_date >= d.d)
        -- ASSET: anchor → enterprise_id → version current at d
        JOIN dim.asset a_anchor
            ON a_anchor.asset_sk = s_at_d.asset_sk
        JOIN dim.asset a_at_d
            ON a_at_d.enterprise_asset_id = a_anchor.enterprise_asset_id
           AND a_at_d.effective_start_date <= d.d
           AND (a_at_d.effective_end_date IS NULL OR a_at_d.effective_end_date >= d.d)
        -- ENTITY: anchor → enterprise_id → version current at d
        JOIN dim.entity e_anchor
            ON e_anchor.entity_sk = a_at_d.entity_sk
        JOIN dim.entity e_at_d
            ON e_at_d.enterprise_entity_id = e_anchor.enterprise_entity_id
           AND e_at_d.effective_start_date <= d.d
           AND (e_at_d.effective_end_date IS NULL OR e_at_d.effective_end_date >= d.d)
        -- PORTFOLIO: anchor → enterprise_id → version current at d
        JOIN dim.portfolio p_anchor
            ON p_anchor.portfolio_sk = e_at_d.portfolio_sk
        JOIN dim.portfolio p_at_d
            ON p_at_d.enterprise_portfolio_id = p_anchor.enterprise_portfolio_id
           AND p_at_d.effective_start_date <= d.d
           AND (p_at_d.effective_end_date IS NULL OR p_at_d.effective_end_date >= d.d);

    END IF;

END;

-- ============================================================================
-- INVOKE THE PROCEDURE WITH CURRENT SESSION VARIABLE VALUES
-- ============================================================================
-- This is the line that actually runs the seed. Override the session
-- variables above (with SET VARIABLE or by editing the DEFAULTs) before
-- this line executes to change behavior.
CALL bridge.usp_reset_setup_seed_data(
    p_position_start_date => position_start_date,
    p_position_end_date   => position_end_date,
    p_simulate_history    => simulate_history,
    p_skip_positions      => skip_positions
);

SELECT 'Seed complete.' AS status;
