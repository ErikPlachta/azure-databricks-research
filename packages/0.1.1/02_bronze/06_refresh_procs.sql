-- ============================================================================
-- 02_bronze/06_refresh_procs.sql
-- Per-entity refresh procedures that populate bronze.t_<entity> from
-- bronze.v<entity> via INSERT OVERWRITE. Plus bronze.refresh_all() that
-- runs them all in any order (no inter-bronze dependencies).
--
-- These procs are operationally distinct from MVs (DECISIONS.md #5):
--   * Tables: explicitly refreshed via these procs
--   * MVs:    Databricks-managed (REFRESH MATERIALIZED VIEW or future SCHEDULE)
-- Both materialize the same logical body. Use procs for batch nightly runs;
-- use MVs for incremental / managed refresh.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- ----------------------------------------------------------------------------
-- Per-entity refresh procs
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE bronze.refresh_security()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vsecurity
    SELECT * FROM bronze.vsecurity;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_entity()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_ventity
    SELECT * FROM bronze.ventity;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_asset()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vasset
    SELECT * FROM bronze.vasset;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_portfolio()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vportfolio
    SELECT * FROM bronze.vportfolio;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_contract()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vcontract
    SELECT * FROM bronze.vcontract;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_business_unit()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vbusiness_unit
    SELECT * FROM bronze.vbusiness_unit;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_position()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vposition
    SELECT * FROM bronze.vposition;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_transaction()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vtransaction
    SELECT * FROM bronze.vtransaction;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_security_price()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vsecurity_price
    SELECT * FROM bronze.vsecurity_price;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_portfolio_risk()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vportfolio_risk
    SELECT * FROM bronze.vportfolio_risk;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_portfolio_performance()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vportfolio_performance
    SELECT * FROM bronze.vportfolio_performance;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_rating()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vrating
    SELECT * FROM bronze.vrating;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_collateral()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vcollateral
    SELECT * FROM bronze.vcollateral;
END;

CREATE OR REPLACE PROCEDURE bronze.refresh_fx_rate()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    INSERT OVERWRITE bronze.t_vfx_rate
    SELECT * FROM bronze.vfx_rate;
END;

-- ----------------------------------------------------------------------------
-- Master proc: refresh every bronze table.
-- Order doesn't matter — bronze entities have no inter-bronze FK dependencies
-- (FK enterprise_keys reference each other but tables don't enforce).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE bronze.refresh_all()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    CALL bronze.refresh_security();
    CALL bronze.refresh_entity();
    CALL bronze.refresh_asset();
    CALL bronze.refresh_portfolio();
    CALL bronze.refresh_contract();
    CALL bronze.refresh_business_unit();
    CALL bronze.refresh_position();
    CALL bronze.refresh_transaction();
    CALL bronze.refresh_security_price();
    CALL bronze.refresh_portfolio_risk();
    CALL bronze.refresh_portfolio_performance();
    CALL bronze.refresh_rating();
    CALL bronze.refresh_collateral();
    CALL bronze.refresh_fx_rate();
END;

SELECT 'bronze.refresh_procs complete' AS status,
       count(*) AS bronze_proc_count
FROM information_schema.routines
WHERE routine_schema = 'bronze'
  AND routine_name LIKE 'refresh%';
