# Bridge Framework — Databricks Port

Faithful port of a SQL Server Bridge Framework POC to Databricks SQL (Unity Catalog, Delta Lake, serverless SQL Warehouse). Targets Databricks Free Edition or any UC-enabled workspace.

The project has grown beyond a simple T-SQL → Databricks SQL translation. It now also includes:

- **SCD2 history simulation** spread across a configurable position window (default 20 years)
- **Two fact tables** with canonical Kimball anchor + temporal-resolution joins
- **Consumer-layer view modeling** (no SKs exposed, joins by string identifiers — mirroring real enterprise constraints)
- **Materialized View performance demos** comparing live-view paths vs MV-backed paths

## Run order

Run files in numeric order in the SQL editor. Each ends with a `status` row.

| File                                  | Purpose                                                                                                                                                   |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `01_ddl_schema_tables.sql`            | Schemas (`bridge`, `dim`, `fact`) + Delta tables. Liquid Clustering, row tracking, CDF, identity columns.                                                 |
| `02_functions_and_views.sql`          | Scalar UDFs (`fn_resolve_key_current`, etc.), table UDFs, lookup views.                                                                                   |
| `03_procedures.sql`                   | SCD2 close-out helper + crosswalk add/update procedures.                                                                                                  |
| `04_seed_data.sql`                    | Big idempotent setup/seed proc. Declares session vars (`position_start_date`, `position_end_date`, `simulate_history`, `skip_positions`); CALLs the proc. |
| `05_test_scenarios.sql`               | Validation queries against the seeded data. Read-only except Test 9 (which self-cleans).                                                                  |
| `06_analytical_views.sql`             | `mart` schema + 2 simple views (`vw_aum_daily_by_portfolio`, `vw_position_enriched`).                                                                     |
| `07_materialized_views.sql`           | MV counterparts to file 06.                                                                                                                               |
| `08_mv_performance_demo.sql`          | Simple-path View vs MV demo. Plus enzyme refresh-technique inspection via `event_log()`.                                                                  |
| `09_advanced_views.sql`               | 2 heavy views: window functions and non-equi SCD2 crosswalk joins.                                                                                        |
| `10_advanced_materialized_views.sql`  | MV counterparts to file 09.                                                                                                                               |
| `11_advanced_mv_performance_demo.sql` | Heavy-path comparisons. Demonstrates `MAINTENANCE_TYPE_COMPLETE_RECOMPUTE` trade-off.                                                                     |
| `12_consumer_views.sql`               | Consumer-layer views — no SKs, computed columns, designed for string-key joins.                                                                           |
| `13_consumer_materialized_views.sql`  | MV counterparts to file 12.                                                                                                                               |
| `14_consumer_perf_demo.sql`           | View ⋈ View on string keys, full window, no LIMITs.                                                                                                       |
| `15_fact_transaction_setup.sql`       | `fact.transaction` table + seed proc + invocation. ~280K transaction rows by default.                                                                     |
| `16_transaction_views_and_mv.sql`     | `vw_transaction_book` / `vw_transaction_detail` and MV counterparts.                                                                                      |
| `17_multi_fact_demo.sql`              | Multi-fact join (transaction × position) on string keys. The heaviest demo.                                                                               |

Files 01–05 are the framework. Files 06–08 are the simple MV demo. Files 09–11 are the heavy single-fact MV demo. Files 12–14 are the consumer-layer string-join demo. Files 15–17 add the second fact and the multi-fact demo.

## Default scale

The default 20-year window with `simulate_history = TRUE` produces:

| Table                  | Rows                                  |
| ---------------------- | ------------------------------------- |
| `dim.investor`         | 50 (+ 10 SCD2 successors)             |
| `dim.portfolio_group`  | 20                                    |
| `dim.portfolio`        | 100                                   |
| `dim.entity`           | 200 (+ 25 successors, 5 soft-deleted) |
| `dim.asset`            | 300                                   |
| `dim.security`         | 700                                   |
| `bridge.key_crosswalk` | ~1,260 (+ 20 SCD2 supersessions)      |
| `fact.position`        | ~5.0–5.1M                             |
| `fact.transaction`     | ~280K                                 |
| Allocation tables      | ~500 total                            |

Initial materialization of all MVs against this scale: ~5–15 minutes total on Free Edition serverless.

## Configuring the position window

Session variables are declared at the top of `04_seed_data.sql` and re-declared in `15_fact_transaction_setup.sql`:

```sql
DECLARE OR REPLACE VARIABLE position_start_date DATE DEFAULT date_sub(current_date(), 365 * 20);
DECLARE OR REPLACE VARIABLE position_end_date   DATE DEFAULT current_date();
DECLARE OR REPLACE VARIABLE simulate_history    BOOLEAN DEFAULT TRUE;
DECLARE OR REPLACE VARIABLE skip_positions      BOOLEAN DEFAULT FALSE;
```

Override before running:

```sql
SET VARIABLE position_start_date = DATE'2010-01-01';
SET VARIABLE position_end_date   = DATE'2024-12-31';
```

Session variables don't persist across SQL editor sessions. Each fresh session picks up the defaults.

## Architecture in three layers

### Base data (`bridge`, `dim`, `fact`)

SCD2-tracked dimensions, crosswalks, two facts. Liquid Clustering on hot filter columns. Row tracking enabled on everything (required for ROW_BASED MV refresh). Schemas not directly exposed to consumers in production deployments.

### Mart objects (`mart` schema)

Views and materialized views consumers query directly. Same view name + MV name pairs share IDENTICAL select bodies, so the View vs MV comparison is apples-to-apples.

### SCD2 fact-load pattern

Both `fact.position` and `fact.transaction` use the canonical Kimball pattern: each fact row references the dim SK that was current at the fact's date. Generation walks the SCD2 chain via `enterprise_xxx_id` natural key + `effective_start_date` / `effective_end_date` temporal filter. Restructured entities split positions across old + new SKs; soft-deleted entities cause facts to naturally stop after dissolution.

## SCD2 history simulation (Phase 6 of the seed)

Distributed deterministically across the position window:

| Scenario                | Count | Pattern                                             |
| ----------------------- | ----- | --------------------------------------------------- |
| Investor renames        | 10    | Insert successor, MERGE-close predecessor           |
| Entity restructurings   | 25    | Insert successor, MERGE-close predecessor           |
| Entity soft-deletes     | 5     | Close without successor (no `succeeding_record_sk`) |
| Crosswalk supersessions | 20    | New target*key prefixed `REMAPPED*`                 |

Event dates use evenly-spaced base + ±60-day deterministic hash jitter, clamped to the position window. Same shape of history regardless of window length.

## MV demo progression

Each demo pair (`vw_X` ⋈ `mv_X`) uses identical SELECT bodies, so timing differences come purely from materialization.

**File 08** — simple aggregations and broadcast joins. Modern Photon + Liquid Clustering keeps the View path fast; the MV path is only marginally faster. Useful as a baseline showing not every query benefits from materialization.

**File 11** — window functions (LAG, moving averages, DENSE_RANK) and non-equi SCD2 crosswalk joins. Photon can't optimize these away. Larger speedup, but both MVs refresh via `MAINTENANCE_TYPE_COMPLETE_RECOMPUTE` since these patterns aren't incrementalizable.

**File 14** — consumer-layer pattern. Two views joined by `(portfolio_name, position_date)` string + date, with all filters on computed columns (concentration percentages, ranks, percentages of AUM). The optimizer's hands are tied — no predicate pushdown, no shared scan state. Worst case for the live-view path.

**File 17** — multi-fact pattern. `fact.transaction` daily aggregates joined to `fact.position` daily aggregates on `(portfolio_name, date)`. The "two-fact constellation" enterprise queries that drive turnover-ratio analytics, AUM-change attribution, etc.

## Refresh technique inspection

File 08 demo 4 and file 11 demo 5 show how to inspect what enzyme picked:

```sql
WITH parsed AS (
    SELECT timestamp,
           from_json(details:planning_information,
                     'struct<technique_information: array<struct<
                         maintenance_type: string,
                         is_chosen: boolean,
                         is_applicable: boolean,
                         cost: double>>>') AS pi
    FROM event_log(TABLE(mart.mv_X))
    WHERE event_type = 'planning_information'
)
SELECT timestamp, chosen.maintenance_type, chosen.cost
FROM parsed
LATERAL VIEW explode(pi.technique_information) t AS chosen
WHERE chosen.is_chosen = TRUE
ORDER BY timestamp DESC;
```

`maintenance_type` values: `MAINTENANCE_TYPE_ROW_BASED`, `MAINTENANCE_TYPE_PARTITION_OVERWRITE`, `MAINTENANCE_TYPE_COMPLETE_RECOMPUTE`, `MAINTENANCE_TYPE_NO_OP`. Catalog Explorer's "See refresh details" button shows the same info via the GUI.

## Translation summary (T-SQL → Databricks SQL)

### Mechanical

- `IF OBJECT_ID(...) IS NULL CREATE TABLE` → `CREATE TABLE IF NOT EXISTS`
- `INT/BIGINT IDENTITY(1,1)` → `BIGINT GENERATED BY DEFAULT AS IDENTITY` (must be BIGINT)
- `BIT` → `BOOLEAN`; `DATETIME2` → `TIMESTAMP`; `NVARCHAR(MAX)` / `UNIQUEIDENTIFIER` → `STRING`
- `GETUTCDATE()` → `current_timestamp()`; `SYSTEM_USER` → `current_user()`; `NEWID()` → `uuid()`
- `DATEADD(DAY, n, d)` → `date_add(d, n)`; `ISNULL` → `COALESCE`
- `CHOOSE(idx, a, b, c)` → `element_at(array(a, b, c), idx)`
- `RIGHT('0000' + CAST(n AS VARCHAR), 4)` → `lpad(cast(n as string), 4, '0')`
- `sys.objects` row-generator trick → `range(N)` for foldable, `sequence(start, end, interval)` for runtime
- `INDEX IX_xxx (...) WHERE is_current = 1` → `CLUSTER BY (...)` (Liquid Clustering)
- `MERGE ... WHEN NOT MATCHED BY TARGET THEN INSERT` → `WHEN NOT MATCHED THEN INSERT` (drop "BY TARGET")
- `THROW 50001, 'msg', 1` → `SIGNAL SQLSTATE '45xxx' SET MESSAGE_TEXT = 'msg'`
- `EXEC proc @p1 = v1` → `CALL proc(p_p1 => v1)`
- `@@ROWCOUNT` / `SCOPE_IDENTITY()` → re-query explicitly
- `UPDATE ... FROM` (T-SQL extension) → `MERGE INTO` (Spark UPDATE doesn't support `FROM`)

### Structural

- T-SQL stored procedures → Databricks SQL Scripting `CREATE OR REPLACE PROCEDURE ... LANGUAGE SQL SQL SECURITY INVOKER`. Variables declared without `@`. `BEGIN ... END`, `IF ... THEN ... END IF`, `EXECUTE IMMEDIATE` for dynamic SQL.
- T-SQL TVFs returning `@results TABLE` → SQL UDF with `RETURNS TABLE (...) RETURN <single query>`.
- `BEGIN TRANSACTION / COMMIT` removed. Multi-table transactions don't apply on Delta.
- Procedure parameter forwarding: named args can omit _trailing_ DEFAULTs but not _middle_ ones. Plan signatures accordingly.

## Fixes / improvements made along the way

1. **`fact.position` SCD2 anchor + temporal-resolution.** Originally joined by SK only. Rewrote to follow the canonical Kimball pattern: anchor SK gives `enterprise_xxx_id`, second join finds the version current at position_date. Restructured entities split fact rows across old/new SKs; soft-deleted entities naturally truncate fact data.
2. **`fact.transaction` added** with the same pattern. ~20 transactions per security per year, 4 transaction types (BUY, SELL, ACQUISITION, DISPOSAL), counterparty + record_source diversity.
3. **Phase 6 SCD2 history.** Investor renames, entity restructurings, soft-deletes, and crosswalk supersessions. Distributed deterministically across the position window so 20-year windows have history throughout, not just at the end.
4. **Allocation tables now populated.** Original code declared but never seeded them.
5. **Position randomness off-by-one fixed.** `cast(rand() * 21 as int) - 10` → symmetric -10..+10.
6. **Row tracking + CDF enabled** on every table. Required for ROW_BASED MV refresh.
7. **Resolution UDFs made deterministic.** `ORDER BY crosswalk_sk DESC LIMIT 1` for the case where multiple `is_current = TRUE` rows exist (informational PK only, no enforcement).
8. **Asset country diversity.** USA / CAN / GBR / DEU / JPN distribution.
9. **Liquid Clustering** on hot filter columns (`enterprise_xxx_id` for dims, `position_date / portfolio_sk` for fact, `domain_id / source_system_id / source_key` for crosswalk).
10. **Test 9 idempotency.** Self-cleans `SS_ENT_TEST_999` artifacts at the start so file 05 can re-run without re-seeding.

## Known caveats

- **`event_log()` schema.** `details` is a JSON STRING accessed via `:` path operator. The `planning_information` payload is itself JSON; needs `from_json` + explode. See file 08 demo 4 for the working pattern.
- **`LATERAL` vs `LATERAL VIEW`.** Spark uses `LATERAL VIEW` for explode-style generators (e.g., explode of an array). For SQL UDF table functions you use `, LATERAL fn(...)`. They're not interchangeable. Test 5 in file 05 demonstrates both.
- **Procedure DEFAULT params.** Named CALLs can omit trailing DEFAULTs but not middle ones — Databricks raises "number of args and params must match after binding". Reorder signatures so DEFAULT params are strictly trailing.
- **No early `RETURN`.** Compound SQL Scripting blocks don't support `RETURN`. Use `IF / ELSE` to gate execution paths.
- **Spark UPDATE no `FROM`.** Use `MERGE INTO` with a derived source CTE.
- **Free Edition timeouts.** Heaviest demo queries (file 14, file 17) may hit serverless query timeout. That's itself part of the demo: the query is intractable as a live view.
- **Session variables are session-scoped.** `DECLARE OR REPLACE VARIABLE` doesn't persist across SQL editor sessions. Files 04 and 15 both re-declare so they can run standalone.

## What to read first

If you're new to the project:

1. Read this README.
2. Skim `04_seed_data.sql` from the top — the file header and Phase headers explain the data model better than this README does.
3. Run files 01 → 05 with default settings to seed.
4. Run file 08 cell-by-cell to see the simple-MV pattern (will look surprisingly fast on Photon).
5. Run file 14 to see why the simple demo wasn't dramatic. The consumer-layer pattern with string joins is where MVs earn their keep.
6. Run files 15 → 17 for the multi-fact case.

If you're extending the framework: each phase or scenario is contained. SCD2 events live in Phase 6 of `04`, and you can add a new sub-phase by copying any of the existing 6.x blocks. New facts follow the file-15 pattern (DDL + standalone seed proc + invocation). New MVs follow the 06/07 split (matched View + MV pairs in `mart`).
