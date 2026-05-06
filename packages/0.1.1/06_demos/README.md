# 0.1.1 — `06_demos/`

Pedagogy harness for views vs materialized views vs tables. Each file is a self-contained teaching artifact; run in order in a Databricks SQL editor and read the result panel + the file's docstring.

Pre-req: full deploy + table population (see `EXECUTION_CHECKLIST.md`). Demos assume `medallion_demo` catalog with non-empty bronze/silver/gold tables and freshly refreshed MVs.

## Reading order

```
01_what_is_a_view.sql            ← view = stored query; nothing materialized
02_what_is_an_mv.sql             ← MV = view + cached results; REFRESH semantics
03_what_is_a_table.sql           ← table = explicit INSERT-driven storage
04_parity_demo.sql               ← v/mv/t return the same rows after refresh
05_timing_demo.sql               ← cold cache vs warm cache vs cached MV
06_freshness_demo.sql            ← what each artifact sees when raw mutates
07_refresh_cost_demo.sql         ← event_log() and refresh strategy choice
08_concurrency_demo.sql          ← read v while mv refreshes (multi-tab demo)
09_cascade_demo.sql              ← Decision #13 made visible: bronze→silver→gold mv refresh
99_adhoc_playground.sql          ← scratch space for analyst-style queries
```

## Pedagogical arc

01-03 establish the three artifact types in isolation. 04 confirms they agree on results. 05-09 explore the operational tradeoffs:

- **05 (timing)** — When are MVs/tables faster than views? Counter-cases?
- **06 (freshness)** — Why is staleness the price you pay for MV/table speed?
- **07 (cost)** — Where do MV refresh costs show up, and what strategies does Databricks pick?
- **08 (concurrency)** — What happens to readers when an MV refreshes?
- **09 (cascade)** — Why did Decision #13's relaxation cut gold materialization 2.5h+ → ~5–10 min?

99 is open-ended — copy-paste analyst queries to feel out the data.

## Free Edition vs paid

Demos use Free Edition seed defaults (~100K positions). Timing differences are smaller multiples than what you'd see at paid scale (~2.5M positions). Each timing demo file documents the paid-scale expectation in a comment.

## What to watch for

In Databricks SQL editor, the result-panel footer shows query duration. Use this for the timing demos (05, 09). For deep MV cost telemetry, demo 07 introduces `event_log()` and `system.query.history`.

## Reference

Background reading on the artifact types and tradeoffs: `DECISIONS.md` #5 (tables vs MVs operational profile), #6 (byte-equality for 0.1.0), #13 (cascading-MV relaxation for 0.1.1+). Also: 0.0.1's pedagogical demos in `packages/0.0.1/08_mv_performance_demo.sql`, `11_advanced_mv_performance_demo.sql`, `14_consumer_perf_demo.sql` use a Kimball model rather than medallion but the structural lessons port directly.
