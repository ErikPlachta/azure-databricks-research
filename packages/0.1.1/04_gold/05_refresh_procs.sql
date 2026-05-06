-- ============================================================================
-- 04_gold/05_refresh_procs.sql
-- Per-entity refresh procedures for the 5 PD-team gold schemas + the
-- gold_pd_consolidated schema. Pattern matches 02_bronze/06_refresh_procs.sql:
-- INSERT OVERWRITE t_<entity> SELECT * FROM v<entity>; per-team aggregator
-- chains them; orchestrator calls each team's aggregator in any order, then
-- consolidated last.
--
-- Ordering note: within a team, ordering doesn't affect correctness because
-- each proc runs `SELECT * FROM v<entity>` — and views always query upstream
-- views/tables fresh, never the team's own t_ tables. The dependency-ordered
-- listing below is for readability + to match enterprise conventions.
--
-- Operational profile: slow path (DECISIONS.md #5). Each proc cascades
-- through the full view stack (gold v* → silver v* → bronze v* → raw).
-- Demonstrates "what production reality looks like without MVs."
--
-- Idempotent. Safe to re-run.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ============================================================================
-- TEAM_PD_DIRECT_LENDING (10 entity procs + 1 aggregator)
-- ============================================================================

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vsecurity_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vsecurity_dim
    SELECT * FROM team_pd_direct_lending.vsecurity_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vsecurity_rating_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vsecurity_rating_dim
    SELECT * FROM team_pd_direct_lending.vsecurity_rating_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vposition_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vposition_analytics_fact
    SELECT * FROM team_pd_direct_lending.vposition_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vportfolio_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vportfolio_analytics_fact
    SELECT * FROM team_pd_direct_lending.vportfolio_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vcontract_details_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vcontract_details_fact
    SELECT * FROM team_pd_direct_lending.vcontract_details_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vcontract_summary_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vcontract_summary_fact
    SELECT * FROM team_pd_direct_lending.vcontract_summary_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vsecurity_master_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vsecurity_master_fact
    SELECT * FROM team_pd_direct_lending.vsecurity_master_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vsecurity_price_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vsecurity_price_fact
    SELECT * FROM team_pd_direct_lending.vsecurity_price_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vtransactions_collateral_exposure_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vtransactions_collateral_exposure_fact
    SELECT * FROM team_pd_direct_lending.vtransactions_collateral_exposure_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_vtransactions_collateral_positions_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_direct_lending.t_vtransactions_collateral_positions_fact
    SELECT * FROM team_pd_direct_lending.vtransactions_collateral_positions_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_direct_lending.refresh_all()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    CALL team_pd_direct_lending.refresh_vsecurity_dim();
    CALL team_pd_direct_lending.refresh_vsecurity_rating_dim();
    CALL team_pd_direct_lending.refresh_vposition_analytics_fact();
    CALL team_pd_direct_lending.refresh_vportfolio_analytics_fact();
    CALL team_pd_direct_lending.refresh_vcontract_details_fact();
    CALL team_pd_direct_lending.refresh_vcontract_summary_fact();
    CALL team_pd_direct_lending.refresh_vsecurity_master_fact();
    CALL team_pd_direct_lending.refresh_vsecurity_price_fact();
    CALL team_pd_direct_lending.refresh_vtransactions_collateral_exposure_fact();
    CALL team_pd_direct_lending.refresh_vtransactions_collateral_positions_fact();
END;

-- ============================================================================
-- TEAM_PD_DISTRESSED (10 entity procs + 1 aggregator)
-- ============================================================================

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vsecurity_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vsecurity_dim
    SELECT * FROM team_pd_distressed.vsecurity_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vsecurity_rating_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vsecurity_rating_dim
    SELECT * FROM team_pd_distressed.vsecurity_rating_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vposition_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vposition_analytics_fact
    SELECT * FROM team_pd_distressed.vposition_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vportfolio_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vportfolio_analytics_fact
    SELECT * FROM team_pd_distressed.vportfolio_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vcontract_details_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vcontract_details_fact
    SELECT * FROM team_pd_distressed.vcontract_details_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vcontract_summary_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vcontract_summary_fact
    SELECT * FROM team_pd_distressed.vcontract_summary_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vsecurity_master_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vsecurity_master_fact
    SELECT * FROM team_pd_distressed.vsecurity_master_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vsecurity_price_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vsecurity_price_fact
    SELECT * FROM team_pd_distressed.vsecurity_price_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vtransactions_collateral_exposure_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vtransactions_collateral_exposure_fact
    SELECT * FROM team_pd_distressed.vtransactions_collateral_exposure_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_vtransactions_collateral_positions_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_distressed.t_vtransactions_collateral_positions_fact
    SELECT * FROM team_pd_distressed.vtransactions_collateral_positions_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_distressed.refresh_all()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    CALL team_pd_distressed.refresh_vsecurity_dim();
    CALL team_pd_distressed.refresh_vsecurity_rating_dim();
    CALL team_pd_distressed.refresh_vposition_analytics_fact();
    CALL team_pd_distressed.refresh_vportfolio_analytics_fact();
    CALL team_pd_distressed.refresh_vcontract_details_fact();
    CALL team_pd_distressed.refresh_vcontract_summary_fact();
    CALL team_pd_distressed.refresh_vsecurity_master_fact();
    CALL team_pd_distressed.refresh_vsecurity_price_fact();
    CALL team_pd_distressed.refresh_vtransactions_collateral_exposure_fact();
    CALL team_pd_distressed.refresh_vtransactions_collateral_positions_fact();
END;

-- ============================================================================
-- TEAM_PD_MEZZANINE (10 entity procs + 1 aggregator)
-- ============================================================================

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vsecurity_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vsecurity_dim
    SELECT * FROM team_pd_mezzanine.vsecurity_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vsecurity_rating_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vsecurity_rating_dim
    SELECT * FROM team_pd_mezzanine.vsecurity_rating_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vposition_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vposition_analytics_fact
    SELECT * FROM team_pd_mezzanine.vposition_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vportfolio_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vportfolio_analytics_fact
    SELECT * FROM team_pd_mezzanine.vportfolio_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vcontract_details_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vcontract_details_fact
    SELECT * FROM team_pd_mezzanine.vcontract_details_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vcontract_summary_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vcontract_summary_fact
    SELECT * FROM team_pd_mezzanine.vcontract_summary_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vsecurity_master_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vsecurity_master_fact
    SELECT * FROM team_pd_mezzanine.vsecurity_master_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vsecurity_price_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vsecurity_price_fact
    SELECT * FROM team_pd_mezzanine.vsecurity_price_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vtransactions_collateral_exposure_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vtransactions_collateral_exposure_fact
    SELECT * FROM team_pd_mezzanine.vtransactions_collateral_exposure_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_vtransactions_collateral_positions_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_mezzanine.t_vtransactions_collateral_positions_fact
    SELECT * FROM team_pd_mezzanine.vtransactions_collateral_positions_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_mezzanine.refresh_all()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    CALL team_pd_mezzanine.refresh_vsecurity_dim();
    CALL team_pd_mezzanine.refresh_vsecurity_rating_dim();
    CALL team_pd_mezzanine.refresh_vposition_analytics_fact();
    CALL team_pd_mezzanine.refresh_vportfolio_analytics_fact();
    CALL team_pd_mezzanine.refresh_vcontract_details_fact();
    CALL team_pd_mezzanine.refresh_vcontract_summary_fact();
    CALL team_pd_mezzanine.refresh_vsecurity_master_fact();
    CALL team_pd_mezzanine.refresh_vsecurity_price_fact();
    CALL team_pd_mezzanine.refresh_vtransactions_collateral_exposure_fact();
    CALL team_pd_mezzanine.refresh_vtransactions_collateral_positions_fact();
END;

-- ============================================================================
-- TEAM_PD_REAL_ESTATE_DEBT (10 entity procs + 1 aggregator)
-- ============================================================================

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vsecurity_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vsecurity_dim
    SELECT * FROM team_pd_real_estate_debt.vsecurity_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vsecurity_rating_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vsecurity_rating_dim
    SELECT * FROM team_pd_real_estate_debt.vsecurity_rating_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vposition_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vposition_analytics_fact
    SELECT * FROM team_pd_real_estate_debt.vposition_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vportfolio_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vportfolio_analytics_fact
    SELECT * FROM team_pd_real_estate_debt.vportfolio_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vcontract_details_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vcontract_details_fact
    SELECT * FROM team_pd_real_estate_debt.vcontract_details_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vcontract_summary_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vcontract_summary_fact
    SELECT * FROM team_pd_real_estate_debt.vcontract_summary_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vsecurity_master_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vsecurity_master_fact
    SELECT * FROM team_pd_real_estate_debt.vsecurity_master_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vsecurity_price_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vsecurity_price_fact
    SELECT * FROM team_pd_real_estate_debt.vsecurity_price_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vtransactions_collateral_exposure_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vtransactions_collateral_exposure_fact
    SELECT * FROM team_pd_real_estate_debt.vtransactions_collateral_exposure_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_vtransactions_collateral_positions_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_real_estate_debt.t_vtransactions_collateral_positions_fact
    SELECT * FROM team_pd_real_estate_debt.vtransactions_collateral_positions_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_real_estate_debt.refresh_all()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    CALL team_pd_real_estate_debt.refresh_vsecurity_dim();
    CALL team_pd_real_estate_debt.refresh_vsecurity_rating_dim();
    CALL team_pd_real_estate_debt.refresh_vposition_analytics_fact();
    CALL team_pd_real_estate_debt.refresh_vportfolio_analytics_fact();
    CALL team_pd_real_estate_debt.refresh_vcontract_details_fact();
    CALL team_pd_real_estate_debt.refresh_vcontract_summary_fact();
    CALL team_pd_real_estate_debt.refresh_vsecurity_master_fact();
    CALL team_pd_real_estate_debt.refresh_vsecurity_price_fact();
    CALL team_pd_real_estate_debt.refresh_vtransactions_collateral_exposure_fact();
    CALL team_pd_real_estate_debt.refresh_vtransactions_collateral_positions_fact();
END;

-- ============================================================================
-- TEAM_PD_SPECIALTY_FINANCE (10 entity procs + 1 aggregator)
-- ============================================================================

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vsecurity_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vsecurity_dim
    SELECT * FROM team_pd_specialty_finance.vsecurity_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vsecurity_rating_dim()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vsecurity_rating_dim
    SELECT * FROM team_pd_specialty_finance.vsecurity_rating_dim;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vposition_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vposition_analytics_fact
    SELECT * FROM team_pd_specialty_finance.vposition_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vportfolio_analytics_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vportfolio_analytics_fact
    SELECT * FROM team_pd_specialty_finance.vportfolio_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vcontract_details_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vcontract_details_fact
    SELECT * FROM team_pd_specialty_finance.vcontract_details_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vcontract_summary_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vcontract_summary_fact
    SELECT * FROM team_pd_specialty_finance.vcontract_summary_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vsecurity_master_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vsecurity_master_fact
    SELECT * FROM team_pd_specialty_finance.vsecurity_master_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vsecurity_price_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vsecurity_price_fact
    SELECT * FROM team_pd_specialty_finance.vsecurity_price_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vtransactions_collateral_exposure_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vtransactions_collateral_exposure_fact
    SELECT * FROM team_pd_specialty_finance.vtransactions_collateral_exposure_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_vtransactions_collateral_positions_fact()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE team_pd_specialty_finance.t_vtransactions_collateral_positions_fact
    SELECT * FROM team_pd_specialty_finance.vtransactions_collateral_positions_fact;
END;

CREATE OR REPLACE PROCEDURE team_pd_specialty_finance.refresh_all()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    CALL team_pd_specialty_finance.refresh_vsecurity_dim();
    CALL team_pd_specialty_finance.refresh_vsecurity_rating_dim();
    CALL team_pd_specialty_finance.refresh_vposition_analytics_fact();
    CALL team_pd_specialty_finance.refresh_vportfolio_analytics_fact();
    CALL team_pd_specialty_finance.refresh_vcontract_details_fact();
    CALL team_pd_specialty_finance.refresh_vcontract_summary_fact();
    CALL team_pd_specialty_finance.refresh_vsecurity_master_fact();
    CALL team_pd_specialty_finance.refresh_vsecurity_price_fact();
    CALL team_pd_specialty_finance.refresh_vtransactions_collateral_exposure_fact();
    CALL team_pd_specialty_finance.refresh_vtransactions_collateral_positions_fact();
END;

-- ============================================================================
-- GOLD_PD_CONSOLIDATED (3 entity procs + 1 aggregator)
--
-- Reads team_pd_*.v* (slow path) which transitively reaches silver/bronze.
-- Must run AFTER all 5 team_pd_*.refresh_all() invocations because the
-- consolidated views chain through team views (which in turn read silver
-- t_/v_). The orchestrator (00_setup/03_refresh_orchestrator.sql) enforces
-- this ordering.
-- ============================================================================

CREATE OR REPLACE PROCEDURE gold_pd_consolidated.refresh_vpd_position_book()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE gold_pd_consolidated.t_vpd_position_book
    SELECT * FROM gold_pd_consolidated.vpd_position_book;
END;

CREATE OR REPLACE PROCEDURE gold_pd_consolidated.refresh_vpd_contract_book()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE gold_pd_consolidated.t_vpd_contract_book
    SELECT * FROM gold_pd_consolidated.vpd_contract_book;
END;

CREATE OR REPLACE PROCEDURE gold_pd_consolidated.refresh_vpd_transaction_book()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    INSERT OVERWRITE gold_pd_consolidated.t_vpd_transaction_book
    SELECT * FROM gold_pd_consolidated.vpd_transaction_book;
END;

CREATE OR REPLACE PROCEDURE gold_pd_consolidated.refresh_all()
LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN
    CALL gold_pd_consolidated.refresh_vpd_position_book();
    CALL gold_pd_consolidated.refresh_vpd_contract_book();
    CALL gold_pd_consolidated.refresh_vpd_transaction_book();
END;

-- ============================================================================
-- Summary
-- ============================================================================

SELECT 'gold.refresh_procs complete' AS status,
       count(*) AS gold_proc_count
FROM information_schema.routines
WHERE routine_schema IN ('team_pd_direct_lending','team_pd_distressed','team_pd_mezzanine',
                         'team_pd_real_estate_debt','team_pd_specialty_finance','gold_pd_consolidated')
  AND routine_name LIKE 'refresh%';
