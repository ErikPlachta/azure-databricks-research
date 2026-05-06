-- ============================================================================
-- 01_pre_bronze/08_seed.sql
-- Deterministic 10-team multi-source seed across all 24 raw tables.
--
-- Sized via 01_config.sql session vars. Free Edition default produces
-- ~100K position rows (~10K per team × 10 teams across the position window).
-- Paid override produces ~2.5M positions.
--
-- Determinism: every value derived from sha2(seed_components, 256) so a given
-- (config, version) yields identical seed across runs. No rand() / uuid().
--
-- Idempotent: TRUNCATE + INSERT pattern. Re-running drops and rebuilds.
--
-- Phases:
--   Phase 1: Reference / fixed-cardinality sets
--             (FX rates, industry classifications, reporting groups,
--              business units, employees, business unit memberships)
--   Phase 2: Masters (entities, securities, assets, contracts)
--   Phase 3: Daily fact tables
--             (positions, transactions, prices, cash flows, NAVs)
--   Phase 4: Periodic / event tables
--             (risk, performance, compliance, blotter, contract summary,
--              covenants, capital activity, collateral)
--   Phase 5: Ratings (entity + security)
--   Phase 6: SCD2 history events (corrections / restatements)
-- ============================================================================

-- Self-declare every session variable this file references, with the same
-- defaults as 01_config.sql. This file is independently runnable in fresh
-- sessions. If you want to override a default, either:
--   (a) Edit the DEFAULT inline below, OR
--   (b) Run 01_config.sql first AND THEN insert SET VARIABLE statements
--       AFTER this DECLARE block (the DECLARE OR REPLACE here resets
--       customizations from 01_config.sql).
DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';

DECLARE OR REPLACE VARIABLE position_start_date DATE    DEFAULT date_sub(current_date(), 365 * 5);
DECLARE OR REPLACE VARIABLE position_end_date   DATE    DEFAULT current_date();
DECLARE OR REPLACE VARIABLE simulate_history    BOOLEAN DEFAULT TRUE;
DECLARE OR REPLACE VARIABLE skip_positions      BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_transactions   BOOLEAN DEFAULT FALSE;

DECLARE OR REPLACE VARIABLE skip_state_street   BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_aladdin        BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_aspen          BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_efront         BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_internal_admin BOOLEAN DEFAULT FALSE;
DECLARE OR REPLACE VARIABLE skip_bloomberg      BOOLEAN DEFAULT FALSE;

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

DECLARE OR REPLACE VARIABLE seed_n_securities                INT DEFAULT 200;
DECLARE OR REPLACE VARIABLE seed_n_entities                  INT DEFAULT 100;
DECLARE OR REPLACE VARIABLE seed_n_assets                    INT DEFAULT 60;
DECLARE OR REPLACE VARIABLE seed_n_contracts                 INT DEFAULT 100;
DECLARE OR REPLACE VARIABLE seed_positions_per_team_per_year INT DEFAULT 2000;
DECLARE OR REPLACE VARIABLE seed_txns_per_security_per_year  INT DEFAULT 8;

EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- PHASE 1 — Reference / fixed-cardinality sets
-- ============================================================================

-- 1.1 raw_bloomberg.fx_rate_raw -----------------------------------------------
-- Daily rates across the position window, USD <-> {EUR, GBP, JPY, CAD, AUD}.
TRUNCATE TABLE raw_bloomberg.fx_rate_raw;
INSERT INTO raw_bloomberg.fx_rate_raw (
    source_key, enterprise_key, from_currency, to_currency, rate_date, fx_rate,
    rate_type, record_source, loaded_at
)
WITH days AS (
    SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 DAY)) AS rate_date
),
pairs AS (
    SELECT * FROM (VALUES
        ('USD','EUR',CAST(0.92 AS DOUBLE)),('USD','GBP',CAST(0.79 AS DOUBLE)),
        ('USD','JPY',CAST(150.0 AS DOUBLE)),('USD','CAD',CAST(1.36 AS DOUBLE)),
        ('USD','AUD',CAST(1.52 AS DOUBLE)),
        ('EUR','USD',CAST(1.087 AS DOUBLE)),('GBP','USD',CAST(1.266 AS DOUBLE)),
        ('JPY','USD',CAST(0.0067 AS DOUBLE)),('CAD','USD',CAST(0.735 AS DOUBLE)),
        ('AUD','USD',CAST(0.658 AS DOUBLE))
    ) AS t(from_currency, to_currency, base_rate)
)
SELECT
    concat(p.from_currency,'_',p.to_currency,'_',date_format(d.rate_date,'yyyyMMdd')) AS source_key,
    concat('EK_FX_',p.from_currency,'_',p.to_currency,'_',date_format(d.rate_date,'yyyyMMdd')) AS enterprise_key,
    p.from_currency,
    p.to_currency,
    d.rate_date,
    -- Deterministic ±2% drift around base rate via hash
    cast(p.base_rate * (1 + (cast(conv(substr(sha2(concat(p.from_currency,p.to_currency,d.rate_date),256),1,8),16,10) AS DOUBLE) % 4000 - 2000) / 100000) AS DECIMAL(18,8)) AS fx_rate,
    'CLOSE' AS rate_type,
    'bloomberg',
    current_timestamp()
FROM days d CROSS JOIN pairs p
WHERE NOT skip_bloomberg;

-- 1.2 raw_aspen.industry_classification_raw -----------------------------------
TRUNCATE TABLE raw_aspen.industry_classification_raw;
INSERT INTO raw_aspen.industry_classification_raw VALUES
    ('GICS_10','EK_IC_GICS_10','10','Energy',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_15','EK_IC_GICS_15','15','Materials',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_20','EK_IC_GICS_20','20','Industrials',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_25','EK_IC_GICS_25','25','Consumer Discretionary',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_30','EK_IC_GICS_30','30','Consumer Staples',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_35','EK_IC_GICS_35','35','Health Care',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_40','EK_IC_GICS_40','40','Financials',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_45','EK_IC_GICS_45','45','Information Technology',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_50','EK_IC_GICS_50','50','Communication Services',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_55','EK_IC_GICS_55','55','Utilities',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_60','EK_IC_GICS_60','60','Real Estate',NULL,1,'GICS','aspen',current_timestamp()),
    ('GICS_4010','EK_IC_GICS_4010','4010','Banks','40',2,'GICS','aspen',current_timestamp()),
    ('GICS_4020','EK_IC_GICS_4020','4020','Diversified Financials','40',2,'GICS','aspen',current_timestamp()),
    ('GICS_4030','EK_IC_GICS_4030','4030','Insurance','40',2,'GICS','aspen',current_timestamp()),
    ('GICS_6010','EK_IC_GICS_6010','6010','Equity REITs','60',2,'GICS','aspen',current_timestamp());

-- 1.3 raw_aspen.reporting_group_raw -------------------------------------------
TRUNCATE TABLE raw_aspen.reporting_group_raw;
INSERT INTO raw_aspen.reporting_group_raw VALUES
    ('RG_STRAT_PD','EK_RG_PD','RG_STRAT_PD','Private Debt',NULL,1,'STRATEGY','aspen',current_timestamp()),
    ('RG_STRAT_RE','EK_RG_RE','RG_STRAT_RE','Real Estate',NULL,1,'STRATEGY','aspen',current_timestamp()),
    ('RG_STRAT_PE','EK_RG_PE','RG_STRAT_PE','Private Equity',NULL,1,'STRATEGY','aspen',current_timestamp()),
    ('RG_STRAT_INFRA','EK_RG_INFRA','RG_STRAT_INFRA','Infrastructure',NULL,1,'STRATEGY','aspen',current_timestamp()),
    ('RG_STRAT_PUB','EK_RG_PUB','RG_STRAT_PUB','Public Markets',NULL,1,'STRATEGY','aspen',current_timestamp()),
    ('RG_GEO_NA','EK_RG_NA','RG_GEO_NA','North America',NULL,1,'GEOGRAPHY','aspen',current_timestamp()),
    ('RG_GEO_EU','EK_RG_EU','RG_GEO_EU','Europe',NULL,1,'GEOGRAPHY','aspen',current_timestamp()),
    ('RG_GEO_APAC','EK_RG_APAC','RG_GEO_APAC','Asia Pacific',NULL,1,'GEOGRAPHY','aspen',current_timestamp());

-- 1.4 raw_internal_admin.business_unit_master_raw -----------------------------
-- 10 teams: 5 PD strategy + 5 non-PD.
TRUNCATE TABLE raw_internal_admin.business_unit_master_raw;
INSERT INTO raw_internal_admin.business_unit_master_raw VALUES
    ('BU_PD_DL','EK_BU_PD_DL','team_pd_direct_lending','Private Debt — Direct Lending','INVESTMENT_TEAM','BU_PD','PRIVATE_DEBT','Mid-market direct corporate lending','EMP_001',DATE'2010-01-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_PD_DI','EK_BU_PD_DI','team_pd_distressed','Private Debt — Distressed','INVESTMENT_TEAM','BU_PD','PRIVATE_DEBT','Distressed debt and special situations','EMP_002',DATE'2011-03-15',TRUE,'internal_admin',current_timestamp()),
    ('BU_PD_MZ','EK_BU_PD_MZ','team_pd_mezzanine','Private Debt — Mezzanine','INVESTMENT_TEAM','BU_PD','PRIVATE_DEBT','Subordinated/mezzanine financing','EMP_003',DATE'2009-06-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_PD_RE','EK_BU_PD_RE','team_pd_real_estate_debt','Private Debt — Real Estate','INVESTMENT_TEAM','BU_PD','PRIVATE_DEBT','CRE lending and mortgages','EMP_004',DATE'2012-09-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_PD_SF','EK_BU_PD_SF','team_pd_specialty_finance','Private Debt — Specialty Finance','INVESTMENT_TEAM','BU_PD','PRIVATE_DEBT','Royalties, litigation finance, esoteric debt','EMP_005',DATE'2015-04-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_RE_C','EK_BU_RE_C','team_re_core','Real Estate — Core','INVESTMENT_TEAM','BU_RE','REAL_ESTATE','Stabilized core real estate','EMP_006',DATE'2008-01-15',TRUE,'internal_admin',current_timestamp()),
    ('BU_RE_VA','EK_BU_RE_VA','team_re_value_add','Real Estate — Value Add','INVESTMENT_TEAM','BU_RE','REAL_ESTATE','Value-add and opportunistic RE','EMP_007',DATE'2010-08-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_PE_BO','EK_BU_PE_BO','team_pe_buyout','Private Equity — Buyout','INVESTMENT_TEAM','BU_PE','PRIVATE_EQUITY','Mid-market buyouts','EMP_008',DATE'2007-05-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_INFRA','EK_BU_INFRA','team_infra','Infrastructure','INVESTMENT_TEAM','BU_INFRA','INFRASTRUCTURE','Core and core-plus infrastructure','EMP_009',DATE'2013-11-01',TRUE,'internal_admin',current_timestamp()),
    ('BU_PUB','EK_BU_PUB','team_public_equity','Public Equity','INVESTMENT_TEAM','BU_PUB','PUBLIC_EQUITY','Long-only public equity','EMP_010',DATE'2005-01-01',TRUE,'internal_admin',current_timestamp());

-- 1.5 raw_internal_admin.employee_raw -----------------------------------------
TRUNCATE TABLE raw_internal_admin.employee_raw;
INSERT INTO raw_internal_admin.employee_raw
SELECT
    concat('EMP_',lpad(cast(id AS STRING),3,'0')) AS source_key,
    concat('EK_EMP_',lpad(cast(id AS STRING),3,'0')) AS enterprise_key,
    concat('EMP_',lpad(cast(id AS STRING),3,'0')) AS employee_id,
    concat('Employee_',lpad(cast(id AS STRING),3,'0')) AS full_name,
    concat('emp',lpad(cast(id AS STRING),3,'0'),'@example.com') AS email,
    date_add(DATE'2000-01-01', cast(conv(substr(sha2(concat('emp',id),256),1,6),16,10) AS INT) % 7300) AS hire_date,
    CAST(NULL AS DATE) AS termination_date,
    element_at(array('IT','Finance','Risk','Operations','Investment'), 1 + cast(conv(substr(sha2(concat('dept',id),256),1,4),16,10) AS INT) % 5) AS department,
    element_at(array('Analyst','Associate','VP','Director','MD'), 1 + cast(conv(substr(sha2(concat('title',id),256),1,4),16,10) AS INT) % 5) AS title,
    'internal_admin',
    current_timestamp()
FROM (SELECT explode(sequence(1, 50)) AS id);

-- 1.6 raw_internal_admin.business_unit_membership_raw -------------------------
-- Each BU gets 4 contiguous employees (BU 1 -> EMP_001..004, BU 2 -> EMP_005..008, ...).
-- bu_idx derived via ROW_NUMBER (BU source_keys are non-numeric so we can't
-- pull an index from them via substr/cast).
TRUNCATE TABLE raw_internal_admin.business_unit_membership_raw;
INSERT INTO raw_internal_admin.business_unit_membership_raw
WITH bu_indexed AS (
    SELECT
        bu.*,
        ROW_NUMBER() OVER (ORDER BY bu.established_date, bu.bu_code) AS bu_idx
    FROM raw_internal_admin.business_unit_master_raw bu
),
memberships AS (
    SELECT
        bu.bu_code,
        bu.established_date,
        e.source_key AS employee_source_key,
        m.member_idx,
        cast(conv(substr(sha2(concat('memoff',m.member_idx),256),1,4),16,10) AS INT) % 365 AS member_offset
    FROM bu_indexed bu
    CROSS JOIN (SELECT explode(sequence(1, 4)) AS member_idx) m
    JOIN raw_internal_admin.employee_raw e
        ON cast(substr(e.source_key, 5) AS INT) = (bu.bu_idx - 1) * 4 + m.member_idx
)
SELECT
    concat(bu_code,'_',employee_source_key,'_',date_format(date_add(established_date, member_offset),'yyyyMMdd')) AS source_key,
    concat('EK_BUM_',bu_code,'_',employee_source_key) AS enterprise_key,
    bu_code,
    employee_source_key AS employee_id,
    element_at(array('HEAD','SENIOR','MID','JUNIOR','SUPPORT'), 1 + cast(conv(substr(sha2(concat(bu_code,employee_source_key),256),1,4),16,10) AS INT) % 5) AS role,
    date_add(established_date, member_offset) AS start_date,
    CAST(NULL AS DATE) AS end_date,
    TRUE AS is_active,
    'internal_admin' AS record_source,
    current_timestamp() AS loaded_at
FROM memberships
WHERE NOT skip_internal_admin;

SELECT 'phase 1 (reference/fixed sets) complete' AS status;

-- ============================================================================
-- PHASE 2 — Masters (entities, securities, assets, contracts)
-- ============================================================================

-- 2.1 raw_aspen.entity_master_raw ---------------------------------------------
TRUNCATE TABLE raw_aspen.entity_master_raw;
INSERT INTO raw_aspen.entity_master_raw
SELECT
    concat('ASP_ENT_',lpad(cast(id AS STRING),4,'0')) AS source_key,
    concat('EK_ENT_',lpad(cast(id AS STRING),4,'0')) AS enterprise_key,
    concat('Entity_',lpad(cast(id AS STRING),4,'0')) AS entity_name,
    element_at(array('CORPORATE','FUND','SPV','TRUST'), 1 + cast(conv(substr(sha2(concat('etype',id),256),1,4),16,10) AS INT) % 4) AS entity_type,
    element_at(array('LLC','LP','Inc','Trust','PLC','GmbH'), 1 + cast(conv(substr(sha2(concat('legal',id),256),1,4),16,10) AS INT) % 6) AS legal_structure,
    element_at(array('USA','GBR','LUX','CYM','IRL','SGP'), 1 + cast(conv(substr(sha2(concat('juris',id),256),1,4),16,10) AS INT) % 6) AS jurisdiction,
    concat(lpad(cast(cast(conv(substr(sha2(concat('tax',id),256),1,8),16,10) AS BIGINT) % 99999999 AS STRING),8,'0')) AS tax_id,
    date_add(DATE'1995-01-01', cast(conv(substr(sha2(concat('form',id),256),1,6),16,10) AS INT) % 10950) AS formation_date,
    CAST(NULL AS DATE) AS dissolution_date,
    CAST(NULL AS STRING) AS parent_entity_source_key,
    TRUE AS is_active,
    concat(cast(cast(conv(substr(sha2(concat('addr',id),256),1,4),16,10) AS INT) % 9999 AS STRING),' Main St') AS address_line,
    element_at(array('New York','London','San Francisco','Singapore','Frankfurt'), 1 + cast(conv(substr(sha2(concat('city',id),256),1,4),16,10) AS INT) % 5) AS city,
    CAST(NULL AS STRING) AS state_region,
    element_at(array('USA','GBR','USA','SGP','DEU'), 1 + cast(conv(substr(sha2(concat('cnty',id),256),1,4),16,10) AS INT) % 5) AS country,
    'aspen',
    current_timestamp()
FROM (SELECT explode(sequence(1, seed_n_entities)) AS id)
WHERE NOT skip_aspen;

-- 2.2 raw_aspen.security_master_raw -------------------------------------------
TRUNCATE TABLE raw_aspen.security_master_raw;
INSERT INTO raw_aspen.security_master_raw
SELECT
    concat('ASP_SEC_',lpad(cast(id AS STRING),4,'0')) AS source_key,
    concat('EK_SEC_',lpad(cast(id AS STRING),4,'0')) AS enterprise_key,
    concat('Security_',lpad(cast(id AS STRING),4,'0')) AS security_name,
    element_at(array('SENIOR_DEBT','SUBORD_DEBT','MEZZANINE','EQUITY','PREFERRED','CONVERTIBLE'), 1 + cast(conv(substr(sha2(concat('stype',id),256),1,4),16,10) AS INT) % 6) AS security_type,
    element_at(array('SENIOR_DEBT','MEZZ','DISTRESSED','RE_DEBT','SPECIALTY','PRIVATE_EQUITY','PUBLIC_EQUITY'), 1 + cast(conv(substr(sha2(concat('aclass',id),256),1,4),16,10) AS INT) % 7) AS asset_class,
    NULL AS sub_asset_class,
    date_add(DATE'2008-01-01', cast(conv(substr(sha2(concat('issue',id),256),1,6),16,10) AS INT) % 5475) AS issue_date,
    date_add(DATE'2025-01-01', cast(conv(substr(sha2(concat('mat',id),256),1,6),16,10) AS INT) % 3650) AS maturity_date,
    cast((cast(conv(substr(sha2(concat('coup',id),256),1,4),16,10) AS DOUBLE) % 1500) / 10000 + 0.02 AS DECIMAL(10,6)) AS coupon_rate,
    element_at(array('USD','EUR','GBP','JPY','CAD','AUD'), 1 + cast(conv(substr(sha2(concat('curr',id),256),1,4),16,10) AS INT) % 6) AS currency_code,
    concat('ASP_ENT_',lpad(cast(1 + (cast(conv(substr(sha2(concat('issuer',id),256),1,4),16,10) AS INT) % seed_n_entities) AS STRING),4,'0')) AS issuer_source_key,
    concat('US',lpad(cast(cast(conv(substr(sha2(concat('isin',id),256),1,8),16,10) AS BIGINT) % 9999999999 AS STRING),10,'0')) AS isin_code,
    concat(lpad(cast(cast(conv(substr(sha2(concat('cusip',id),256),1,8),16,10) AS BIGINT) % 999999999 AS STRING),9,'0')) AS cusip_code,
    'aspen',
    current_timestamp()
FROM (SELECT explode(sequence(1, seed_n_securities)) AS id)
WHERE NOT skip_aspen;

-- 2.3 raw_aspen.asset_master_raw ----------------------------------------------
TRUNCATE TABLE raw_aspen.asset_master_raw;
INSERT INTO raw_aspen.asset_master_raw
SELECT
    concat('ASP_AST_',lpad(cast(id AS STRING),4,'0')) AS source_key,
    concat('EK_AST_',lpad(cast(id AS STRING),4,'0')) AS enterprise_key,
    concat('Asset_',lpad(cast(id AS STRING),4,'0')) AS asset_name,
    element_at(array('OFFICE','RETAIL','INDUSTRIAL','MULTIFAMILY','HOTEL','INFRA','OTHER'), 1 + cast(conv(substr(sha2(concat('atype',id),256),1,4),16,10) AS INT) % 7) AS asset_type,
    element_at(array('REAL_ESTATE','INFRASTRUCTURE','SPECIALTY'), 1 + cast(conv(substr(sha2(concat('aclass',id),256),1,4),16,10) AS INT) % 3) AS asset_class,
    element_at(array('USA','GBR','DEU','JPN','CAN','AUS'), 1 + cast(conv(substr(sha2(concat('cnty',id),256),1,4),16,10) AS INT) % 6) AS country,
    element_at(array('NA','EU','APAC'), 1 + cast(conv(substr(sha2(concat('reg',id),256),1,4),16,10) AS INT) % 3) AS region,
    2010 + cast(conv(substr(sha2(concat('vint',id),256),1,4),16,10) AS INT) % 14 AS vintage_year,
    cast(50000000 + (cast(conv(substr(sha2(concat('size',id),256),1,8),16,10) AS BIGINT) % 950000000) AS DECIMAL(18,2)) AS total_size_local,
    element_at(array('USD','EUR','GBP','JPY','CAD','AUD'), 1 + cast(conv(substr(sha2(concat('curr',id),256),1,4),16,10) AS INT) % 6) AS currency_code,
    cast((cast(conv(substr(sha2(concat('own',id),256),1,4),16,10) AS DOUBLE) % 100) / 100 AS DECIMAL(10,6)) AS ownership_pct,
    concat('Manager_',lpad(cast(1 + cast(conv(substr(sha2(concat('mgr',id),256),1,4),16,10) AS INT) % 20 AS STRING),3,'0')) AS manager_name,
    element_at(array('OPERATING','DEVELOPING','ACQUIRED','DIVESTED'), 1 + cast(conv(substr(sha2(concat('stat',id),256),1,4),16,10) AS INT) % 4) AS status,
    'aspen',
    current_timestamp()
FROM (SELECT explode(sequence(1, seed_n_assets)) AS id)
WHERE NOT skip_aspen;

-- 2.4 raw_efront.contract_raw -------------------------------------------------
TRUNCATE TABLE raw_efront.contract_raw;
INSERT INTO raw_efront.contract_raw
SELECT
    concat('EF_CT_',lpad(cast(id AS STRING),4,'0')) AS source_key,
    concat('EK_CT_',lpad(cast(id AS STRING),4,'0')) AS enterprise_key,
    concat('Contract_',lpad(cast(id AS STRING),4,'0')) AS contract_name,
    concat('ASP_ENT_',lpad(cast(1 + cast(conv(substr(sha2(concat('cent',id),256),1,4),16,10) AS INT) % seed_n_entities AS STRING),4,'0')) AS entity_source_key,
    element_at(array('TERM_LOAN','REVOLVER','MEZZ','UNITRANCHE','EQUITY_COMMITMENT'), 1 + cast(conv(substr(sha2(concat('ctype',id),256),1,4),16,10) AS INT) % 5) AS contract_type,
    date_add(position_start_date, cast(conv(substr(sha2(concat('sign',id),256),1,4),16,10) AS INT) % datediff(position_end_date, position_start_date)) AS signing_date,
    date_add(position_end_date, 365 * (1 + cast(conv(substr(sha2(concat('cmat',id),256),1,4),16,10) AS INT) % 7)) AS maturity_date,
    cast(5000000 + (cast(conv(substr(sha2(concat('cprin',id),256),1,8),16,10) AS BIGINT) % 95000000) AS DECIMAL(18,2)) AS principal_local,
    element_at(array('USD','EUR','GBP'), 1 + cast(conv(substr(sha2(concat('ccurr',id),256),1,4),16,10) AS INT) % 3) AS currency_code,
    element_at(array('FIXED','FLOATING','PIK'), 1 + cast(conv(substr(sha2(concat('coupt',id),256),1,4),16,10) AS INT) % 3) AS coupon_type,
    cast((cast(conv(substr(sha2(concat('crate',id),256),1,4),16,10) AS DOUBLE) % 800) / 10000 + 0.04 AS DECIMAL(10,6)) AS coupon_rate,
    cast((cast(conv(substr(sha2(concat('cspr',id),256),1,4),16,10) AS DOUBLE) % 600) / 10000 + 0.02 AS DECIMAL(10,6)) AS spread_over_benchmark,
    element_at(array('SOFR','EURIBOR','SONIA'), 1 + cast(conv(substr(sha2(concat('cben',id),256),1,4),16,10) AS INT) % 3) AS benchmark_code,
    element_at(array('ACTIVE','ACTIVE','ACTIVE','ACTIVE','RESTRUCTURED','DEFAULT'), 1 + cast(conv(substr(sha2(concat('cstat',id),256),1,4),16,10) AS INT) % 6) AS status,
    'efront',
    current_timestamp()
FROM (SELECT explode(sequence(1, seed_n_contracts)) AS id)
WHERE NOT skip_efront;

SELECT 'phase 2 (masters) complete' AS status;

-- ============================================================================
-- PHASE 3 — Daily fact tables (positions, transactions, prices, cash, NAV)
-- ============================================================================

-- 3.1 raw_state_street.security_price_raw -------------------------------------
-- Sparse: prices only for first 60% of securities (held subset).
TRUNCATE TABLE raw_state_street.security_price_raw;
INSERT INTO raw_state_street.security_price_raw
SELECT
    concat('SS_PRC_',lpad(cast(sec_id AS STRING),4,'0'),'_',date_format(price_date,'yyyyMMdd')) AS source_key,
    concat('EK_PRC_',lpad(cast(sec_id AS STRING),4,'0'),'_',date_format(price_date,'yyyyMMdd')) AS enterprise_key,
    concat('ASP_SEC_',lpad(cast(sec_id AS STRING),4,'0')) AS security_source_key,
    price_date,
    cast(80 + (cast(conv(substr(sha2(concat('px',sec_id,price_date),256),1,6),16,10) AS DOUBLE) % 4000) / 100 AS DECIMAL(18,6)) AS close_price_local,
    element_at(array('USD','EUR','GBP','JPY','CAD','AUD'), 1 + cast(sec_id AS INT) % 6) AS currency_code,
    'CLOSE' AS price_type,
    'state_street',
    current_timestamp()
FROM (
    SELECT explode(sequence(1, cast(seed_n_securities * 0.6 AS INT))) AS sec_id
) s
CROSS JOIN (
    -- Weekly prices (every 7 days) to keep volume manageable
    SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 7 DAY)) AS price_date
) d
WHERE NOT skip_state_street;

-- 3.2 raw_state_street.position_raw -------------------------------------------
-- Each team holds ~seed_positions_per_team_per_year/365 securities at any given
-- time. We generate monthly snapshots of positions per team to keep volume
-- tractable on Free Edition.
TRUNCATE TABLE raw_state_street.position_raw;
INSERT INTO raw_state_street.position_raw
SELECT
    concat('SS_POS_',team_idx,'_',sec_id,'_',date_format(snap_date,'yyyyMMdd')) AS source_key,
    concat('EK_POS_',team_idx,'_',sec_id,'_',date_format(snap_date,'yyyyMMdd')) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    concat('ASP_SEC_',lpad(cast(sec_id AS STRING),4,'0')) AS security_source_key,
    snap_date AS position_date,
    cast(100 + (cast(conv(substr(sha2(concat('q',team_idx,sec_id,snap_date),256),1,6),16,10) AS DOUBLE) % 9900) AS DECIMAL(18,4)) AS quantity,
    cast(100000 + (cast(conv(substr(sha2(concat('mv',team_idx,sec_id,snap_date),256),1,8),16,10) AS BIGINT) % 9900000) AS DECIMAL(18,2)) AS market_value_local,
    cast(95000 + (cast(conv(substr(sha2(concat('bv',team_idx,sec_id,snap_date),256),1,8),16,10) AS BIGINT) % 9500000) AS DECIMAL(18,2)) AS book_value_local,
    cast(90000 + (cast(conv(substr(sha2(concat('cb',team_idx,sec_id,snap_date),256),1,8),16,10) AS BIGINT) % 9000000) AS DECIMAL(18,2)) AS cost_basis_local,
    cast((cast(conv(substr(sha2(concat('gl',team_idx,sec_id,snap_date),256),1,6),16,10) AS BIGINT) % 200000) - 100000 AS DECIMAL(18,2)) AS unrealized_gl_local,
    cast(80 + (cast(conv(substr(sha2(concat('up',team_idx,sec_id,snap_date),256),1,4),16,10) AS DOUBLE) % 4000) / 100 AS DECIMAL(18,6)) AS unit_price_local,
    element_at(array('USD','EUR','GBP','JPY','CAD','AUD'), 1 + cast(sec_id AS INT) % 6) AS currency_code,
    'SETTLED' AS settlement_status,
    concat('ACCT_',lpad(cast(team_idx AS STRING),2,'0')) AS custodian_account,
    'state_street',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(1, cast(seed_n_securities * 0.4 AS INT))) AS sec_id) s
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS snap_date) d
-- Each team holds a deterministic ~50% subset of the security pool to create
-- partial overlap (cross-team-MV-reuse demo gets meaningful overlap)
WHERE cast(conv(substr(sha2(concat('hold',t.team_idx,s.sec_id),256),1,2),16,10) AS INT) % 2 = 0
  AND NOT skip_state_street
  AND NOT (
        (t.team_idx = 1  AND skip_team_pd_direct_lending)
     OR (t.team_idx = 2  AND skip_team_pd_distressed)
     OR (t.team_idx = 3  AND skip_team_pd_mezzanine)
     OR (t.team_idx = 4  AND skip_team_pd_real_estate_debt)
     OR (t.team_idx = 5  AND skip_team_pd_specialty_finance)
     OR (t.team_idx = 6  AND skip_team_re_core)
     OR (t.team_idx = 7  AND skip_team_re_value_add)
     OR (t.team_idx = 8  AND skip_team_pe_buyout)
     OR (t.team_idx = 9  AND skip_team_infra)
     OR (t.team_idx = 10 AND skip_team_public_equity)
  )
  AND NOT skip_positions;

-- 3.3 raw_state_street.transaction_raw ----------------------------------------
TRUNCATE TABLE raw_state_street.transaction_raw;
INSERT INTO raw_state_street.transaction_raw
SELECT
    concat('SS_TXN_',team_idx,'_',sec_id,'_',txn_seq) AS source_key,
    concat('EK_TXN_',team_idx,'_',sec_id,'_',txn_seq) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    concat('ASP_SEC_',lpad(cast(sec_id AS STRING),4,'0')) AS security_source_key,
    date_add(position_start_date, cast(conv(substr(sha2(concat('td',team_idx,sec_id,txn_seq),256),1,4),16,10) AS INT) % datediff(position_end_date, position_start_date)) AS transaction_date,
    date_add(position_start_date, cast(conv(substr(sha2(concat('td',team_idx,sec_id,txn_seq),256),1,4),16,10) AS INT) % datediff(position_end_date, position_start_date) + 2) AS settlement_date,
    element_at(array('BUY','SELL','BUY','BUY','SELL'), 1 + cast(conv(substr(sha2(concat('tt',team_idx,sec_id,txn_seq),256),1,4),16,10) AS INT) % 5) AS transaction_type,
    cast(100 + (cast(conv(substr(sha2(concat('tq',team_idx,sec_id,txn_seq),256),1,6),16,10) AS DOUBLE) % 4900) AS DECIMAL(18,4)) AS quantity,
    cast(80 + (cast(conv(substr(sha2(concat('tp',team_idx,sec_id,txn_seq),256),1,4),16,10) AS DOUBLE) % 4000) / 100 AS DECIMAL(18,4)) AS price_local,
    cast(50000 + (cast(conv(substr(sha2(concat('gx',team_idx,sec_id,txn_seq),256),1,8),16,10) AS BIGINT) % 4500000) AS DECIMAL(18,2)) AS gross_amount_local,
    cast(100 + (cast(conv(substr(sha2(concat('fe',team_idx,sec_id,txn_seq),256),1,4),16,10) AS BIGINT) % 9900) AS DECIMAL(18,2)) AS fees_local,
    cast(50000 + (cast(conv(substr(sha2(concat('na',team_idx,sec_id,txn_seq),256),1,8),16,10) AS BIGINT) % 4500000) AS DECIMAL(18,2)) AS net_amount_local,
    element_at(array('USD','EUR','GBP','JPY','CAD','AUD'), 1 + cast(sec_id AS INT) % 6) AS currency_code,
    element_at(array('Goldman Sachs','Morgan Stanley','JP Morgan','Citi','Barclays','Deutsche'), 1 + cast(conv(substr(sha2(concat('cp',team_idx,sec_id,txn_seq),256),1,4),16,10) AS INT) % 6) AS counterparty_name,
    concat('ACCT_',lpad(cast(team_idx AS STRING),2,'0')) AS custodian_account,
    'state_street',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(1, cast(seed_n_securities * 0.4 AS INT))) AS sec_id) s
CROSS JOIN (SELECT explode(sequence(1, seed_txns_per_security_per_year * cast(year(position_end_date) - year(position_start_date) + 1 AS INT))) AS txn_seq) x
WHERE cast(conv(substr(sha2(concat('hold',t.team_idx,s.sec_id),256),1,2),16,10) AS INT) % 2 = 0
  AND NOT skip_state_street AND NOT skip_transactions;

-- 3.4 raw_state_street.cash_flow_raw ------------------------------------------
TRUNCATE TABLE raw_state_street.cash_flow_raw;
INSERT INTO raw_state_street.cash_flow_raw
SELECT
    concat('SS_CF_',team_idx,'_',date_format(cf_date,'yyyyMMdd'),'_',cf_seq) AS source_key,
    concat('EK_CF_',team_idx,'_',date_format(cf_date,'yyyyMMdd'),'_',cf_seq) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    cf_date,
    element_at(array('INCOME','EXPENSE','CONTRIBUTION','DISTRIBUTION','FEE'), 1 + cast(conv(substr(sha2(concat('cft',team_idx,cf_date,cf_seq),256),1,4),16,10) AS INT) % 5) AS cash_flow_type,
    cast((cast(conv(substr(sha2(concat('cfa',team_idx,cf_date,cf_seq),256),1,8),16,10) AS BIGINT) % 1000000) - 500000 AS DECIMAL(18,2)) AS amount_local,
    'USD' AS currency_code,
    element_at(array('Bank of America','Wells Fargo','HSBC','BNP Paribas'), 1 + cast(conv(substr(sha2(concat('cfcp',team_idx,cf_date,cf_seq),256),1,4),16,10) AS INT) % 4) AS counterparty_name,
    'state_street',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS cf_date) d
CROSS JOIN (SELECT explode(sequence(1, 3)) AS cf_seq) c
WHERE NOT skip_state_street;

-- 3.5 raw_state_street.nav_raw ------------------------------------------------
TRUNCATE TABLE raw_state_street.nav_raw;
INSERT INTO raw_state_street.nav_raw
SELECT
    concat('SS_NAV_',team_idx,'_',date_format(nav_date,'yyyyMMdd')) AS source_key,
    concat('EK_NAV_',team_idx,'_',date_format(nav_date,'yyyyMMdd')) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    nav_date,
    cast(100000000 + (cast(conv(substr(sha2(concat('nv',team_idx,nav_date),256),1,8),16,10) AS BIGINT) % 900000000) AS DECIMAL(18,2)) AS nav_local,
    'USD' AS currency_code,
    cast(110000000 + (cast(conv(substr(sha2(concat('ga',team_idx,nav_date),256),1,8),16,10) AS BIGINT) % 990000000) AS DECIMAL(18,2)) AS gross_assets_local,
    cast(100000000 + (cast(conv(substr(sha2(concat('na',team_idx,nav_date),256),1,8),16,10) AS BIGINT) % 900000000) AS DECIMAL(18,2)) AS net_assets_local,
    cast(1000000 + (cast(conv(substr(sha2(concat('tu',team_idx,nav_date),256),1,6),16,10) AS DOUBLE) % 9000000) AS DECIMAL(18,4)) AS total_units,
    'state_street',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS nav_date) d
WHERE NOT skip_state_street;

SELECT 'phase 3 (daily facts) complete' AS status;

-- ============================================================================
-- PHASE 4 — Periodic / event tables
-- ============================================================================

-- 4.1 raw_aladdin.portfolio_risk_raw ------------------------------------------
TRUNCATE TABLE raw_aladdin.portfolio_risk_raw;
INSERT INTO raw_aladdin.portfolio_risk_raw
SELECT
    concat('AL_RISK_',team_idx,'_',date_format(risk_date,'yyyyMMdd')) AS source_key,
    concat('EK_RISK_',team_idx,'_',date_format(risk_date,'yyyyMMdd')) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    risk_date,
    cast((cast(conv(substr(sha2(concat('v95',team_idx,risk_date),256),1,4),16,10) AS DOUBLE) % 500) / 10000 AS DECIMAL(18,6)) AS var_95,
    cast((cast(conv(substr(sha2(concat('v99',team_idx,risk_date),256),1,4),16,10) AS DOUBLE) % 800) / 10000 AS DECIMAL(18,6)) AS var_99,
    cast((cast(conv(substr(sha2(concat('es',team_idx,risk_date),256),1,4),16,10) AS DOUBLE) % 700) / 10000 AS DECIMAL(18,6)) AS expected_shortfall,
    cast(0.7 + (cast(conv(substr(sha2(concat('be',team_idx,risk_date),256),1,4),16,10) AS DOUBLE) % 80) / 100 AS DECIMAL(8,4)) AS beta,
    cast((cast(conv(substr(sha2(concat('te',team_idx,risk_date),256),1,4),16,10) AS DOUBLE) % 400) / 10000 AS DECIMAL(8,4)) AS tracking_error,
    'USD' AS risk_currency,
    concat('Portfolio_Team_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_name,
    element_at(array('Direct Lending','Distressed','Mezzanine','RE Debt','Specialty','Core RE','Value Add RE','Buyout','Infrastructure','Public Equity'), team_idx) AS strategy_name,
    'aladdin',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS risk_date) d
WHERE NOT skip_aladdin;

-- 4.2 raw_aladdin.portfolio_performance_raw -----------------------------------
TRUNCATE TABLE raw_aladdin.portfolio_performance_raw;
INSERT INTO raw_aladdin.portfolio_performance_raw
SELECT
    concat('AL_PERF_',team_idx,'_',date_format(perf_date,'yyyyMMdd')) AS source_key,
    concat('EK_PERF_',team_idx,'_',date_format(perf_date,'yyyyMMdd')) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    perf_date,
    cast(((cast(conv(substr(sha2(concat('p',team_idx,perf_date),256),1,4),16,10) AS DOUBLE) % 1000) - 200) / 10000 AS DECIMAL(10,6)) AS period_return_pct,
    cast(((cast(conv(substr(sha2(concat('y',team_idx,perf_date),256),1,4),16,10) AS DOUBLE) % 2000) - 400) / 10000 AS DECIMAL(10,6)) AS ytd_return_pct,
    cast(((cast(conv(substr(sha2(concat('si',team_idx,perf_date),256),1,4),16,10) AS DOUBLE) % 4000) + 500) / 10000 AS DECIMAL(10,6)) AS since_inception_return_pct,
    cast(((cast(conv(substr(sha2(concat('bm',team_idx,perf_date),256),1,4),16,10) AS DOUBLE) % 1500) - 300) / 10000 AS DECIMAL(10,6)) AS benchmark_return_pct,
    'CAMBRIDGE_PD' AS benchmark_code,
    'aladdin',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS perf_date) d
WHERE NOT skip_aladdin;

-- 4.3 raw_aladdin.compliance_check_raw ----------------------------------------
TRUNCATE TABLE raw_aladdin.compliance_check_raw;
INSERT INTO raw_aladdin.compliance_check_raw
SELECT
    concat('AL_CC_',team_idx,'_',date_format(check_date,'yyyyMMdd'),'_',rule_seq) AS source_key,
    concat('EK_CC_',team_idx,'_',date_format(check_date,'yyyyMMdd'),'_',rule_seq) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    check_date,
    concat('RULE_',lpad(cast(rule_seq AS STRING),3,'0')) AS rule_code,
    element_at(array('Concentration Limit','Sector Cap','Currency Hedge','Leverage','Liquidity'), 1 + ((rule_seq - 1) % 5)) AS rule_name,
    element_at(array('PASS','PASS','PASS','PASS','WARN','BREACH'), 1 + cast(conv(substr(sha2(concat('rs',team_idx,check_date,rule_seq),256),1,4),16,10) AS INT) % 6) AS rule_status,
    cast((cast(conv(substr(sha2(concat('ba',team_idx,check_date,rule_seq),256),1,8),16,10) AS BIGINT) % 1000000) AS DECIMAL(18,2)) AS breach_amount,
    cast((cast(conv(substr(sha2(concat('bp',team_idx,check_date,rule_seq),256),1,4),16,10) AS DOUBLE) % 500) / 10000 AS DECIMAL(10,6)) AS breach_pct,
    concat('RISK_TEAM_',lpad(cast(((rule_seq - 1) % 3) + 1 AS STRING),2,'0')) AS risk_team_code,
    'aladdin',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS check_date) d
CROSS JOIN (SELECT explode(sequence(1, 5)) AS rule_seq) r
WHERE NOT skip_aladdin;

-- 4.4 raw_aladdin.trade_blotter_raw -------------------------------------------
TRUNCATE TABLE raw_aladdin.trade_blotter_raw;
INSERT INTO raw_aladdin.trade_blotter_raw
SELECT
    concat('AL_TB_',team_idx,'_',sec_id,'_',trade_seq) AS source_key,
    concat('EK_TB_',team_idx,'_',sec_id,'_',trade_seq) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    concat('ASP_SEC_',lpad(cast(sec_id AS STRING),4,'0')) AS security_source_key,
    date_add(position_start_date, cast(conv(substr(sha2(concat('tbd',team_idx,sec_id,trade_seq),256),1,4),16,10) AS INT) % datediff(position_end_date, position_start_date)) AS trade_date,
    element_at(array('PENDING','EXECUTED','SETTLED','SETTLED','SETTLED','CANCELLED'), 1 + cast(conv(substr(sha2(concat('tbs',team_idx,sec_id,trade_seq),256),1,4),16,10) AS INT) % 6) AS trade_status,
    cast(100 + (cast(conv(substr(sha2(concat('tbq',team_idx,sec_id,trade_seq),256),1,6),16,10) AS DOUBLE) % 4900) AS DECIMAL(18,4)) AS quantity,
    cast(80 + (cast(conv(substr(sha2(concat('tbp',team_idx,sec_id,trade_seq),256),1,4),16,10) AS DOUBLE) % 4000) / 100 AS DECIMAL(18,4)) AS limit_price,
    element_at(array('BUY','SELL'), 1 + cast(conv(substr(sha2(concat('tbsi',team_idx,sec_id,trade_seq),256),1,4),16,10) AS INT) % 2) AS side,
    concat('TRADER_',lpad(cast(1 + cast(conv(substr(sha2(concat('tbtr',team_idx,sec_id,trade_seq),256),1,4),16,10) AS INT) % 12 AS STRING),3,'0')) AS trader_id,
    'USD' AS currency_code,
    'aladdin',
    current_timestamp()
FROM (SELECT explode(sequence(1, 10)) AS team_idx) t
CROSS JOIN (SELECT explode(sequence(1, cast(seed_n_securities * 0.2 AS INT))) AS sec_id) s
CROSS JOIN (SELECT explode(sequence(1, 4)) AS trade_seq) x
WHERE NOT skip_aladdin;

-- 4.5 raw_efront.contract_summary_raw -----------------------------------------
TRUNCATE TABLE raw_efront.contract_summary_raw;
INSERT INTO raw_efront.contract_summary_raw
SELECT
    concat('EF_CS_',c.source_key,'_',date_format(summary_date,'yyyyMMdd')) AS source_key,
    concat('EK_CS_',c.enterprise_key,'_',date_format(summary_date,'yyyyMMdd')) AS enterprise_key,
    c.source_key AS contract_source_key,
    summary_date,
    cast(c.principal_local * (1 - cast(conv(substr(sha2(concat('osp',c.source_key,summary_date),256),1,4),16,10) AS DOUBLE) % 50 / 100) AS DECIMAL(18,2)) AS outstanding_principal_local,
    cast(c.principal_local * cast(conv(substr(sha2(concat('ai',c.source_key,summary_date),256),1,4),16,10) AS DOUBLE) % 5 / 100 AS DECIMAL(18,2)) AS accrued_interest_local,
    cast(c.principal_local * cast(conv(substr(sha2(concat('ptd',c.source_key,summary_date),256),1,4),16,10) AS DOUBLE) % 30 / 100 AS DECIMAL(18,2)) AS paid_to_date_local,
    c.currency_code,
    element_at(array('CURRENT','CURRENT','CURRENT','WATCH','NON_ACCRUAL','IMPAIRED'), 1 + cast(conv(substr(sha2(concat('ps',c.source_key,summary_date),256),1,4),16,10) AS INT) % 6) AS performance_status,
    'efront',
    current_timestamp()
FROM raw_efront.contract_raw c
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS summary_date) d
WHERE NOT skip_efront AND d.summary_date >= c.signing_date;

-- 4.6 raw_efront.contract_covenant_raw ----------------------------------------
TRUNCATE TABLE raw_efront.contract_covenant_raw;
INSERT INTO raw_efront.contract_covenant_raw
SELECT
    concat('EF_CV_',c.source_key,'_',date_format(covenant_date,'yyyyMMdd'),'_',cov_type) AS source_key,
    concat('EK_CV_',c.enterprise_key,'_',date_format(covenant_date,'yyyyMMdd'),'_',cov_type) AS enterprise_key,
    c.source_key AS contract_source_key,
    covenant_date,
    cov_type AS covenant_type,
    cast((cast(conv(substr(sha2(concat('cth',c.source_key,covenant_date,cov_type),256),1,4),16,10) AS DOUBLE) % 500) / 100 AS DECIMAL(18,6)) AS covenant_threshold,
    cast((cast(conv(substr(sha2(concat('cac',c.source_key,covenant_date,cov_type),256),1,4),16,10) AS DOUBLE) % 600) / 100 AS DECIMAL(18,6)) AS covenant_actual,
    element_at(array('PASS','PASS','PASS','WATCH','TRIPPED','WAIVED'), 1 + cast(conv(substr(sha2(concat('cst',c.source_key,covenant_date,cov_type),256),1,4),16,10) AS INT) % 6) AS covenant_status,
    element_at(array('NONE','NONE','NONE','SOFT','HARD'), 1 + cast(conv(substr(sha2(concat('csv',c.source_key,covenant_date,cov_type),256),1,4),16,10) AS INT) % 5) AS breach_severity,
    'efront',
    current_timestamp()
FROM raw_efront.contract_raw c
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 3 MONTH)) AS covenant_date) d
CROSS JOIN (SELECT explode(array('LEVERAGE','DSCR','INTEREST_COVERAGE','LTV')) AS cov_type) ct
WHERE NOT skip_efront AND d.covenant_date >= c.signing_date;

-- 4.7 raw_efront.capital_activity_raw -----------------------------------------
TRUNCATE TABLE raw_efront.capital_activity_raw;
INSERT INTO raw_efront.capital_activity_raw
SELECT
    concat('EF_CA_',team_idx,'_',date_format(activity_date,'yyyyMMdd'),'_',ca_seq) AS source_key,
    concat('EK_CA_',team_idx,'_',date_format(activity_date,'yyyyMMdd'),'_',ca_seq) AS enterprise_key,
    concat('SS_PORT_TEAM_',lpad(cast(team_idx AS STRING),2,'0')) AS portfolio_source_key,
    concat('ASP_ENT_',lpad(cast(1 + cast(conv(substr(sha2(concat('cae',team_idx,activity_date,ca_seq),256),1,4),16,10) AS INT) % seed_n_entities AS STRING),4,'0')) AS entity_source_key,
    activity_date,
    element_at(array('CAPITAL_CALL','DISTRIBUTION','FEE','EXPENSE','RECALL'), 1 + cast(conv(substr(sha2(concat('cat',team_idx,activity_date,ca_seq),256),1,4),16,10) AS INT) % 5) AS activity_type,
    cast(100000 + (cast(conv(substr(sha2(concat('caa',team_idx,activity_date,ca_seq),256),1,8),16,10) AS BIGINT) % 9900000) AS DECIMAL(18,2)) AS amount_local,
    'USD' AS currency_code,
    concat('LP_',lpad(cast(1 + cast(conv(substr(sha2(concat('lp',team_idx,activity_date,ca_seq),256),1,4),16,10) AS INT) % 30 AS STRING),3,'0')) AS lp_id_string,
    concat('GP_',lpad(cast(team_idx AS STRING),2,'0')) AS gp_id_string,
    'efront',
    current_timestamp()
FROM (SELECT explode(sequence(1, 5)) AS team_idx) t  -- PD teams only
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 1 MONTH)) AS activity_date) d
CROSS JOIN (SELECT explode(sequence(1, 2)) AS ca_seq) c
WHERE NOT skip_efront;

-- 4.8 raw_efront.collateral_exposure_raw + collateral_position_raw ------------
TRUNCATE TABLE raw_efront.collateral_exposure_raw;
INSERT INTO raw_efront.collateral_exposure_raw
SELECT
    concat('EF_CX_',c.source_key,'_',date_format(exposure_date,'yyyyMMdd')) AS source_key,
    concat('EK_CX_',c.enterprise_key,'_',date_format(exposure_date,'yyyyMMdd')) AS enterprise_key,
    c.source_key AS contract_source_key,
    exposure_date,
    cast(c.principal_local * 0.85 AS DECIMAL(18,2)) AS exposure_amount_local,
    c.currency_code,
    element_at(array('REAL_ESTATE','EQUIPMENT','RECEIVABLES','SECURITIES'), 1 + cast(conv(substr(sha2(concat('cxt',c.source_key,exposure_date),256),1,4),16,10) AS INT) % 4) AS collateral_type,
    cast(c.principal_local * (0.7 + cast(conv(substr(sha2(concat('cxv',c.source_key,exposure_date),256),1,4),16,10) AS DOUBLE) % 50 / 100) AS DECIMAL(18,2)) AS collateral_value_local,
    cast(0.5 + cast(conv(substr(sha2(concat('cxl',c.source_key,exposure_date),256),1,4),16,10) AS DOUBLE) % 40 / 100 AS DECIMAL(10,6)) AS ltv_pct,
    'efront',
    current_timestamp()
FROM raw_efront.contract_raw c
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 3 MONTH)) AS exposure_date) d
WHERE NOT skip_efront AND d.exposure_date >= c.signing_date;

-- sec_idx pre-computed in CTE; deriving it via correlated CROSS JOIN
-- subquery would require LATERAL syntax (dialect-fragile). One sec_idx
-- per contract, deterministic from contract source_key.
TRUNCATE TABLE raw_efront.collateral_position_raw;
INSERT INTO raw_efront.collateral_position_raw
WITH contract_with_sec AS (
    SELECT
        c.source_key,
        c.enterprise_key,
        c.principal_local,
        c.currency_code,
        c.signing_date,
        1 + cast(conv(substr(sha2(c.source_key,256),1,4),16,10) AS INT) % seed_n_securities AS sec_idx
    FROM raw_efront.contract_raw c
)
SELECT
    concat('EF_CP_',cs.source_key,'_',date_format(position_date,'yyyyMMdd'),'_',cs.sec_idx) AS source_key,
    concat('EK_CP_',cs.enterprise_key,'_',date_format(position_date,'yyyyMMdd'),'_',cs.sec_idx) AS enterprise_key,
    cs.source_key AS contract_source_key,
    concat('ASP_SEC_',lpad(cast(cs.sec_idx AS STRING),4,'0')) AS security_source_key,
    CAST(NULL AS STRING) AS asset_source_key,
    position_date,
    cast(cs.principal_local * 0.3 AS DECIMAL(18,2)) AS position_value_local,
    cs.currency_code,
    element_at(array('PRIMARY','SUPPORTING','CROSS_COLLATERAL'), 1 + cast(conv(substr(sha2(concat('cpr',cs.source_key,position_date,cs.sec_idx),256),1,4),16,10) AS INT) % 3) AS collateral_role,
    'efront' AS record_source,
    current_timestamp() AS loaded_at
FROM contract_with_sec cs
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 6 MONTH)) AS position_date) d
WHERE NOT skip_efront AND d.position_date >= cs.signing_date;

SELECT 'phase 4 (periodic events) complete' AS status;

-- ============================================================================
-- PHASE 5 — Ratings
-- ============================================================================

TRUNCATE TABLE raw_aspen.entity_rating_raw;
INSERT INTO raw_aspen.entity_rating_raw
SELECT
    concat('ASP_ER_',e.source_key,'_',date_format(rating_date,'yyyyMMdd')) AS source_key,
    concat('EK_ER_',e.enterprise_key,'_',date_format(rating_date,'yyyyMMdd')) AS enterprise_key,
    e.source_key AS entity_source_key,
    rating_date,
    element_at(array('MOODY','SP','FITCH'), 1 + cast(conv(substr(sha2(concat('era',e.source_key,rating_date),256),1,4),16,10) AS INT) % 3) AS rating_agency,
    element_at(array('AAA','AA','A','BBB','BB','B','CCC'), 1 + cast(conv(substr(sha2(concat('erv',e.source_key,rating_date),256),1,4),16,10) AS INT) % 7) AS rating_value,
    element_at(array('STABLE','POSITIVE','NEGATIVE','WATCH'), 1 + cast(conv(substr(sha2(concat('ero',e.source_key,rating_date),256),1,4),16,10) AS INT) % 4) AS rating_outlook,
    element_at(array('AFFIRM','UPGRADE','DOWNGRADE','INITIAL'), 1 + cast(conv(substr(sha2(concat('eraa',e.source_key,rating_date),256),1,4),16,10) AS INT) % 4) AS rating_action_type,
    'aspen',
    current_timestamp()
FROM raw_aspen.entity_master_raw e
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 6 MONTH)) AS rating_date) d
WHERE NOT skip_aspen AND e.formation_date <= d.rating_date;

TRUNCATE TABLE raw_aspen.security_rating_raw;
INSERT INTO raw_aspen.security_rating_raw
SELECT
    concat('ASP_SR_',s.source_key,'_',date_format(rating_date,'yyyyMMdd')) AS source_key,
    concat('EK_SR_',s.enterprise_key,'_',date_format(rating_date,'yyyyMMdd')) AS enterprise_key,
    s.source_key AS security_source_key,
    rating_date,
    element_at(array('MOODY','SP','FITCH'), 1 + cast(conv(substr(sha2(concat('sra',s.source_key,rating_date),256),1,4),16,10) AS INT) % 3) AS rating_agency,
    element_at(array('AAA','AA','A','BBB','BB','B'), 1 + cast(conv(substr(sha2(concat('srv',s.source_key,rating_date),256),1,4),16,10) AS INT) % 6) AS rating_value,
    element_at(array('STABLE','POSITIVE','NEGATIVE'), 1 + cast(conv(substr(sha2(concat('sro',s.source_key,rating_date),256),1,4),16,10) AS INT) % 3) AS rating_outlook,
    'AFFIRM' AS rating_action_type,
    'aspen',
    current_timestamp()
FROM raw_aspen.security_master_raw s
CROSS JOIN (SELECT explode(sequence(position_start_date, position_end_date, INTERVAL 6 MONTH)) AS rating_date) d
WHERE NOT skip_aspen AND s.issue_date <= d.rating_date;

SELECT 'phase 5 (ratings) complete' AS status;

-- ============================================================================
-- PHASE 6 — SCD2 history events (corrections / restatements)
-- Insert successor entity/security/contract rows that bronze and silver will
-- detect as supersession events. Keeps the SCD2-everywhere demo realistic.
-- ============================================================================

-- 6.1 Entity restructurings: insert a "v2" row for the first
-- history_entity_restructurings entities, with a name change + later
-- formation_date. Bronze precedence will keep both rows; silver SCD2 will
-- chain them via enterprise_key.
INSERT INTO raw_aspen.entity_master_raw
SELECT
    concat(e.source_key,'_v2') AS source_key,
    e.enterprise_key,  -- same enterprise key signals a supersession
    concat(e.entity_name,' (Restructured)') AS entity_name,
    e.entity_type, e.legal_structure, e.jurisdiction, e.tax_id,
    date_add(e.formation_date, 365 + cast(conv(substr(sha2(e.source_key,256),1,4),16,10) AS INT) % 365 * 5) AS formation_date,
    NULL AS dissolution_date,
    NULL AS parent_entity_source_key,
    TRUE AS is_active,
    e.address_line, e.city, e.state_region, e.country,
    'aspen', current_timestamp()
FROM (
    SELECT * FROM raw_aspen.entity_master_raw
    WHERE simulate_history AND NOT skip_aspen
    ORDER BY source_key
    LIMIT 25  -- history_entity_restructurings literal; SQL Scripting wants compile-time
) e;

-- 6.2 Entity soft-deletes: dissolution_date set on 5 entities.
UPDATE raw_aspen.entity_master_raw
SET dissolution_date = date_add(formation_date, 365 * 8),
    is_active = FALSE
WHERE simulate_history
  AND source_key IN (
      SELECT source_key FROM raw_aspen.entity_master_raw
      WHERE source_key NOT LIKE '%_v2'
      ORDER BY source_key DESC
      LIMIT 5
  );

-- 6.3 Security renames: insert v2 row.
INSERT INTO raw_aspen.security_master_raw
SELECT
    concat(s.source_key,'_v2') AS source_key,
    s.enterprise_key,
    concat(s.security_name,' (Reissued)') AS security_name,
    s.security_type, s.asset_class, s.sub_asset_class,
    date_add(s.issue_date, 365 * 2) AS issue_date,
    s.maturity_date, s.coupon_rate, s.currency_code, s.issuer_source_key, s.isin_code, s.cusip_code,
    'aspen', current_timestamp()
FROM (
    SELECT * FROM raw_aspen.security_master_raw
    WHERE simulate_history AND NOT skip_aspen
    ORDER BY source_key
    LIMIT 10
) s;

-- 6.4 Contract amendments.
INSERT INTO raw_efront.contract_raw
SELECT
    concat(c.source_key,'_v2') AS source_key,
    c.enterprise_key,
    concat(c.contract_name,' (Amended)') AS contract_name,
    c.entity_source_key, c.contract_type,
    date_add(c.signing_date, 365) AS signing_date,
    date_add(c.maturity_date, 365 * 2) AS maturity_date,
    cast(c.principal_local * 1.5 AS DECIMAL(18,2)) AS principal_local,
    c.currency_code, c.coupon_type,
    cast(c.coupon_rate * 0.95 AS DECIMAL(10,6)) AS coupon_rate,
    c.spread_over_benchmark, c.benchmark_code,
    'RESTRUCTURED' AS status,
    'efront', current_timestamp()
FROM (
    SELECT * FROM raw_efront.contract_raw
    WHERE simulate_history AND NOT skip_efront
    ORDER BY source_key
    LIMIT 15
) c;

-- 6.5 Crosswalk supersessions: insert duplicate (source_key, new enterprise_key)
-- pairs in raw_state_street.position_raw to simulate enterprise_key reassignment.
INSERT INTO raw_state_street.position_raw
SELECT
    p.source_key,
    concat('REMAPPED_',p.enterprise_key) AS enterprise_key,
    p.portfolio_source_key, p.security_source_key,
    date_add(p.position_date, 1) AS position_date,
    p.quantity, p.market_value_local, p.book_value_local, p.cost_basis_local,
    p.unrealized_gl_local, p.unit_price_local, p.currency_code, p.settlement_status,
    p.custodian_account, p.record_source, current_timestamp()
FROM (
    SELECT * FROM raw_state_street.position_raw
    WHERE simulate_history AND NOT skip_positions
    ORDER BY source_key
    LIMIT 20
) p;

SELECT 'phase 6 (SCD2 history events) complete' AS status;

-- ============================================================================
-- SEED COMPLETE
-- ============================================================================

SELECT 'pre_bronze.seed COMPLETE' AS status,
       (SELECT count(*) FROM raw_state_street.position_raw)        AS positions,
       (SELECT count(*) FROM raw_state_street.transaction_raw)     AS transactions,
       (SELECT count(*) FROM raw_aspen.entity_master_raw)          AS entities,
       (SELECT count(*) FROM raw_aspen.security_master_raw)        AS securities,
       (SELECT count(*) FROM raw_efront.contract_raw)              AS contracts,
       (SELECT count(*) FROM raw_bloomberg.fx_rate_raw)            AS fx_rates,
       (SELECT count(*) FROM raw_internal_admin.business_unit_master_raw) AS business_units;
