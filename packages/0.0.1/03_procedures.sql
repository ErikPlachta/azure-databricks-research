-- ============================================================================
-- BRIDGE FRAMEWORK — Stored Procedures
--
-- Run after 02_functions_and_views.sql.
--
-- Translation notes:
--   * T-SQL CREATE OR ALTER PROCEDURE → Databricks CREATE OR REPLACE PROCEDURE.
--   * Param prefix '@' dropped; declared as IN/INOUT/OUT.
--   * BEGIN/END/DECLARE/SET/IF/THEN/END IF — Databricks SQL Scripting syntax.
--   * THROW → RAISE_ERROR('msg').
--   * sp_executesql dynamic SQL → EXECUTE IMMEDIATE.
--   * SCOPE_IDENTITY() not available; we look up the just-inserted SK by its
--     unique attribute combination. Acceptable for serial seed/maintenance use;
--     not safe for concurrent multi-writer scenarios.
--   * Multi-statement transactions across tables are not supported in Delta.
--     The update-mapping procedure performs INSERT then UPDATE on the same
--     table, which is fine — each statement is an atomic Delta commit.
-- ============================================================================

USE CATALOG workspace;

-- ============================================================================
-- SECTION 1: SCD2 HELPER PROCEDURES
-- ============================================================================

-- 1.1 Close a dimension record (end-date it, clear is_current)
CREATE OR REPLACE PROCEDURE bridge.usp_close_dimension_record(
    IN p_schema_name    STRING,
    IN p_table_name     STRING,
    IN p_surrogate_key  BIGINT,
    IN p_effective_date DATE     DEFAULT NULL,
    IN p_succeeding_sk  BIGINT   DEFAULT NULL
)
COMMENT 'Closes out a dimension record (SCD2). Sets is_current=FALSE, sets effective_end_date to one day before p_effective_date, and links to the succeeding record. Call before inserting a new version.'
LANGUAGE SQL
SQL SECURITY INVOKER
BEGIN
    DECLARE eff_date     DATE;
    DECLARE sk_column    STRING;
    DECLARE sql_stmt     STRING;

    SET eff_date = COALESCE(p_effective_date, current_date());

    -- Map table_name → its surrogate key column name
    SET sk_column = CASE p_table_name
        WHEN 'investor'        THEN 'investor_sk'
        WHEN 'portfolio_group' THEN 'portfolio_group_sk'
        WHEN 'portfolio'       THEN 'portfolio_sk'
        WHEN 'entity'          THEN 'entity_sk'
        WHEN 'asset'           THEN 'asset_sk'
        WHEN 'security'        THEN 'security_sk'
        ELSE concat(p_table_name, '_sk')
    END;

    SET sql_stmt = concat(
        'UPDATE ', p_schema_name, '.', p_table_name, ' ',
        'SET is_current = FALSE, ',
        '    effective_end_date = date_sub(?, 1), ',
        '    succeeding_record_sk = ?, ',
        '    modified_at = current_timestamp(), ',
        '    modified_by = current_user() ',
        'WHERE ', sk_column, ' = ?'
    );

    EXECUTE IMMEDIATE sql_stmt USING eff_date, p_succeeding_sk, p_surrogate_key;
END;

-- ============================================================================
-- SECTION 2: CROSSWALK MANAGEMENT PROCEDURES
-- ============================================================================

-- 2.1 Add a new crosswalk mapping
CREATE OR REPLACE PROCEDURE bridge.usp_add_crosswalk_mapping(
    IN p_domain_code       STRING,
    IN p_source_code       STRING,
    IN p_source_key        STRING,
    IN p_target_code       STRING,
    IN p_target_key        STRING,
    IN p_relationship_type STRING DEFAULT 'ONE_TO_ONE',
    IN p_split_sequence    INT    DEFAULT NULL,
    IN p_split_description STRING DEFAULT NULL,
    IN p_effective_date    DATE   DEFAULT NULL
)
COMMENT 'Adds a new crosswalk mapping. Throws if a current mapping already exists for the source side.'
LANGUAGE SQL
SQL SECURITY INVOKER
BEGIN
    DECLARE v_domain_id BIGINT;
    DECLARE v_source_id BIGINT;
    DECLARE v_target_id BIGINT;
    DECLARE v_existing  BIGINT DEFAULT 0;
    DECLARE v_eff_date  DATE;

    SET v_eff_date  = COALESCE(p_effective_date, current_date());
    SET v_domain_id = (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = p_domain_code);
    SET v_source_id = (SELECT source_id FROM bridge.source_registry WHERE source_code = p_source_code);
    SET v_target_id = (SELECT source_id FROM bridge.source_registry WHERE source_code = p_target_code);

    IF v_domain_id IS NULL THEN
        SIGNAL SQLSTATE '45001' SET MESSAGE_TEXT = 'Invalid domain_code';
    END IF;
    IF v_source_id IS NULL THEN
        SIGNAL SQLSTATE '45002' SET MESSAGE_TEXT = 'Invalid source_code';
    END IF;
    IF v_target_id IS NULL THEN
        SIGNAL SQLSTATE '45003' SET MESSAGE_TEXT = 'Invalid target_code';
    END IF;

    SET v_existing = (
        SELECT COUNT(*)
        FROM bridge.key_crosswalk
        WHERE domain_id        = v_domain_id
          AND source_system_id = v_source_id
          AND source_key       = p_source_key
          AND target_system_id = v_target_id
          AND is_current       = TRUE
          AND (p_split_sequence IS NULL OR split_sequence = p_split_sequence)
    );

    IF v_existing > 0 THEN
        SIGNAL SQLSTATE '45004' SET MESSAGE_TEXT = 'A current mapping already exists for this source key. Use usp_update_crosswalk_mapping to change it.';
    END IF;

    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, split_sequence, split_description,
        is_current, effective_start_date
    )
    VALUES (
        v_domain_id, v_source_id, p_source_key, v_target_id, p_target_key,
        p_relationship_type, p_split_sequence, p_split_description,
        TRUE, v_eff_date
    );
END;

-- 2.2 Update / supersede an existing crosswalk mapping
CREATE OR REPLACE PROCEDURE bridge.usp_update_crosswalk_mapping(
    IN p_domain_code            STRING,
    IN p_source_code            STRING,
    IN p_source_key             STRING,
    IN p_target_code            STRING,
    IN p_new_target_key         STRING,
    IN p_new_relationship_type  STRING DEFAULT NULL,
    IN p_effective_date         DATE   DEFAULT NULL
)
COMMENT 'Closes the current mapping (SCD2) and inserts a new version with the new target_key. Maintains record chain.'
LANGUAGE SQL
SQL SECURITY INVOKER
BEGIN
    DECLARE v_domain_id              BIGINT;
    DECLARE v_source_id              BIGINT;
    DECLARE v_target_id              BIGINT;
    DECLARE v_old_sk                 BIGINT;
    DECLARE v_new_sk                 BIGINT;
    DECLARE v_old_relationship_type  STRING;
    DECLARE v_eff_date               DATE;

    SET v_eff_date  = COALESCE(p_effective_date, current_date());
    SET v_domain_id = (SELECT domain_id FROM bridge.key_domain      WHERE domain_code = p_domain_code);
    SET v_source_id = (SELECT source_id FROM bridge.source_registry WHERE source_code = p_source_code);
    SET v_target_id = (SELECT source_id FROM bridge.source_registry WHERE source_code = p_target_code);

    -- Find current mapping
    SET v_old_sk = (
        SELECT crosswalk_sk
        FROM bridge.key_crosswalk
        WHERE domain_id        = v_domain_id
          AND source_system_id = v_source_id
          AND source_key       = p_source_key
          AND target_system_id = v_target_id
          AND is_current       = TRUE
        ORDER BY crosswalk_sk DESC
        LIMIT 1
    );
    SET v_old_relationship_type = (
        SELECT relationship_type
        FROM bridge.key_crosswalk
        WHERE crosswalk_sk = v_old_sk
    );

    IF v_old_sk IS NULL THEN
        SIGNAL SQLSTATE '45005' SET MESSAGE_TEXT = 'No current mapping found to update.';
    END IF;

    -- Insert the new version, linking back to the old
    INSERT INTO bridge.key_crosswalk (
        domain_id, source_system_id, source_key, target_system_id, target_key,
        relationship_type, is_current, effective_start_date, preceding_record_sk
    )
    VALUES (
        v_domain_id, v_source_id, p_source_key, v_target_id, p_new_target_key,
        COALESCE(p_new_relationship_type, v_old_relationship_type),
        TRUE, v_eff_date, v_old_sk
    );

    -- Look up the new SK (no SCOPE_IDENTITY equivalent in Delta)
    SET v_new_sk = (
        SELECT crosswalk_sk
        FROM bridge.key_crosswalk
        WHERE domain_id        = v_domain_id
          AND source_system_id = v_source_id
          AND source_key       = p_source_key
          AND target_system_id = v_target_id
          AND target_key       = p_new_target_key
          AND is_current       = TRUE
          AND preceding_record_sk = v_old_sk
        ORDER BY crosswalk_sk DESC
        LIMIT 1
    );

    -- Close the old record and link forward to the new
    UPDATE bridge.key_crosswalk
    SET is_current           = FALSE,
        effective_end_date   = date_sub(v_eff_date, 1),
        succeeding_record_sk = v_new_sk,
        modified_at          = current_timestamp(),
        modified_by          = current_user()
    WHERE crosswalk_sk = v_old_sk;
END;

SELECT 'Procedures created successfully.' AS status;
