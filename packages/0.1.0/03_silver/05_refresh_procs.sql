-- ============================================================================
-- 03_silver/05_refresh_procs.sql
-- Per-entity refresh procs that populate investments.t_<entity> from
-- investments.v<entity> via INSERT OVERWRITE. Plus investments.refresh_all()
-- master.
--
-- Order matters: dims first (SCD2 chains must be current before facts can
-- temporally-resolve their dim_sks via BETWEEN joins), then bridges, then
-- base facts, then monthend snapshots, then cancels.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ----------------------------------------------------------------------------
-- Dims (8 SCD2 + 1 type-2-lite)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE investments.refresh_security_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vsecurity_dim SELECT * FROM investments.vsecurity_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_security_rating_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vsecurity_rating_dim SELECT * FROM investments.vsecurity_rating_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_contract_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vcontract_dim SELECT * FROM investments.vcontract_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_portfolio_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vportfolio_dim SELECT * FROM investments.vportfolio_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_entity_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_ventity_dim SELECT * FROM investments.ventity_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_security_industry_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vsecurity_industry_dim SELECT * FROM investments.vsecurity_industry_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_reporting_group_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vreporting_group_dim SELECT * FROM investments.vreporting_group_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_business_unit_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vbusiness_unit_dim SELECT * FROM investments.vbusiness_unit_dim;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_fx_rate_dim()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vfx_rate_dim SELECT * FROM investments.vfx_rate_dim;
END;

-- ----------------------------------------------------------------------------
-- Base facts (8)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE investments.refresh_position_analytics_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vposition_analytics_fact SELECT * FROM investments.vposition_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_security_master_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vsecurity_master_fact SELECT * FROM investments.vsecurity_master_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_security_price_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vsecurity_price_fact SELECT * FROM investments.vsecurity_price_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_contract_details_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vcontract_details_fact SELECT * FROM investments.vcontract_details_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_contract_summary_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vcontract_summary_fact SELECT * FROM investments.vcontract_summary_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_portfolio_analytics_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vportfolio_analytics_fact SELECT * FROM investments.vportfolio_analytics_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_collateral_exposure_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vtransactions_collateral_exposure_fact SELECT * FROM investments.vtransactions_collateral_exposure_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_collateral_positions_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vtransactions_collateral_positions_fact SELECT * FROM investments.vtransactions_collateral_positions_fact;
END;

-- ----------------------------------------------------------------------------
-- Monthend snapshots (2) — depend on base facts
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE investments.refresh_position_monthend_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vposition_monthend_fact SELECT * FROM investments.vposition_monthend_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_portfolio_analytics_monthend_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vportfolio_analytics_monthend_fact SELECT * FROM investments.vportfolio_analytics_monthend_fact;
END;

-- ----------------------------------------------------------------------------
-- Cancels (3)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE investments.refresh_contract_details_cancels_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vcontract_details_cancels_fact SELECT * FROM investments.vcontract_details_cancels_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_position_cancels_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vposition_cancels_fact SELECT * FROM investments.vposition_cancels_fact;
END;

CREATE OR REPLACE PROCEDURE investments.refresh_security_price_cancels_fact()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vsecurity_price_cancels_fact SELECT * FROM investments.vsecurity_price_cancels_fact;
END;

-- ----------------------------------------------------------------------------
-- Bridge (1)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE investments.refresh_income_bridge()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE investments.t_vincome_bridge SELECT * FROM investments.vincome_bridge;
END;

-- ----------------------------------------------------------------------------
-- Master orchestrator. Dims first (chains must be current before facts
-- temporally-resolve dim_sks), then base facts, then monthends, then cancels,
-- then bridge.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE investments.refresh_all()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    -- Dims
    CALL investments.refresh_security_dim();
    CALL investments.refresh_security_rating_dim();
    CALL investments.refresh_contract_dim();
    CALL investments.refresh_portfolio_dim();
    CALL investments.refresh_entity_dim();
    CALL investments.refresh_security_industry_dim();
    CALL investments.refresh_reporting_group_dim();
    CALL investments.refresh_business_unit_dim();
    CALL investments.refresh_fx_rate_dim();
    -- Base facts
    CALL investments.refresh_position_analytics_fact();
    CALL investments.refresh_security_master_fact();
    CALL investments.refresh_security_price_fact();
    CALL investments.refresh_contract_details_fact();
    CALL investments.refresh_contract_summary_fact();
    CALL investments.refresh_portfolio_analytics_fact();
    CALL investments.refresh_collateral_exposure_fact();
    CALL investments.refresh_collateral_positions_fact();
    -- Monthend snapshots
    CALL investments.refresh_position_monthend_fact();
    CALL investments.refresh_portfolio_analytics_monthend_fact();
    -- Cancels
    CALL investments.refresh_contract_details_cancels_fact();
    CALL investments.refresh_position_cancels_fact();
    CALL investments.refresh_security_price_cancels_fact();
    -- Bridge
    CALL investments.refresh_income_bridge();
END;

SELECT 'silver.refresh_procs complete' AS status,
       count(*) AS silver_proc_count
FROM information_schema.routines
WHERE routine_schema = 'investments' AND routine_name LIKE 'refresh%';
