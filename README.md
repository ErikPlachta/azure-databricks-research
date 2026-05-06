# azure-databricks

Databricks SQL artifacts for the tabular-rebuild workspace. Two artifacts ship side-by-side:

| Version | Architecture                                                                  | Catalog          | Use when                                                                                                                                                   |
| ------- | ----------------------------------------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0.0.1` | Single-tier Kimball (`bridge`/`dim`/`fact`/`mart`)                            | `workspace`      | Bridge-Framework POC; SCD2 + Liquid Clustering; ~5M positions / ~280K transactions; consumed by 0.0.x PBIP fixture. Legacy archive — kept untouched.       |
| `0.1.0` | 4-tier medallion (pre-bronze → bronze → silver `investments` → gold per-team) | `medallion_demo` | MV-placement evaluation rig. 6 source schemas, 22 silver entities, 5 PD-strategy team gold schemas, 5 MV-placement scenarios × 3 contrasting demo queries. |

Pick `0.0.1` for the legacy Kimball reference (consumed by `fixtures/azure-databricks.pbip`). Pick `0.1.0` for the medallion-lake simulation built to evaluate where MVs pay off in a multi-source, multi-team analytics stack.

## What "medallion" means

Medallion is the Databricks-popularized lakehouse pattern that organizes data into named tiers, each adding refinement on top of the previous one. Classic three tiers:

- **Bronze** — raw ingested data, minimal transformation (near-copy of source with metadata added)
- **Silver** — cleaned, validated, conformed data (dedup, type-casting, basic joins, business-key resolution)
- **Gold** — business-level aggregates and team/use-case marts (curated for reporting, ML, analytics)

Each tier is a "medal," with later tiers progressively more refined and trustworthy (bronze → silver → gold).

`0.1.0` uses a 4-tier variant:

| Tier         | Schema(s)                                        | Role                                                                                                                                                            |
| ------------ | ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pre-bronze` | `raw_state_street`, `raw_aladdin`, etc.          | Raw landings from each of the 6 source systems. Tables only. No business logic.                                                                                 |
| `bronze`     | `bronze`                                         | Per-entity unification across sources (precedence + provenance). `source_key → enterprise_key` bridging. First level of business logic.                         |
| `silver`     | `investments`                                    | Cleaned, decomposed entities with SCD2 dims, temporal-resolved fact joins, USD currency normalization, cancel-aware aggregates. Second level of business logic. |
| `gold`       | `team_pd_*` (5 schemas) + `gold_pd_consolidated` | Team-specific filters and derivations — the consumer-facing layer. Third level.                                                                                 |

The `pre-bronze` prefix is a project-specific addition modelling the enterprise reality where raw landing tables are clearly distinct from the bronze views built on top of them.

We adopted medallion in `0.1.0` (vs `0.0.1`'s Kimball single-tier) because this package's goal is evaluating MV-placement strategies in a multi-tier view stack — medallion's tier structure is the natural way to layer view-on-view-on-view, which is the painful pattern the demo simulates. The catalog name `medallion_demo` is named after this architecture.

References: [Databricks medallion docs](https://learn.microsoft.com/en-us/azure/databricks/lakehouse/medallion).

## Versions live in separate Unity Catalog catalogs

`0.0.1` lives in `workspace`. `0.1.0` lives in `medallion_demo`. They do not collide and you can keep both indefinitely. Free Edition supports multiple catalogs within its single metastore — the create-catalog prereq lives in `0.1.0/00_setup/00_create_catalog.sql`.

## Clean-room boundary

These SQL artifacts are authored from public Databricks docs and standard data-modelling patterns. No decompiled code; no copied code from TabularEditor, pbi-tools, or AnalysisServices-samples. eFront table shapes are inferred from industry-standard usage where enterprise schemas weren't available — see `DECISIONS.md` for per-table assumptions.

## Quick links

- [`0.1.0/README.md`](0.1.0/README.md) — runbook for the medallion lake (recommended starting point)
- [`PLAN.md`](PLAN.md) — roadmap (0.1.1 through 0.2.0)
- [`DECISIONS.md`](DECISIONS.md) — architectural decisions and assumptions
- [`0.0.1/README.md`](0.0.1/README.md) — legacy Kimball reference
