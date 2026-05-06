# azure-databricks — PLAN

Roadmap for the medallion line. `0.0.1` (Kimball) is frozen; all new work lands in the `0.1.x` series.

| Milestone | Scope                                                                                                                                                       |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0.1.0`   | Initial medallion: 6 source schemas, bronze (precedence + provenance), silver `investments` (23 entities, 8 SCD2 dims), gold (5 PD-strategy teams + `gold_pd_consolidated`). 5 MV-placement scenarios × 3 demo queries. **Status:** validated through silver materialization on Free Edition; gold MV materialization hit 100/schema cap + 2.5h+ cascade. Retained as legacy reference. |
| `0.1.1`   | **Schema split + cascading MVs** (per plan p00/14, branch `feat/databricks-0.1.1`). Silver splits to `investments` (17 current) + `investments_history` (6 monthend/cancels/bridge) — under Free Edition 100/schema cap. Mv* bodies reference upstream mv* (silver→bronze, gold→silver) — gold materialization drops 2.5h+ → ~5–10 min. Byte-equality contract relaxed to mechanically-derivable. |
| `0.1.2`   | Non-PD gold schemas: `team_re_core`, `team_re_value_add`, `team_pe_buyout`, `team_infra`, `team_public_equity`. Strengthens cross-team-MV-reuse demo (S2). (Reordered from prior 0.1.1.) |
| `0.1.3`   | `_all` historical UNION pattern. 3 silver entities gain `*_all` siblings unioning current + historical (uses the `investments_history` schema introduced in 0.1.1). |
| `0.1.3`   | `_pivot` cross-tab pattern. 2-3 silver entities gain `*_pivot_*` siblings.                                                                                  |
| `0.1.4`   | MV `SCHEDULE` clauses for production refresh. Removes manual-trigger demo posture.                                                                          |
| `0.1.5`   | Bloomberg security pricing layer. Bronze precedence rule update for `vsecurity_price` (state_street vs bloomberg).                                          |
| `0.1.6`   | PBIP fixture coupled-landing — repoint `fixtures/azure-databricks.pbip` from 0.0.1 schemas to 0.1.0's `investments` + `team_pd_*` + `gold_pd_consolidated`. |
| `0.1.7`   | CI smoke runner — automated end-to-end run on a paid Databricks workspace via Databricks CLI / REST.                                                        |
| `0.1.8`   | Streaming-table option for bronze (real-time-ish ingestion) — alternative to batch refresh procs.                                                           |
| `0.2.0`   | Real eFront schema integration if user supplies authoritative shapes. Removes industry-standard inferences flagged in DECISIONS.md.                         |

## Deferred / open questions

- **Multi-catalog deploy automation** — currently catalog name is a session var; deploying to a new catalog requires re-running setup. CLI/Terraform deployment helper would let users spin up isolated catalogs per branch/PR.
- **Refresh proc vs MV split** — 0.1.0 documents the operational distinction but the demo gradient groups them. A 0.1.4 follow-on could add a "table-refresh" scenario alongside the MV scenarios.
- **Free Edition compute budget** — bronze MV initial materialization is the heavy phase (~5-10 min). Smaller `seed_n_*` defaults already chosen but worth revisiting if Free Edition users hit quota.

## Out-of-scope (this package)

- TS wrappers / programmatic SDK clients — separate package if needed.
- PowerBI semantic model consumption — that's `pbi-metadata-capture` and PBIP fixtures.
- Cost-modelling automation — out of scope.
