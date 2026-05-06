-- ============================================================================
-- 00_setup/00_create_catalog.sql
-- Run ONCE per workspace before any other 0.1.0/ file.
--
-- Purpose: create a dedicated Unity Catalog catalog for the medallion-lake
-- demo, separate from 0.0.1's `workspace`.
--
-- Free Edition: SUPPORTED. Free Edition caps at one metastore per account but
-- does NOT cap catalogs within that metastore. Verified at:
-- https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations
--
-- Idempotent: safe to re-run. Subsequent files reference `medallion_demo`
-- via the `catalog_name` session variable in 01_config.sql.
-- ============================================================================

CREATE CATALOG IF NOT EXISTS medallion_demo
    COMMENT 'azure-databricks 0.1.0 medallion-lake demo. See packages/azure-databricks/0.1.0/README.md.';

-- Smoke check.
SELECT 'catalog_create complete' AS status, current_catalog() AS current_catalog;
