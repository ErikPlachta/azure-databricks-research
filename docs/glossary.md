# Glossary

Term reference for this repo. Definitions are short by design — for *how* these concepts are used in the project, see [architecture.md](architecture.md) and [data-domain.md](data-domain.md).

Ordered by topic, not alphabetically, so reading top-to-bottom builds up correctly.

---

## Lakehouse fundamentals

### Delta Lake / Delta table
Open-source storage format underlying every table in Databricks. Adds ACID transactions, time-travel, schema enforcement, and change data feed on top of Parquet files. When this repo says "table," it means a Delta table.

### Unity Catalog
Databricks' metadata + governance layer. Three-level namespace: `catalog.schema.object`. A *catalog* is a top-level container; a *schema* (a.k.a. database) holds tables/views/MVs/functions.

### Catalog
Top-level Unity Catalog container. This repo uses two: `workspace` (legacy 0.0.1 Kimball model) and `medallion_demo` (active 0.1.x medallion). Free Edition supports multiple catalogs in its single metastore.

### Schema
The middle namespace level (catalog → schema → object). Examples in this repo: `bronze`, `investments`, `team_pd_direct_lending`. On Free Edition, each schema is capped at 100 objects — the constraint that drove the silver split.

### Volume
Unity Catalog's managed storage abstraction for files (not tables). Not used in this project — everything is in Delta tables.

### SQL warehouse
A Databricks compute cluster optimized for SQL. Free Edition gets a single serverless 2X-Small warehouse. This project targets that warehouse for all SQL execution.

---

## Storage object types

### Table (`t_<entity>`)
Physical Delta table. Populated explicitly via `INSERT OVERWRITE` in a refresh procedure. You control when it refreshes; the data sits there until you re-populate it. In this repo, table names are prefixed `t_`.

### View (`v<entity>`)
Logical, computed on every read. No cached result — each query re-executes the SELECT. Slow when views read views read views (the cascade explodes). Always reflects upstream state. Prefix `v`.

### Materialized view (`mv<entity>`)
A view whose SELECT body has been executed and cached as a physical table. Databricks (via Delta Live Tables under the hood) auto-refreshes it. Faster than views; less control than tables. Prefix `mv`.

### Refresh procedure
A SQL stored procedure (`usp_refresh_<entity>` or `<schema>.refresh_all`) that explicitly repopulates the corresponding `t_*` table. Pairs with the table; the MV path manages its own refresh.

### t/v/mv triplet
Every entity in this project ships all three artifacts (t, v, mv) with **the same logical SELECT body**. Triplets enable apples-to-apples comparison between the three storage strategies.

---

## MV-placement concepts

### MV cold-start
The fixed cost (Spark warmup + DLT pipeline bootstrap) Databricks pays the first time an MV materializes. On Free Edition's serverless 2X-Small, this is ~5–6 minutes per MV regardless of how trivial the body is. Often dominates total deploy time.

### Cascading MVs
When an MV reads from another MV (rather than from a view). Each layer reuses the materialized result below it instead of re-cascading through views. Dramatically faster: this repo's gold materialization dropped from 2.5+ hours to ~5–10 minutes when we switched bronze→silver→gold MV references from views to MVs.

### Byte-equality contract (0.1.0)
Original invariant: `v<entity>` and `mv<entity>` SELECT bodies must be byte-identical (modulo the `CREATE` clause). Made `v*` and `mv*` directly comparable but forced both to read upstream `v*`, defeating cascading. Superseded.

### Mechanical derivability (0.1.1+)
Replacement contract: `v<entity>` and `mv<entity>` bodies need not be byte-identical, but `mv<entity>` must be derivable from `v<entity>` by `s/v/mv/g` substitution at every upstream `FROM`/`JOIN`/`IN` reference. So `v*` cascades through views (slow path, production-faithful); `mv*` cascades through MVs (fast path). Both paths preserved for side-by-side comparison.

### MV-placement scenario (S0–S4)
Five permutations of where MVs live in the bronze/silver/gold stack. The whole project exists to compare them. See [architecture.md § The MV-placement experiment](architecture.md#the-mv-placement-experiment).

---

## Slowly Changing Dimensions

### SCD1 — overwrite
When a dimension attribute changes, you overwrite the old value. Simple and cheap. **Loses history** — yesterday's reports retroactively change. Useful when history doesn't matter (e.g., a typo fix).

### SCD2 — full history
When an attribute changes, you keep the old row and insert a new one. Each row has `effective_start_date`, `effective_end_date`, `is_current`, and a surrogate key unique per *version*. Optionally adds chain pointers (`preceding_record_sk`, `succeeding_record_sk`) for traversing history. **This repo uses SCD2 on all silver dims.** See [architecture.md § SCD2 mechanics](architecture.md#scd2-mechanics).

### SCD3 — partial history
Keep only the *previous* + *current* values in extra columns (`status`, `prior_status`). Limited history depth. Rarely worth it — usually loses to SCD2.

### SCD2-lite
This repo's term for SCD2 with effective dates only — no `preceding_record_sk`/`succeeding_record_sk` chain. Used for `vfx_rate_dim` because FX rates simply expire when superseded; you don't traverse the chain.

### Surrogate key (SK)
Artificial unique ID assigned by the dim table itself (e.g., `security_sk` from `xxhash64(source_key)` or `ROW_NUMBER`). Distinct from the natural key. In SCD2, the SK is unique **per version**, so `security_sk` 42 might be "Acme Bond, status=active, valid 2024-01-01 to 2025-03-15," and `security_sk` 73 is the same security after a status change.

### Natural key
The business identifier (e.g., a CUSIP or ISIN) — what humans use to talk about the entity.

### Source key (`source_key`)
The natural key as the source system emits it. Only unique within that source. Example: `'SS_SEC_12345'` from State Street.

### Enterprise key (`enterprise_key`)
Cross-source unification key. The crosswalk maps `(source_system, source_key) → enterprise_key`. The same security in State Street and Aspen has different `source_key`s but the same `enterprise_key`.

### Temporal join / BETWEEN join
Joining a fact to a dim via `fact.event_date BETWEEN dim.effective_start_date AND dim.effective_end_date`. Picks the dim version that was current at the fact's event date. Required for SCD2 to mean anything.

---

## Bronze unification

### Crosswalk
Lookup table (`bronze.crosswalk`) mapping `(source_system, source_key) → enterprise_key`. The seed populates it deterministically. Two UDFs (`fn_resolve_enterprise_key`, `fn_resolve_source_keys`) let SQL bridge between source-local and unified IDs.

### Provenance
Per-column metadata recording where each value came from. This repo's bronze entities carry `<col>_source` (which source system), `<col>_source_pref` (precedence rank), and `<col>_sources_in_conflict` (whether sources disagreed). Makes unification decisions auditable at row level.

### Precedence rule
Per-entity policy choosing the "default" source. Aspen wins for entity master data; State Street wins for security prices; eFront wins for contracts. Per-column overrides are allowed; provenance columns track when sources disagreed.

### Source-of-truth
The system designated as authoritative for a given attribute. In this repo, it's per-entity per-column (encoded in precedence rules), not global.

---

## Fact/dim modeling

### Fact table
Table of operational events — positions, trades, NAVs, cash flows. Typically wide (many FK columns to dims) and large (many rows). Examples here: `vposition_analytics_fact`, `vtransaction_fact`.

### Dimension table
Table of reference entities — security, contract, portfolio, business unit. Typically narrow (few descriptive columns) and small. SCD2-tracked in this repo.

### Bridge table
Resolves a many-to-many or reconciliation relationship that doesn't fit cleanly as a fact or dim. Example here: `vincome_bridge` reconciles interest accrued vs interest paid (P&L timing).

### Monthend snapshot
A point-in-time freeze of a fact aggregated to month-end. Used for SEC/accounting reporting cadence. In this repo: `vposition_monthend_fact`, `vportfolio_analytics_monthend_fact`.

### Cancels fact
A row-correction layer. When the source emits a duplicate (often a correction of an earlier row), the second instance lands in a `*_cancels_fact` table. Analysts join cancels to the live fact to audit out the bad row.

---

## Delta Lake features used

### Liquid clustering
Delta feature that clusters rows by specified columns (e.g., `(date_col, portfolio_sk)`) for query pruning, without explicit static partitions. Lets clustering evolve as data grows. Used on this repo's gold facts and dim subsets.

### Change Data Feed (CDF)
Delta feature emitting per-row inserts/updates/deletes as a queryable stream. Enabled on tables to audit what refresh procs mutated.

### Row tracking
Delta feature that gives each row a stable internal ID enabling CDC patterns without explicit change-tracking columns.

### Time travel
Delta feature for querying a table as of a past version (`VERSION AS OF` or `TIMESTAMP AS OF`). Useful for debugging refresh procs.

---

## Determinism

### Deterministic seed
The seed (`01_pre_bronze/08_seed.sql`) generates synthetic data where every value derives from `sha2(seed_components, 256)` — no `rand()`, no `uuid()`. Same configuration produces byte-identical data across runs. Required for validation gates and apples-to-apples performance comparisons.

### `xxhash64`
Fast deterministic 64-bit hash. Used in this repo to derive stable BIGINT surrogate keys from string source keys (`xxhash64(source_key)`) without needing a sequence.

### `sha2`
Cryptographic hash used by the seed for pseudo-random number generation. Slower than xxhash64 but deterministic and widely available — the seed leans on it for value generation.

---

## Operational

### `BEGIN..END` compound block
Spark SQL Scripting block that lets multiple statements share scope (variables, control flow). The Statement Execution API is single-statement, so `dbx_run.py` wraps each file in a compound block to preserve `DECLARE`s and procedural flow.

### `DECLARE OR REPLACE`
Spark SQL session-variable declaration. `dbx_run.py` rewrites this to `DECLARE` inside compound blocks because `OR REPLACE` is incompatible with the inner block scope.

### Personal Access Token (PAT)
Databricks credential type used for API auth. Stored as `DATABRICKS_TOKEN`. Recommended on Free Edition; service-principal auth is the production pattern.

### Asset Bundle
Databricks IaC format (`databricks.yml`) for declaring jobs, pipelines, and resources as code. This repo ships a stub — full automation lands in 0.1.7. See [`databricks.yml`](../databricks.yml).

### DLT (Delta Live Tables)
Databricks' declarative pipeline framework. Every materialized view is a one-table DLT pipeline under the hood — which is why MV refreshes are pipeline-quota-limited on Free Edition.
