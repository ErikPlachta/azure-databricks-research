# Free Edition vs Paid Databricks

Reference for what Databricks Free Edition allows, where it constrains *this* project, and what would change on a paid workspace. Focus is on the limits we actually hit, not an exhaustive catalog of paid features.

For terminology, see [glossary.md](glossary.md). For what resources the project consumes, see [azure-databricks-resources.md](azure-databricks-resources.md).

## TL;DR

The project is designed to run end-to-end on Free Edition. You give up:
- Speed (~7 hours to fully deploy vs ~30 minutes on paid)
- Some advanced features (job orchestration at scale, multi-node clusters, larger warehouses)
- Multi-concurrent MV refresh (Free caps DLT pipelines at 1 concurrent)

You keep:
- The full Unity Catalog feature set (catalogs, schemas, governance)
- Delta Lake (ACID, time-travel, liquid clustering, CDF)
- All MV / view / table semantics
- All SQL — every line of this project runs unchanged on paid

## What Free Edition gives you

Per the [Free Edition limits page](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations):

| Resource | Free Edition |
| --- | --- |
| Workspaces | 1 |
| Metastore | 1 (multiple catalogs OK) |
| Compute | Serverless only |
| SQL warehouse | 2X-Small Starter |
| All-purpose clusters | None (serverless notebooks are available) |
| DLT pipelines (concurrent) | 1 |
| Daily compute | Capped quota; no overage |
| Cost | $0 |

## Constraints this project hits

These are the limits that actually shaped the design.

### 100 objects per schema

**The constraint:** any single schema is capped at 100 tables/views/MVs.

**Where it bit:** 0.1.0 used a single `investments` schema for silver. With 23 entities × 3 artifacts (t/v/mv) + MV-backing tables = exactly 100. Adding any further entity blocked.

**The workaround:** **silver schema split** — 0.1.1 split into `investments` (current state, 18 entities) and `investments_history` (corrections + monthend, 6 entities). Mirrors the user's enterprise pattern (`investments` + `investments_historical`). Cross-schema FROM clauses are normal in Spark/UC.

**On paid:** same cap exists, but enterprises hit it less because they tend to split by domain anyway. The split is good practice regardless of edition.

See [DECISIONS.md #12](../DECISIONS.md#12-silver-schema-split-investments--investments_history-in-011).

### MV cold-start

**The constraint:** every materialized view is a Delta Live Tables pipeline under the hood. Each MV pays a fixed Spark+DLT bootstrap cost (~5–6 minutes on Free Edition's serverless 2X-Small) before it can run its body.

**Where it bit:** even though the seed is small (~23K rows in the largest fact), MV materialization is dominated by cold-start, not query work.

| Layer | MV count | Time on Free Edition |
| --- | --- | --- |
| Bronze | 14 | ~30 min |
| Silver (cascading) | 24 | ~120 min |
| Gold (cascading) | 53 | ~5 hr |
| **Total deploy** | **91** | **~7 hr** |

**The workaround:** **cascading MVs**. 0.1.0 hit 2.5+ hours just for *gold* because gold MVs read silver views (re-cascading through all upstream views). 0.1.1 changed `mv*` to read upstream `mv*` (the byte-equality contract was relaxed to mechanical derivability). Materialization dropped to ~5–10 minutes once the cascade was warm.

The 7-hour figure above is **first deploy, cold cascade**. Subsequent refreshes are much faster because the upstream MVs already exist.

**On paid:** larger warehouses cut cold-start materially; multi-node clusters can run multiple pipelines in parallel; expected total is closer to ~30 min cold, single-digit minutes warm.

See [DECISIONS.md #13](../DECISIONS.md#13-cascading-mv-bodies--byte-equality-contract-relaxation-011) and [#16](../DECISIONS.md#16-free-edition-deploy-reality-live-findings-2026-05-0607).

### 1 concurrent DLT pipeline

**The constraint:** Free Edition caps DBSQL/DLT at **1 concurrent pipeline**. Every `CREATE OR REPLACE MATERIALIZED VIEW` and every `REFRESH MATERIALIZED VIEW` provisions a pipeline. Submit a second concurrent MV op and Databricks returns `[DLT ERROR CODE: QUOTA_EXCEEDED_EXCEPTION] Limit: 1; used: 2`.

**Implication:** MV creation is **inherently serialized** on Free Edition. No amount of submission-layer parallelism helps.

**The workaround:** `dbx_run.py` polls each MV creation to terminal state before starting the next. Multi-hour deploys are accepted as the cost of Free Edition.

**On paid:** DLT pipeline concurrency scales with workspace tier. Standard tier ≥ 4 concurrent; enterprise scales further.

### Daily compute quota

**The constraint:** Free Edition has a daily compute cap. Bursting past it pauses your warehouse.

**Where it bites:** a full cold deploy + validation + demo run can exhaust the daily quota in a single sitting.

**The workaround:** deploy is **idempotent**. Every artifact uses `CREATE OR REPLACE` or `IF NOT EXISTS`. If quota is hit mid-deploy, re-run the next day from where you left off. The seed is also deterministic, so re-runs don't drift.

**On paid:** no daily quota — pay-per-use serverless or reserved capacity.

### Serverless 2X-Small only

**The constraint:** one warehouse size. Can't scale up for heavy queries.

**Where it bites:** the headline cross-team query (`gold_pd_consolidated.vpd_position_book` UNION-ALL across 5 teams) runs slow under view-mode (S0 scenario). MVs help, but only because they shift the cost off the query path.

**The workaround:** seed sizing — Free Edition default is ~100K total positions (small enough that 2X-Small can chew through any query in seconds once MVs exist). Paid override is ~2.5M.

**On paid:** pick warehouse size by workload — Small for dev, Medium-Large for production.

## What's the same on both

| Feature | Free / Paid |
| --- | --- |
| Unity Catalog (catalogs, schemas, grants, governance) | ✅ Identical |
| Delta Lake (ACID, MERGE, OPTIMIZE, ZORDER, liquid clustering) | ✅ Identical |
| Materialized views, views, tables | ✅ Same syntax, same semantics |
| Stored procedures, UDFs | ✅ Identical |
| SQL warehouse query engine (Photon under the hood) | ✅ Same engine |
| Spark SQL Scripting (`BEGIN..END`, `DECLARE`, control flow) | ✅ Identical |
| SCD2 patterns, CDF, time travel | ✅ Identical |
| Statement Execution API | ✅ Identical |

**The whole point:** every line of SQL in this repo runs unchanged on paid. Only operational characteristics change.

## What you'd add on paid

Things this project doesn't currently use but that paid workspaces unlock:

| Feature | Why you'd want it |
| --- | --- |
| **Larger SQL warehouses** | Faster MV cold-start; faster `S0` view-cascade queries |
| **Multi-node general-purpose clusters** | Notebook-driven exploration, ad-hoc Spark work |
| **Workflows / Jobs** | Scheduled deploys, dependency orchestration, retries |
| **DLT scheduled refresh** | Production-grade MV refresh on cron / event triggers |
| **Photon on dedicated clusters** | Performance isolation from neighboring tenants |
| **Multi-region / DR** | Cross-region replication, failover |
| **Service principal auth** | CI/CD-friendly auth without user PATs |
| **Audit log access** | System tables for compliance/cost tracking |
| **Vector Search, AI/BI Genie, MLflow scaling** | Out of scope here, but available |
| **Higher DLT pipeline concurrency** | Parallelize MV materialization (multi-hour → multi-minute) |
| **Multiple workspaces** | Dev/staging/prod separation |
| **Custom networking, private link** | Locked-down enterprise networking |

## Quick scaling map

If you move this project to a paid workspace and want to push it harder:

```sql
-- packages/0.1.1/00_setup/01_config.sql
-- Free Edition defaults (~100K positions). Override for paid:
SET VARIABLE seed_n_securities                = 700;
SET VARIABLE seed_n_entities                  = 200;
SET VARIABLE seed_n_assets                    = 300;
SET VARIABLE seed_n_contracts                 = 500;
SET VARIABLE seed_positions_per_team_per_year = 10000;
SET VARIABLE seed_txns_per_security_per_year  = 20;
```

Yields ~2.5M positions. Materialization on a Medium warehouse runs in minutes; the headline cross-team query under S0 (all views) becomes feasible to actually time.

## Reference links

- [Sign Up for Free Edition (MS Learn)](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition)
- [Free Edition limitations (MS Learn)](https://learn.microsoft.com/en-us/azure/databricks/getting-started/free-edition-limitations)
- [Free Sign-Up (Databricks)](https://login.databricks.com/?dbx_source=docs&intent=CE_SIGN_UP)
- [Pricing (Azure Databricks)](https://azure.microsoft.com/en-us/pricing/details/databricks/)
- [Workspace tiers (MS Learn)](https://learn.microsoft.com/en-us/azure/databricks/getting-started/concepts#workspace)

For the live deployment findings that produced these numbers, see [DECISIONS.md #16](../DECISIONS.md#16-free-edition-deploy-reality-live-findings-2026-05-0607).
