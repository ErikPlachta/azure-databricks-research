# 0.1.0 — Medallion lake simulation (predecessor reference)

> **Predecessor**. New work lands in `packages/0.1.1/` (silver schema split + cascading MVs + 05_validate/ + 06_demos/). 0.1.0 is retained for the cap-hit reference: its `investments` schema accumulated 100 objects under Free Edition's per-schema cap, motivating the 0.1.1 split. See `DECISIONS.md` #12 + #13 for the migration rationale.

4-tier medallion (pre-bronze → bronze → silver `investments` → gold per-team) for evaluating MV-placement strategies in a multi-source, multi-team analytics stack. Lives in its own Unity Catalog catalog (`medallion_demo`) so it doesn't touch `0.0.1` in `workspace`.

## Prereq — create the catalog (one-time)

```sql
-- Run once. Free Edition: supported. See 00_setup/00_create_catalog.sql.
CREATE CATALOG IF NOT EXISTS medallion_demo
  COMMENT 'azure-databricks 0.1.0 medallion-lake demo';
```

After this, every subsequent SQL file uses `EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;` to scope to `medallion_demo`. Override `catalog_name` in `01_config.sql` if you want a different name.

## Run order

```
00_setup/00_create_catalog.sql      ← one-time, idempotent
00_setup/01_config.sql              ← session vars (re-run per SQL editor session)
01_pre_bronze/01_schemas.sql        ← raw_state_street | raw_aladdin | raw_aspen | raw_efront | raw_internal_admin | raw_bloomberg
01_pre_bronze/02_tables_*.sql       ← 6 source-system table files
01_pre_bronze/08_seed.sql           ← deterministic 10-team multi-source seed (~5-10 min on Free Edition)
02_bronze/01_schema.sql             ← bronze schema
02_bronze/02_crosswalk.sql          ← bronze.crosswalk + fn_resolve_*
02_bronze/03_tables.sql             ← t_<entity> Delta tables
02_bronze/04_views.sql              ← v<entity> with precedence + provenance
02_bronze/05_materialized_views.sql ← mv<entity>, byte-identical to v<entity>
02_bronze/06_refresh_procs.sql      ← table-population procs
02_bronze/07_lineage_audit.sql      ← bronze_lineage_audit view
03_silver/*.sql                     ← investments schema (22 entities)
04_gold/*.sql                       ← 5 team_pd_* + gold_pd_consolidated
05_validate/*.sql                   ← test scenarios + FK + view-MV parity + SCD2 integrity
06_demos/*.sql                      ← 3 demo queries × 5 MV scenarios + ad-hoc playground
```

`USE CATALOG` runs at the top of every file. SQL editor multi-tab users must re-run `01_config.sql` per tab.

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
│  investments (silver, 22 entities, 8 SCD2 dims):                             │
│    facts: vcontract_details_fact / vcontract_summary_fact /                  │
│           vportfolio_analytics_fact / vposition_analytics_fact /             │ silver (t / v / mv triplet)
│           vsecurity_master_fact / vsecurity_price_fact /                     │
│           vtransactions_collateral_*_fact + cancels + monthend siblings      │
│    dims:  vsecurity_dim / vsecurity_rating_dim / vcontract_dim /             │
│           vportfolio_dim / ventity_dim / vsecurity_industry_dim /            │
│           vreporting_group_dim / vbusiness_unit_dim / vfx_rate_dim           │
│    bridge: vincome_bridge                                                    │
│                                       │                                      │
│  gold: team_pd_direct_lending / team_pd_distressed / team_pd_mezzanine /     │
│        team_pd_real_estate_debt / team_pd_specialty_finance                  │ gold (t / v / mv triplet)
│        gold_pd_consolidated (cross-team UNION)                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

5 PD-strategy teams live in gold. 5 non-PD teams (`team_re_core`, `team_re_value_add`, `team_pe_buyout`, `team_infra`, `team_public_equity`) have rows in `vbusiness_unit_dim` + facts but no gold schema in 0.1.0 (see PLAN.md 0.1.1).

## MV-placement scenarios

| Scenario | bronze | silver | gold  | Lesson                                                                                          |
| -------- | ------ | ------ | ----- | ----------------------------------------------------------------------------------------------- |
| **S0**   | `v*`   | `v*`   | `v*`  | Production reality. Likely timeouts on the headline cross-team query.                           |
| **S1**   | `v*`   | `v*`   | `mv*` | Cache final answer per team. Cheap. 5 PD teams = 5 separate MVs.                                |
| **S2**   | `v*`   | `mv*`  | `v*`  | Cross-team reuse — 1 silver MV refresh services all 10 teams. Often the production-recommended. |
| **S3**   | `v*`   | `mv*`  | `mv*` | Cascading. Best query speed, refresh chains.                                                    |
| **S4**   | `mv*`  | `mv*`  | `mv*` | Counter-pattern. Refresh cost spirals.                                                          |

## Demo queries

3 contrasting headlines × 5 scenarios:

- **Query A** (`02_query_a_*.sql`) — cross-team activity report. Expected winner: S2.
- **Query B** (`03_query_b_*.sql`) — heavy single-team concentration analysis. Expected winner: S1.
- **Query C** (`04_query_c_*.sql`) — simple per-team summary. S0 should suffice (counter-example).
- **Summary** (`05_summary_dashboard.sql`) — consolidated comparison.
- **Playground** (`99_adhoc_playground.sql`) — unscored ad-hoc queries representing real analyst workloads.

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

Free Edition limits (per [MS Learn](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations)): one workspace, one metastore (catalogs OK), serverless compute only, 2X-Small SQL warehouse, daily quota.

## Teardown

```sql
SET VARIABLE RUN_TEARDOWN = TRUE;
-- run 00_setup/02_teardown.sql
```

Drops every schema/object 0.1.0 created. Catalog itself is not dropped (likely shared).

## Verification

`05_validate/` checks per layer; expected to PASS after a clean seed:

- `01_test_scenarios.sql` — row counts, smoke tests
- `02_fk_integrity.sql` — orphan keys, broken bridges
- `03_view_mv_parity.sql` — every `v<entity>` and `mv<entity>` return identical row count + identical row-hash
- `04_scd2_integrity.sql` — chain integrity, is_current uniqueness, no gaps

## Key contracts

- **Catalog isolation**: `medallion_demo` is dedicated to 0.1.0. Don't co-deploy with 0.0.1 in the same catalog.
- **View/MV byte equality**: every `v<entity>` and `mv<entity>` SELECT body must stay byte-identical (modulo the CREATE clause). This is permanent — see DECISIONS.md #6.
- **Schema-qualified two-part names**: every reference is `<schema>.<entity>`, not `<catalog>.<schema>.<entity>`. Catalog is set per session via `USE CATALOG`.
