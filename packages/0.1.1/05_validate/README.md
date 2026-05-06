# 0.1.1 — `05_validate/`

Correctness gates for the medallion deploy. Run after `04_gold/` lands and `bronze_silver_gold_refresh()` populates the tables. Each file emits a `'PASS'` or `'FAIL'` status row in the result panel; failures should stop the runbook.

## Run order

```
01_object_inventory.sql        ← counts per schema, confirms 15 schemas, all <100
02_fk_integrity.sql            ← orphan-key checks across bronze/silver/gold
03_view_mv_derivability.sql    ← row-count + key-sum parity between v* and mv*
04_scd2_integrity.sql          ← chain overlap/gap detection on SCD2 dims
05_provenance_audit.sql        ← bronze_lineage_audit invocation + thresholds
06_refresh_smoke.sql           ← end-to-end orchestrator timing capture
```

## What each gate proves

| File | Catches |
| ---- | ------- |
| `01_object_inventory` | Free Edition per-schema 100-cap regression; missing/extra schemas; missing artifact triplets. |
| `02_fk_integrity` | Orphan dim_sks in facts; broken enterprise_key resolution; missing team membership. |
| `03_view_mv_derivability` | v*/mv* divergence (proxy for Decision #13 mechanical-derivability violation). |
| `04_scd2_integrity` | Overlapping or gapped effective-date ranges; bad `is_current` flags; broken chain links. |
| `05_provenance_audit` | Source-system data missing or bronze precedence rules misfired. |
| `06_refresh_smoke` | Orchestrator regression; cascading-MV expected timing budget exceeded. |

## Failure triage

If `01` fails → check seed; not all schemas/objects landed.
If `02` fails → bronze crosswalk or silver SCD2 dim resolution is broken; investigate `bronze.crosswalk` or fact temporal-join logic.
If `03` fails → v* and mv* SELECT bodies have drifted; re-run `s/v/mv/g` substitution check by reading both `SHOW CREATE` outputs side-by-side.
If `04` fails → SCD2 chain logic in silver dim views has a bug.
If `05` fails → seed for one source ran zero rows (check `skip_<source>` toggles in `01_config.sql`).
If `06` fails or runs slow → confirm gold MVs refreshed before tables (DECISIONS.md #5 for ops profile).

## Free Edition vs paid

Row-count thresholds in these files default to Free Edition seed sizes. On paid (~10x larger seed) the thresholds remain proportional — they assert *non-zero* rather than *exact* count, so they hold across both.
