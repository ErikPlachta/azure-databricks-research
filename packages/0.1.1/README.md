# 0.1.1 — Medallion lake simulation (schema-split + cascading MVs)

4-tier medallion (pre-bronze → bronze → silver `investments` + `investments_history` → gold per-team) for evaluating MV-placement strategies in a multi-source, multi-team analytics stack. Lives in its own Unity Catalog catalog (`medallion_demo`) so it doesn't touch `0.0.1` in `workspace`.

## What changed from 0.1.0

| Change                                                                                               | Why                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Silver schema split: `investments` (18 current) + `investments_history` (6: monthend/cancels/bridge) | Free Edition caps schemas at 100 objects. 0.1.0's `investments` hit the cap. Split mirrors user's enterprise `investments` + `investments_historical` pattern.                                                                               |
| Cascading MV references (silver mv → bronze mv, gold mv → silver mv)                                 | 0.1.0's gold MV materialization took 2.5+ hours because gold mv bodies referenced silver views (full re-cascade). New pattern: mv reads from already-materialized upstream mv. Drops to ~5–10 min total.                                     |
| Byte-equality contract relaxed                                                                       | v* and mv* SELECT projections still mechanically derivable (`s/v/mv/g` substitution at upstream refs). `v*` references upstream `v*` (slow path = production reality). `mv*` references upstream `mv*` (fast cascading path = MV value-add). |

## Prereq — create the catalog (one-time)

```sql
-- Run once. Free Edition: supported. See 00_setup/00_create_catalog.sql.
-- medallion_demo is shared between 0.1.0 and 0.1.1 — they don't co-exist
-- in the same deploy (teardown + re-run to switch versions).
CREATE CATALOG IF NOT EXISTS medallion_demo
  COMMENT 'azure-databricks 0.1.0 + 0.1.1 medallion-lake demo';
```

After this, every subsequent SQL file uses `EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;` to scope to `medallion_demo`. Override `catalog_name` in `01_config.sql` if you want a different name.

## Run order

```
00_setup/00_create_catalog.sql      ← one-time, idempotent
00_setup/01_config.sql              ← session vars (re-run per SQL editor session)
00_setup/03_refresh_orchestrator.sql ← master refresh proc (run once after layers exist)
01_pre_bronze/01_schemas.sql        ← raw_state_street | raw_aladdin | raw_aspen | raw_efront | raw_internal_admin | raw_bloomberg
01_pre_bronze/02_tables_*.sql       ← 6 source-system table files
01_pre_bronze/08_seed.sql           ← deterministic 10-team multi-source seed (~5-10 min on Free Edition)
02_bronze/01_schema.sql             ← bronze schema
02_bronze/02_crosswalk.sql          ← bronze.crosswalk + fn_resolve_*
02_bronze/03_tables.sql             ← t_<entity> Delta tables
02_bronze/04_views.sql              ← v<entity> with precedence + provenance
02_bronze/05_materialized_views.sql ← mv<entity>, byte-identical to v<entity> (raw has no v/mv split)
02_bronze/06_refresh_procs.sql      ← table-population procs
02_bronze/07_lineage_audit.sql      ← bronze_lineage_audit view
03_silver/01_schema.sql             ← creates 2 schemas: investments + investments_history
03_silver/02_tables.sql             ← t_<entity> across both schemas (18 + 6 = 24 entities)
03_silver/03_views.sql              ← v<entity> (slow path: references upstream v*)
03_silver/04_materialized_views.sql ← mv<entity> (cascading: references bronze.mv*)
03_silver/05_refresh_procs.sql      ← per-entity + master refresh_all() (cross-schema)
03_silver/06_documentation.sql      ← ALTER TABLE … COMMENT for both schemas
04_gold/01_schemas.sql              ← 5 team_pd_* + gold_pd_consolidated schemas
04_gold/02_tables.sql               ← 50 team tables + 3 consolidated tables (53 total)
04_gold/03_views.sql                ← v<entity> per team + 3 consolidated UNIONs (slow path)
04_gold/04_materialized_views.sql   ← mv<entity> per team + 3 consolidated MVs (cascading)
04_gold/05_refresh_procs.sql        ← per-team + per-consolidated refresh_all() procs
05_validate/*.sql                   ← correctness gates (run after deploy + refresh)
06_demos/*.sql                      ← v vs mv vs t pedagogy + freshness/cascade demos
00_setup/02_teardown.sql            ← gated by RUN_TEARDOWN; drops all 15 schemas
```

`05_validate/*.sql` runs correctness gates (object inventory, FK integrity, mechanical-derivability, SCD2 chain checks, provenance audit, refresh smoke). `06_demos/*.sql` is the pedagogy harness for views vs MVs vs tables (parity, timing, freshness, refresh cost, concurrency, cascade reach).

`USE CATALOG` runs at the top of every file. SQL editor multi-tab users must re-run `01_config.sql` per tab.

## Programmatic deploy (optional)

Manual SQL editor flow is the primary UX. For batch deploy / CI dry-run / 0.1.7 foundation, the repo ships a thin shell wrapper at `scripts/runbook.sh` and an Asset Bundle stub at `databricks.yml`.

```bash
# One-time setup
cp .env.example .env       # fill in DATABRICKS_HOST, DATABRICKS_TOKEN, DATABRICKS_WAREHOUSE_ID

# Deploy + refresh + validate
pnpm run deploy            # runs every 0.1.1 SQL file in run order
pnpm run refresh           # CALL bronze_silver_gold_refresh()
pnpm run validate          # runs every 05_validate/*.sql gate

# Other targets
pnpm run seed              # just re-runs 01_pre_bronze/08_seed.sql
pnpm run demo              # prints the 06_demos/ reading order
TEARDOWN_CONFIRM=YES pnpm run teardown   # drops all 15 schemas
```

The shell wrapper uses the `/api/2.0/sql/statements` REST endpoint via `curl + jq` (stable across CLI versions). The Asset Bundle YAML is a stub for the 0.1.7 CI smoke runner — the `resources.jobs` section is sketched but commented out.

PLAN.md flags TS/SDK programmatic wrappers as out-of-scope. Bash + bundle YAML are configuration, not wrappers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  raw_state_street    raw_aladdin    raw_aspen    raw_efront                  │
│  raw_internal_admin  raw_bloomberg                                           │ pre-bronze (tables only)
│        │                  │            │            │            │      │   │
│        └──────────────────┴────────────┴────────────┴────────────┴──────┘   │
│                                       │                                      │
│                            bronze.crosswalk                                  │
│                                       │                                      │
│  bronze: vsecurity / ventity / vasset / vportfolio / vposition /             │
│          vtransaction / vcontract / vcollateral / vsecurity_price /          │ bronze (t / v / mv triplet)
│          vportfolio_risk / vportfolio_performance / vrating /                │
│          vbusiness_unit / vfx_rate                                           │
│                                       │                                      │
│  silver (split into 2 schemas — Free Edition 100/schema cap):                │
│                                                                              │
│  investments (current, 17 entities):                                         │
│    facts: vcontract_details_fact / vcontract_summary_fact /                  │
│           vportfolio_analytics_fact / vposition_analytics_fact /             │ silver (t / v / mv triplet)
│           vsecurity_master_fact / vsecurity_price_fact /                     │
│           vtransactions_collateral_lifecycle_fact /                          │
│           vtransactions_collateral_settlement_fact                           │
│    dims:  vsecurity_dim / vsecurity_rating_dim / vcontract_dim /             │
│           vportfolio_dim / ventity_dim / vsecurity_industry_dim /            │
│           vreporting_group_dim / vbusiness_unit_dim / vfx_rate_dim           │
│                                                                              │
│  investments_history (history/corrections, 6 entities):                      │
│    monthend: vposition_monthend_fact / vportfolio_analytics_monthend_fact    │
│    cancels:  vcontract_details_cancels_fact / vposition_cancels_fact /       │
│              vsecurity_price_cancels_fact                                    │
│    bridge:   vincome_bridge                                                  │
│                                       │                                      │
│  gold: team_pd_direct_lending / team_pd_distressed / team_pd_mezzanine /     │
│        team_pd_real_estate_debt / team_pd_specialty_finance                  │ gold (t / v / mv triplet)
│        gold_pd_consolidated (cross-team UNION)                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

5 PD-strategy teams live in gold. 5 non-PD teams (`team_re_core`, `team_re_value_add`, `team_pe_buyout`, `team_infra`, `team_public_equity`) have rows in `vbusiness_unit_dim` + facts but no gold schema in 0.1.1 (see `packages/azure-databricks/PLAN.md` 0.1.2).

## MV-placement scenarios

| Scenario | bronze | silver | gold  | Lesson                                                                                          |
| -------- | ------ | ------ | ----- | ----------------------------------------------------------------------------------------------- |
| **S0**   | `v*`   | `v*`   | `v*`  | Production reality. Likely timeouts on the headline cross-team query.                           |
| **S1**   | `v*`   | `v*`   | `mv*` | Cache final answer per team. Cheap. 5 PD teams = 5 separate MVs.                                |
| **S2**   | `v*`   | `mv*`  | `v*`  | Cross-team reuse — 1 silver MV refresh services all 10 teams. Often the production-recommended. |
| **S3**   | `v*`   | `mv*`  | `mv*` | Cascading. Best query speed, refresh chains.                                                    |
| **S4**   | `mv*`  | `mv*`  | `mv*` | Counter-pattern. Refresh cost spirals.                                                          |

## Demo queries

See `06_demos/`. The full S0–S4 MV-placement matrix lands in a future 0.1.x once the v-vs-mv-vs-t fundamentals demos prove out (current 0.1.1 covers the fundamentals; the placement matrix layers on top).

## Free Edition vs paid

`01_config.sql` defaults are sized for Free Edition compute (~100K total positions, ~5-10 min initial MV materialization). Paid workspace override (commented inline) flips to ~2.5M positions. To switch:

```sql
SET VARIABLE seed_n_securities                = 700;
SET VARIABLE seed_n_entities                  = 200;
SET VARIABLE seed_n_assets                    = 300;
SET VARIABLE seed_n_contracts                 = 500;
SET VARIABLE seed_positions_per_team_per_year = 10000;
SET VARIABLE seed_txns_per_security_per_year  = 20;
```

- [Sign Up for Free Edition | MS Learn](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition)
- [Free Edition Limits | MS Learn](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations))
  - One workspace, one metastore (catalogs OK), serverless compute only, 2X-Small SQL warehouse, daily quota.
- [Free Sign-Up | Databricks](https://login.databricks.com/?dbx_source=docs&intent=CE_SIGN_UP)

## Teardown

```sql
SET VARIABLE RUN_TEARDOWN = TRUE;
-- run 00_setup/02_teardown.sql
```

Drops every schema/object 0.1.0 or 0.1.1 created (15 schemas: 6 raw + bronze + investments + investments_history + 5 gold team + gold_pd_consolidated). Catalog itself is not dropped (shared between versions).

## Verification

Run `05_validate/*.sql` in order — each file emits a `'PASS'` or `'FAIL'` row in the result panel. See `EXECUTION_CHECKLIST.md` for the manual run-through (catalog created, warehouse picked, expected per-file status, expected row counts at default seed).

Quick smoke checks:

- Per-schema object count <100: `SELECT table_schema, count(*) FROM information_schema.tables WHERE table_catalog = 'medallion_demo' GROUP BY 1 ORDER BY 2 DESC;`
- Silver MV materialization completes in minutes (not hours) thanks to cascading.
- Gold MV materialization completes in ~5–10 min total.
- `vposition_analytics_fact` row count ~20–25K at default seed.
- `team_pd_*.vposition_analytics_fact` returns non-zero rows for its bu_code.

## Key contracts

- **Catalog isolation**: `medallion_demo` is shared between 0.1.0 and 0.1.1 (one version active at a time, swap via teardown + re-run). Don't co-deploy with 0.0.1 in the same catalog.
- **View/MV mechanical derivability** (DECISIONS.md #13, supersedes #6 for 0.1.1+): `v<entity>` and `mv<entity>` SELECT bodies are no longer byte-identical, but `mv<entity>` IS derivable from `v<entity>` by `s/v/mv/g` substitution at every upstream FROM/JOIN/IN reference. `v*` reads upstream `v*` (slow path); `mv*` reads upstream `mv*` (fast cascading). Bronze layer is the exception — its v/mv are still byte-identical because raw has no v/mv split.
- **Silver schema split** (DECISIONS.md #12 + #15): 18 current entities (8 SCD2 dims + `vfx_rate_dim` + 9 facts including `vtransaction_fact`) live in `investments`; 6 history/correction entities (monthend, cancels, bridge) live in `investments_history`. Cross-schema FROM clauses are normal — historical reads from current.
- **Schema-qualified two-part names**: every reference is `<schema>.<entity>`, not `<catalog>.<schema>.<entity>`. Catalog is set per session via `USE CATALOG`.
