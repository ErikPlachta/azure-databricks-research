# Azure Databricks Resources In Use

What this project actually consumes from a Databricks workspace. The default target is **Databricks Free Edition** (multi-cloud, includes Azure-backed workspaces); paid Azure Databricks works the same. For Free vs paid limits, see [free-vs-paid.md](free-vs-paid.md). For term definitions, see [glossary.md](glossary.md).

## At a glance

| Resource | What we use | Required? |
| --- | --- | --- |
| Workspace | Any Databricks workspace (Free Edition is fine) | Yes |
| Unity Catalog | Catalogs `medallion_demo` (active) and `workspace` (legacy) | Yes |
| SQL warehouse | One serverless SQL warehouse | Yes |
| Delta Lake | Underlying storage for every table/view/MV | Yes (default) |
| Personal Access Token | Auth for the helper scripts | Only for scripted deploys |
| Asset Bundle | `databricks.yml` stub for future CI | No (0.1.7+) |

## Workspace

Any Databricks workspace works. The project is developed and tested against Databricks Free Edition (`dbc-*.cloud.databricks.com`); the same SQL runs unchanged on a paid Azure workspace (`adb-*.azuredatabricks.net`).

You don't need admin rights — you need:
- Permission to create catalogs (or have one pre-created and named in `01_config.sql`)
- Permission to use a SQL warehouse
- A PAT for scripted deploys (or you can paste SQL into the SQL editor manually)

## Unity Catalog

Two catalogs, one per project version:

| Catalog | Schemas | Purpose |
| --- | --- | --- |
| `workspace` | `bridge`, `dim`, `fact`, `mart` | Legacy 0.0.1 Kimball model. Frozen; consumed by `fixtures/azure-databricks.pbip`. |
| `medallion_demo` | 15 schemas (see below) | Active 0.1.x medallion lake. |

The 15 schemas in `medallion_demo`:
- 6 pre-bronze: `raw_state_street`, `raw_aladdin`, `raw_aspen`, `raw_efront`, `raw_internal_admin`, `raw_bloomberg`
- 1 bronze: `bronze`
- 2 silver: `investments`, `investments_history`
- 6 gold: `team_pd_direct_lending`, `team_pd_distressed`, `team_pd_mezzanine`, `team_pd_real_estate_debt`, `team_pd_specialty_finance`, `gold_pd_consolidated`

The catalog is created by [`packages/0.1.1/00_setup/00_create_catalog.sql`](../packages/0.1.1/00_setup/00_create_catalog.sql) (one-time, idempotent). Every subsequent SQL file calls `USE CATALOG medallion_demo` at the top.

**What we don't use here:** Unity Catalog *volumes* (file storage), *external locations* (cloud-storage mounts), *external tables*. Everything is a managed Delta table inside the catalog. Volumes/external locations are how you'd hook up real source-system landings; this project simulates them with seeded raw schemas instead.

## Compute — SQL warehouse

One serverless SQL warehouse. On Free Edition that's the **2X-Small Serverless Starter**; paid workspaces can use any size.

You set the warehouse via env var (or `01_config.sql`):
```bash
DATABRICKS_WAREHOUSE_ID=<id from Connection details panel>
```

**Why SQL warehouse and not a job cluster?** Every artifact in this project is SQL — DDL, DML, stored procedures, materialized views. SQL warehouse is the right compute for that workload. No notebook tasks, no Spark jobs, no DLT pipelines authored directly (DLT pipelines exist *under* every materialized view, but we don't author them ourselves).

## Storage — Delta Lake

Default for everything. Each `t_<entity>` table is a managed Delta table; views compile to Delta query plans; MVs cache results in Delta-backed tables.

Delta features the project uses explicitly:
- **Liquid clustering** on gold facts — `(date_col, portfolio_sk)` for query pruning
- **Delta Lake transaction log** — implicit, gives us atomic refreshes
- **`CREATE OR REPLACE`** — idempotent re-deploys of every artifact

Features the project does not use (yet): Change Data Feed, row tracking, deletion vectors, time travel queries.

## Auth — PAT via env vars

The scripted deploy path uses a Personal Access Token. Three env vars:

```bash
DATABRICKS_HOST=adb-…azuredatabricks.net          # or dbc-….cloud.databricks.com
DATABRICKS_TOKEN=dapi…                             # PAT
DATABRICKS_WAREHOUSE_ID=…                          # SQL warehouse id
```

Loaded from any of (in priority order):
1. Process env (e.g. `~/.claude/load-secrets.sh` from macOS Keychain)
2. `.env` at repo root (auto-sourced by `runbook.sh`; git-ignored)
3. Manual export in your shell

If you only use the SQL editor, you don't need any of this — the editor handles auth implicitly.

## Helper scripts

Two-layer architecture under [`scripts/`](../scripts/):

```
scripts/runbook.sh     ← thin dispatcher (high-level commands, runbook order)
   │
   ▼
scripts/dbx_run.py     ← engine (SQL submission + compound-block wrapping + polling)
   │
   ▼
curl                   ← REST → /api/2.0/sql/statements
```

**`runbook.sh`** — wraps common tasks (`deploy`, `seed`, `refresh`, `validate`, `demo`, `query`, `teardown`, `nuke`). Wired through `package.json` so `pnpm run deploy` works.

**`dbx_run.py`** — submits SQL files to the Statement Execution API. Wraps each file in a `BEGIN..END;` Spark SQL Scripting compound block so `DECLARE`s share scope across statements. Uses `subprocess + curl` rather than Python's `urllib` because corp Zscaler environments often have a self-signed root that the system `curl` trusts but Python doesn't.

Full reference in [`scripts/README.md`](../scripts/README.md).

## Asset Bundle (stub for now)

[`databricks.yml`](../databricks.yml) is a stub for the 0.1.7 CI smoke runner. It declares workspace + warehouse variables; the `resources.jobs` section is sketched but commented out. Not load-bearing today — useful as a foundation if you want to wire up automated deploys.

## What we explicitly do NOT use

Documenting the omissions because they're informative — they tell you what the demo is and isn't:

| Resource | Why not |
| --- | --- |
| **ADLS Gen2 / S3 / GCS direct mounts** | Source data is seeded synthetically into raw schemas. Real ingestion would replace the seed. |
| **External tables / external locations** | Same — no cloud-storage paths to point to. |
| **Unity Catalog volumes** | No file workloads (no PDFs, parquet drops, ML artifacts). All data is in tables. |
| **Job clusters / general-purpose clusters** | All work is SQL → SQL warehouse is the right compute. |
| **DLT pipelines (authored)** | MVs are DLT under the hood, but we don't write `.dlt` files. |
| **Notebooks** | Every artifact is a `.sql` file. Repeatability and PR review beat notebooks here. |
| **Workflows / Jobs** | Manual run order via `runbook.sh`. Job orchestration is 0.1.7+. |
| **Terraform / Bicep / ARM** | Not used. Asset Bundle is the planned IaC path. |
| **MLflow, Vector Search, AI/BI Genie** | Out of scope — this is a structured-data lakehouse demo. |
| **Service principal auth** | PAT is fine for solo Free-Edition development. SP auth is the recommended pattern for paid/CI. |

## Connection cheatsheet

```bash
# 1. Sign into Databricks (Free Edition signup linked in RESOURCES.md)
# 2. Pick a SQL warehouse (Free Edition: serverless 2X-Small starter)
# 3. Generate a PAT: User Settings → Developer → Access Tokens
# 4. Note the warehouse ID from Connection details
# 5. Wire it up:
cp .env.example .env
# edit .env: DATABRICKS_HOST, DATABRICKS_TOKEN, DATABRICKS_WAREHOUSE_ID
# 6. Deploy:
pnpm run deploy
pnpm run validate
```

End-to-end deploy time on Free Edition: **~7+ hours** wall-clock (MV cold-start dominates — see [free-vs-paid.md § MV cold-start](free-vs-paid.md#mv-cold-start)). On paid, much faster.
