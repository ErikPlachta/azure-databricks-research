# Docs — Design Reference

Beginner-friendly reference for this Azure Databricks medallion-lake project. Start here if you're new to the repo or new to Databricks.

## What this project is, in one paragraph

A pedagogical, runnable simulation of an enterprise data lakehouse for a private-debt fund. It models 6 source systems landing into a 4-tier medallion architecture (pre-bronze → bronze → silver → gold) and uses that stack to answer one empirical question: **where in a multi-tier view stack do materialized views actually pay off?** Everything is deterministic, sized for Databricks Free Edition by default, and runnable end-to-end via SQL.

## Doc map

| Doc | Read when you want to know... |
| --- | --- |
| [architecture.md](architecture.md) | What the 4 tiers are, how data flows, what each schema contains, what the MV-placement experiment is testing |
| [data-domain.md](data-domain.md) | What data we're modeling (entities, events, edge cases), why a private-debt fund, what "deterministic seed" means |
| [glossary.md](glossary.md) | Term definitions — SCD2 vs SCD1/SCD3, view vs MV vs table, surrogate key, crosswalk, provenance, etc. |
| [azure-databricks-resources.md](azure-databricks-resources.md) | Which Databricks/Azure features the project actually uses, how auth/compute/catalogs are wired |
| [free-vs-paid.md](free-vs-paid.md) | What Free Edition allows, where it constrains us, what would change on a paid workspace |
| [RESOURCES.md](RESOURCES.md) | External links — official Databricks docs, signup, reference reading |

## Where the deep dive lives

`docs/` is the curated explanation layer. The full operational and architectural detail lives elsewhere in the repo:

- [`README.md`](../README.md) — top-level repo overview, version table (0.0.1 / 0.1.0 / 0.1.1)
- [`PLAN.md`](../PLAN.md) — roadmap (0.1.2 through 0.2.0)
- [`DECISIONS.md`](../DECISIONS.md) — architectural decisions, append-only with dates and rationale
- [`packages/0.1.1/README.md`](../packages/0.1.1/README.md) — runbook for the active medallion package
- [`packages/0.1.1/EXECUTION_CHECKLIST.md`](../packages/0.1.1/EXECUTION_CHECKLIST.md) — manual deploy verification
- [`scripts/README.md`](../scripts/README.md) — `runbook.sh` + `dbx_run.py` helper docs

## Reading order for a Databricks newcomer

1. [architecture.md](architecture.md) — get the tier model in your head
2. [glossary.md](glossary.md) — skim it; come back when a term shows up
3. [data-domain.md](data-domain.md) — what the rows actually represent
4. [free-vs-paid.md](free-vs-paid.md) — context for why some things look constrained
5. [azure-databricks-resources.md](azure-databricks-resources.md) — when you're ready to deploy
6. [`packages/0.1.1/README.md`](../packages/0.1.1/README.md) — the runbook
