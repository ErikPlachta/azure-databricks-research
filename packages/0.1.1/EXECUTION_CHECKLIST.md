# 0.1.1 — Execution checklist

Manual run-through for verifying a fresh deploy. Run each step in a Databricks SQL editor against the `medallion_demo` catalog. Each `.sql` file emits a status row in the result panel; expected text is listed in the "Expect" column. If a step fails, stop and triage before continuing — failures cascade.

The full checklist on Free Edition: ~25–35 min including the 5–10 min seed and 5–10 min gold MV materialization.

## Pre-flight

- [ ] Databricks workspace open; SQL warehouse running (Free Edition: serverless 2X-Small).
- [ ] No existing `medallion_demo` deploy you care about. If yes: run `00_setup/02_teardown.sql` with `RUN_TEARDOWN=TRUE` first.
- [ ] SQL editor session active. **Re-run `01_config.sql` per tab** — session vars don't carry across tabs.
- [ ] Free Edition seed defaults intact (`seed_n_securities = 200`, `seed_positions_per_team_per_year = 2000`). Override per `01_config.sql` inline comments if running on paid.

## Phase A — Setup

| Step | File | Expect (status row text) | Notes |
| ---- | ---- | ------------------------ | ----- |
| A.1 | `00_setup/00_create_catalog.sql` | `catalog medallion_demo created` (or already-exists) | One-time per catalog. |
| A.2 | `00_setup/01_config.sql` | `config_load complete` + `active_catalog = medallion_demo` | Re-run at the start of every session. |

## Phase B — Pre-bronze (raw landings)

| Step | File | Expect | Notes |
| ---- | ---- | ------ | ----- |
| B.1 | `01_pre_bronze/01_schemas.sql` | `pre_bronze.schemas complete` | 6 schemas created. |
| B.2 | `01_pre_bronze/02_tables_state_street.sql` | `state_street.tables complete` | 3 tables. |
| B.3 | `01_pre_bronze/03_tables_aladdin.sql` | `aladdin.tables complete` | 3 tables. |
| B.4 | `01_pre_bronze/04_tables_aspen.sql` | `aspen.tables complete` | 6 tables. |
| B.5 | `01_pre_bronze/05_tables_efront.sql` | `efront.tables complete` | 6 tables. |
| B.6 | `01_pre_bronze/06_tables_internal_admin.sql` | `internal_admin.tables complete` | 1 table. |
| B.7 | `01_pre_bronze/07_tables_bloomberg.sql` | `bloomberg.tables complete` | 1 table. |
| B.8 | `01_pre_bronze/08_seed.sql` | `seed complete` | **5–10 min on Free Edition.** Deterministic; reruns produce same row counts. |

After B.8, sanity-check seed sizes:

```sql
SELECT 'raw_state_street.position_raw' AS t, count(*) AS n FROM raw_state_street.position_raw
UNION ALL SELECT 'raw_aspen.security_master_raw', count(*) FROM raw_aspen.security_master_raw
UNION ALL SELECT 'raw_efront.contract_raw', count(*) FROM raw_efront.contract_raw
UNION ALL SELECT 'raw_bloomberg.fx_rate_raw', count(*) FROM raw_bloomberg.fx_rate_raw;
```

Expect (Free Edition default seed): position_raw ~50K–100K, security_master_raw ~200, contract_raw ~100, fx_rate_raw ~5K–10K.

## Phase C — Bronze

| Step | File | Expect |
| ---- | ---- | ------ |
| C.1 | `02_bronze/01_schema.sql` | `bronze.schema complete` |
| C.2 | `02_bronze/02_crosswalk.sql` | `bronze.crosswalk complete` |
| C.3 | `02_bronze/03_tables.sql` | `bronze.tables complete` (14 tables) |
| C.4 | `02_bronze/04_views.sql` | `bronze.views complete` (14 views) |
| C.5 | `02_bronze/05_materialized_views.sql` | `bronze.materialized_views complete` (14 MVs) |
| C.6 | `02_bronze/06_refresh_procs.sql` | `bronze.refresh_procs complete` (15 routines: 14 per-entity + 1 master) |
| C.7 | `02_bronze/07_lineage_audit.sql` | `bronze.lineage_audit complete` |

## Phase D — Silver

| Step | File | Expect |
| ---- | ---- | ------ |
| D.1 | `03_silver/01_schema.sql` | `silver.schemas complete` (2 schemas) |
| D.2 | `03_silver/02_tables.sql` | `silver.tables complete` (24 tables: 18 + 6) |
| D.3 | `03_silver/03_views.sql` | `silver.views complete` (24 views) |
| D.4 | `03_silver/04_materialized_views.sql` | `silver.materialized_views complete` (24 MVs) |
| D.5 | `03_silver/05_refresh_procs.sql` | `silver.refresh_procs complete` |
| D.6 | `03_silver/06_documentation.sql` | `silver.documentation complete` |

## Phase E — Gold

| Step | File | Expect |
| ---- | ---- | ------ |
| E.1 | `04_gold/01_schemas.sql` | `gold.schemas complete` (6 schemas) |
| E.2 | `04_gold/02_tables.sql` | `gold.tables complete` (53 tables: 50 team + 3 consolidated) |
| E.3 | `04_gold/03_views.sql` | `gold.views complete` (53 views) |
| E.4 | `04_gold/04_materialized_views.sql` | `gold.materialized_views complete` (53 MVs) |
| E.5 | `04_gold/05_refresh_procs.sql` | `gold.refresh_procs complete` (~60 routines) |

## Phase F — Orchestration (table population)

| Step | Action | Expect |
| ---- | ------ | ------ |
| F.1 | Run `00_setup/03_refresh_orchestrator.sql` | `refresh_orchestrator created` |
| F.2 | `CALL bronze_silver_gold_refresh()` | 3-row layer-duration summary (bronze, silver, gold seconds). **Pre-Phase 3 fix this fails at gold.** |

## Phase G — MV refresh (cascading materialized path)

MVs are operationally distinct from tables (DECISIONS.md #5). Refresh in dependency order:

```sql
-- Bronze MVs (14)
REFRESH MATERIALIZED VIEW bronze.mvsecurity;
REFRESH MATERIALIZED VIEW bronze.ventity;  -- and the other 12
-- ...

-- Silver MVs (23) — reads bronze.mv* (cascading)
REFRESH MATERIALIZED VIEW investments.mvsecurity_dim;
-- ...

-- Gold MVs (53) — reads investments.mv* + team_pd_*.mv* (cascading)
REFRESH MATERIALIZED VIEW team_pd_direct_lending.mvposition_analytics_fact;
-- ...
REFRESH MATERIALIZED VIEW gold_pd_consolidated.mvpd_position_book;
```

Free Edition expected total: ~5–10 min for the gold layer (vs 2.5h+ in 0.1.0 without cascading).

## Object inventory

After E.5 + F.2, run:

```sql
SELECT table_schema, count(*) AS n
FROM information_schema.tables
WHERE table_catalog = 'medallion_demo'
GROUP BY 1 ORDER BY 2 DESC;
```

Expect 15 schema rows, each `<100`. Approximate counts per schema after a clean deploy:

| Schema | Count | Mix |
| ------ | ----- | --- |
| `bronze` | ~58 | 14 t + 14 v + 14 mv + 14 mv-backing + 1 crosswalk + 1 audit |
| `investments` | ~79 | 18 t + 18 v + 18 mv + 18 mv-backing + 8 procs |
| `investments_history` | ~30 | 6 t + 6 v + 6 mv + 6 mv-backing + procs |
| `team_pd_*` (×5) | ~50 each | 10 t + 10 v + 10 mv + 10 mv-backing + 11 procs |
| `gold_pd_consolidated` | ~16 | 3 t + 3 v + 3 mv + 3 mv-backing + 4 procs |
| `raw_*` (×6) | varies (1–6 tables) | source raw landings |

If any schema's count exceeds 100, you've hit Free Edition's per-schema cap — stop and refer to DECISIONS.md #12 for split strategy.

## Lineage audit

```sql
SELECT * FROM bronze.bronze_lineage_audit ORDER BY entity;
```

Expect: 14 entity rows. Per-entity, no source contribution should be 0 unless that source is intentionally toggled off in `01_config.sql`. Holes appear when seed for a source ran with `skip_<source> = TRUE` — fine, but worth confirming the toggles match your intent.

## Sample queries (per gold team)

```sql
-- Each query should return non-zero rows for its team's bu_code.
SELECT 'team_pd_direct_lending'    AS team, count(*) AS n FROM team_pd_direct_lending.t_vposition_analytics_fact
UNION ALL SELECT 'team_pd_distressed',         count(*) FROM team_pd_distressed.t_vposition_analytics_fact
UNION ALL SELECT 'team_pd_mezzanine',          count(*) FROM team_pd_mezzanine.t_vposition_analytics_fact
UNION ALL SELECT 'team_pd_real_estate_debt',   count(*) FROM team_pd_real_estate_debt.t_vposition_analytics_fact
UNION ALL SELECT 'team_pd_specialty_finance',  count(*) FROM team_pd_specialty_finance.t_vposition_analytics_fact
UNION ALL SELECT 'gold_pd_consolidated.position_book', count(*) FROM gold_pd_consolidated.t_vpd_position_book;
```

Expect: each row has count > 0. Consolidated row should equal the sum of the 5 team rows (within a small delta if any team has rows that drop in the UNION via filter).

## Validate harness

After Phase F + G, run `05_validate/` files in order. Each emits a `'PASS'` or `'FAIL'` row. Any `'FAIL'` blocks demos.

## Done

If everything passes: explore `06_demos/` next. The freshness demo (`06_demos/06_freshness_demo.sql`) and cascade demo (`06_demos/09_cascade_demo.sql`) are the load-bearing pedagogy for understanding the v-vs-mv-vs-t tradeoffs.

## Failure triage shortlist

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `Table or view not found: ...` during MV refresh | Silver MVs not refreshed before gold MVs | Refresh in order: bronze → silver → team_pd_* → consolidated |
| Object-count >100 in any schema | Free Edition per-schema cap | Reduce seed sizes in `01_config.sql` or split schema (see DECISIONS.md #12) |
| `team_pd_*.refresh_all() does not exist` from F.2 | Phase 3 (`04_gold/05_refresh_procs.sql`) not run | Run E.5 |
| Gold MV refresh hangs >30 min | Likely cascading through `v*` instead of `mv*` (Decision #13 violation) | Compare body via `SHOW CREATE` — see `05_validate/03_view_mv_derivability.sql` |
| Empty `t_vpd_transaction_book` after F.2 | No raw transactions seeded for PD-team portfolios | Confirm `skip_state_street = FALSE` in `01_config.sql` and reseed |
