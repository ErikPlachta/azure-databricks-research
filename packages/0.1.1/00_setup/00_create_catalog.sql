-- ============================================================================
-- 00_setup/00_create_catalog.sql
-- Run ONCE per workspace before any other 0.1.x/ file.
--
-- Purpose: create a dedicated Unity Catalog catalog for the medallion-lake
-- demo, separate from 0.0.1's `workspace`. Shared between 0.1.0 and 0.1.1
-- (versions co-deploy via teardown + re-run; see 0.1.1/README.md).
--
-- Free Edition: SUPPORTED. Free Edition caps at one metastore per account but
-- does NOT cap catalogs within that metastore. Verified at:
-- https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations
--
-- Idempotent: safe to re-run. Subsequent files reference `medallion_demo`
-- via the `catalog_name` session variable in 01_config.sql. Note: with
-- IF NOT EXISTS, an existing COMMENT is NOT overwritten on re-run.
-- ============================================================================

CREATE CATALOG IF NOT EXISTS medallion_demo
    COMMENT 'azure-databricks 0.1.0 + 0.1.1 medallion-lake demo. See packages/azure-databricks/0.1.1/README.md (active version).';

-- Smoke check.
SELECT 'catalog_create complete' AS status, current_catalog() AS current_catalog;
