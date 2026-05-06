-- ============================================================================
-- 01_pre_bronze/07_tables_bloomberg.sql
-- Bloomberg market-data source. 1 raw table in 0.1.0 (FX rates only).
--
-- Bloomberg pricing layer is deferred to 0.1.5. See DECISIONS.md #10 for
-- rationale.
-- ============================================================================

DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;

-- 7.1 FX RATE -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS raw_bloomberg.fx_rate_raw (
    source_key                STRING       NOT NULL COMMENT 'Composite: from_currency + to_currency + rate_date',
    enterprise_key            STRING       NOT NULL,
    from_currency             STRING       NOT NULL COMMENT 'ISO-4217 currency code (USD, EUR, GBP, JPY, CAD, AUD, ...)',
    to_currency               STRING       NOT NULL,
    rate_date                 DATE         NOT NULL,
    fx_rate                   DECIMAL(18, 8) NOT NULL COMMENT 'Multiplier: amount_in_from_currency * fx_rate = amount_in_to_currency',
    rate_type                 STRING       COMMENT 'CLOSE / MID / BID / ASK',
    record_source             STRING       NOT NULL DEFAULT 'bloomberg',
    loaded_at                 TIMESTAMP    NOT NULL DEFAULT current_timestamp()
)
COMMENT 'Daily FX rates. Drives currency normalization in silver. Demo populates USD<->EUR/GBP/JPY/CAD/AUD across the position window.'
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

SELECT 'pre_bronze.bloomberg.tables complete' AS status, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'raw_bloomberg';
