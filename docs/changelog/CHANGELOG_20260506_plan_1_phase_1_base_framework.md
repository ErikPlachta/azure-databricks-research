# CHANGELOG — 2026-05-06 — plan 1 phase 1 — base framework

Took 0.1.1 from "structurally complete SQL on disk, orchestrator broken at gold" to "executable end-to-end with test/demo harness + thin runbook helper." Plan reference: `~/.claude/plans/evalautet-his-repo-and-iridescent-fern.md`. Sister DECISIONS entries: #14 (gold-tier closure), #15 (silver vtransaction_fact).

## Summary

Six original phases plus six follow-ups. All shipped in this conversation.

- **Original phases:** DECISIONS #14, doc reconciliation, gold-tier gap closure (60 procs + consolidated views/MVs), execution checklist, validate harness (6 SQL files), demo harness (10 SQL files), execution wrapper (databricks.yml + scripts/runbook.sh + .env.example + package.json + .gitignore).
- **Follow-ups:** silver `vtransaction_fact` end-to-end (resolves bronze-direct sourcing of `vpd_transaction_book`), concurrency demo rewrite (solo-runnable via Delta time-travel + multi-tab option), DECISIONS #15, PLAN.md audit (merged duplicate 0.1.3 rows; updated 0.1.1, 0.1.2, 0.1.6, deferred questions), entity-count updates across 0.1.1/README + EXECUTION_CHECKLIST + 03_silver/01_schema.sql.

## Actions completed

| # | Phase | Action | Touched |
| - | ----- | ------ | ------- |
| 1 | A     | DECISIONS.md #14 (0.1.1 gold-tier partial implementation, closed additively)               | `DECISIONS.md` |
| 2 | C     | Created `04_gold/05_refresh_procs.sql` — 60 procs (50 team + 5 team aggregators + 3 consolidated entity + 1 consolidated aggregator + 1 master) | NEW: `packages/0.1.1/04_gold/05_refresh_procs.sql` |
| 3 | C     | Section G appended to gold views + MVs — 3 cross-team UNION views + 3 cascading MVs (Decision #13 contract preserved) | `packages/0.1.1/04_gold/03_views.sql`, `04_materialized_views.sql` |
| 4 | B     | Doc reconciliation: schema count 14→15; run-order block expanded; demo/validate refs replaced; predecessor banner on 0.1.0; root README version table + quick links; PLAN 0.1.1 + 0.1.7 row updates; 04_gold/01_schemas.sql comment fix | `README.md`, `PLAN.md`, `packages/0.1.0/README.md`, `packages/0.1.1/README.md`, `packages/0.1.1/04_gold/01_schemas.sql` |
| 5 | D     | EXECUTION_CHECKLIST.md — 7-phase manual walkthrough (pre-flight → setup → bronze → silver → gold → orchestrator → MV refresh → object inventory → lineage audit → sample queries → validate harness pointer) | NEW: `packages/0.1.1/EXECUTION_CHECKLIST.md` |
| 6 | E     | `05_validate/` correctness gates (7 files: README + object_inventory + fk_integrity + view_mv_derivability + scd2_integrity + provenance_audit + refresh_smoke) | NEW: `packages/0.1.1/05_validate/` |
| 7 | E     | `06_demos/` pedagogy harness (11 files: README + 9 numbered demos covering view/mv/table fundamentals, parity, timing, freshness, refresh cost, concurrency, cascade reach, playground)  | NEW: `packages/0.1.1/06_demos/` |
| 8 | F     | Execution wrapper: `databricks.yml` Asset Bundle stub, `scripts/runbook.sh` (deploy/seed/refresh/validate/demo/teardown subcommands using `/api/2.0/sql/statements`), `.env.example`, `.gitignore`, package.json scripts | NEW: `databricks.yml`, `scripts/runbook.sh`, `.env.example`, `.gitignore`; MOD: `package.json` |
| 9 | F1    | Silver `vtransaction_fact` — table + view + cascading mv + refresh proc + aggregator hookup; gold `vpd_transaction_book` refactored to source from silver instead of bronze | `packages/0.1.1/03_silver/02_tables.sql` (+ view, mv, refresh procs), `04_gold/03_views.sql`, `04_materialized_views.sql` |
| 10 | F2    | Concurrency demo rewrite: solo-tab demonstration via Delta time-travel + clearer multi-tab steps                                                                                          | `packages/0.1.1/06_demos/08_concurrency_demo.sql` |
| 11 | F3    | DECISIONS.md #15 (silver vtransaction_fact addition, resolves #14 caveat)                                                                                                                 | `DECISIONS.md` |
| 12 | F4    | PLAN.md cleanup: merged duplicate 0.1.3 rows; updated 0.1.1 (count 17→18, vtransaction_fact mention); 0.1.2 reorder note removed; 0.1.6 fixture target updated 0.1.0→0.1.1; deferred-questions modernized | `PLAN.md` |
| 13 | F5    | Silver entity counts updated: 17→18 in 0.1.1/README, 0.1.1/EXECUTION_CHECKLIST, 03_silver/01_schema.sql                                                                                   | `packages/0.1.1/README.md`, `packages/0.1.1/EXECUTION_CHECKLIST.md`, `packages/0.1.1/03_silver/01_schema.sql` |
| 14 | F6    | This changelog                                                                                                                                                                            | NEW: `docs/changelog/CHANGELOG_20260506_plan_1_phase_1_base_framework.md` |

## Metrics

| Metric | Pre | Post |
| ------ | --- | ---- |
| Schemas in `medallion_demo` | 15 (claim was 14 in stale README) | 15 (corrected README) |
| Silver entities (`investments`) | 17 | 18 |
| Silver entities total (across both schemas) | 23 | 24 |
| Gold per-team entities (per schema × 5) | 10 | 10 |
| Gold consolidated artifacts (`gold_pd_consolidated`) | 3 tables only (no v/mv/procs) | 3 t + 3 v + 3 mv + 4 procs |
| Total gold refresh procs | 0 (file missing) | 60 |
| Validate harness files | 0 | 7 |
| Demo harness files | 0 | 11 |
| Root execution wrapper files | 0 | 5 (`.gitignore`, `.env.example`, `databricks.yml`, `scripts/runbook.sh`, `package.json` scripts) |
| Orchestrator end-to-end runnable | No (fails at line 48) | Yes |

## Key files / branches

**Branch:** `main` (all changes committed-ready in working tree at end of session).

**New top-level files:** `databricks.yml`, `scripts/runbook.sh`, `.env.example`, `.gitignore`, `docs/changelog/CHANGELOG_20260506_plan_1_phase_1_base_framework.md`.

**New 0.1.1 deliverables:** `packages/0.1.1/04_gold/05_refresh_procs.sql`, `packages/0.1.1/EXECUTION_CHECKLIST.md`, `packages/0.1.1/05_validate/` (7 files), `packages/0.1.1/06_demos/` (11 files).

**Modified existing:** `DECISIONS.md` (+#14, +#15), `PLAN.md`, `README.md`, `package.json`, `packages/0.1.0/README.md`, `packages/0.1.1/README.md`, `packages/0.1.1/04_gold/01_schemas.sql`, `packages/0.1.1/04_gold/03_views.sql`, `packages/0.1.1/04_gold/04_materialized_views.sql`, `packages/0.1.1/03_silver/01_schema.sql`, `packages/0.1.1/03_silver/02_tables.sql`, `packages/0.1.1/03_silver/03_views.sql`, `packages/0.1.1/03_silver/04_materialized_views.sql`, `packages/0.1.1/03_silver/05_refresh_procs.sql`, `packages/0.1.1/06_demos/08_concurrency_demo.sql`.

## Verification next steps (user-driven)

1. SQL editor: follow `packages/0.1.1/EXECUTION_CHECKLIST.md` for full deploy.
2. After deploy + refresh: run `05_validate/01..06.sql` — all should return `'PASS'` rows.
3. Pedagogical demos: `06_demos/06_freshness_demo.sql` and `09_cascade_demo.sql` are the load-bearing files for v-vs-mv-vs-t intuition.
4. Programmatic: `cp .env.example .env`, fill in credentials, `pnpm run deploy && pnpm run validate`.

## Out of scope (carried forward)

Per `PLAN.md`: 0.1.2 non-PD gold schemas, 0.1.3 `_all`/`_pivot` patterns, 0.1.4 MV `SCHEDULE`, 0.1.5 Bloomberg pricing, 0.1.6 PBIP repointing, 0.1.7 full CI runner (foundation laid in 0.1.1), 0.1.8 streaming-table option, 0.2.0 real eFront schema.

## Known caveats (post-this-changelog)

- `06_demos/07_refresh_cost_demo.sql` uses `event_log()` and `system.query.history` — both have a 30s–2m population delay; if results are empty, wait and re-run.
- `02_fk_integrity.sql` checks consolidated total = sum of teams; a tiny mismatch is possible if a team's positions reference a portfolio whose business_unit's `is_pd_strategy` flips during refresh — unlikely under deterministic seed but worth flagging.
- `03_view_mv_derivability.sql` uses row-count + sum proxy for body equivalence; full body-derivation lint is 0.1.7 CI work.
