# CHANGELOG — 2026-05-11 — plan 2 phase 1 — clean redeploy with #17 fix

Closed DECISIONS #17 (cross-system FK crosswalk gap), surfaced and worked around DECISIONS #18 (Spark INSERT-OVERWRITE attribute-ID bug). Clean deploy of 0.1.1 against Free Edition completed in ~6 hours total wall-clock (mostly the 14 + 24 bronze + silver MV cold-start cycles); orchestrator runs clean in 35 min; 5/6 validate gates pass.

Plan reference: `~/.claude/plans/evalautet-his-repo-and-iridescent-fern.md` (overwritten with plan-2 spec).

## Summary

| # | Change | Effect |
| - | ------ | ------ |
| 1 | DECISIONS #17 closed via crosswalk augmentation | `bronze.crosswalk` now carries cross-system FK rows: `('state_street', 'SS_PORT_TEAM_NN', 'EK_PORT_TEAM_NN')` + similar from aladdin. `bronze.fn_resolve_enterprise_key('state_street', 'SS_PORT_TEAM_01')` returns `'EK_PORT_TEAM_01'` (was NULL). |
| 2 | Silver `vportfolio_dim` canonical EK | Replaced per-row `EK_RISK_<date>` with canonical `'EK_' || substr(portfolio_source_key, 4)` → `EK_PORT_TEAM_NN`. Matches the new crosswalk entries so silver dim joins resolve. |
| 3 | DECISIONS #18 worked around | `vsecurity_master_fact` view's bronze.vsecurity LEFT JOIN dropped (Spark INSERT-OVERWRITE attribute-ID collision; multiple rewrites failed). `latest_close_price_*` set to NULL; same data is in `vsecurity_price_fact`. Workaround mirrored in cascading mv. |
| 4 | 1y seed default | `01_config.sql` + `08_seed.sql` `position_start_date` default 5y → 1y. Seed positions drop ~23K → ~5K; downstream MV materialization unchanged in time but table ops faster. |
| 5 | Clean redeploy executed | DROP CATALOG CASCADE + full re-run per plan-2 phases A → E. All bronze + silver + gold tables populated; gold MVs skipped per option B. |

## Acceptance (verified live 2026-05-11)

| Check | Pre-#17 | Post-#17 |
| ----- | ------- | -------- |
| `bronze.fn_resolve_enterprise_key('state_street', 'SS_PORT_TEAM_01')` | NULL | `'EK_PORT_TEAM_01'` ✓ |
| `bronze.vposition.portfolio_enterprise_key` NULL count | 4999 of 4999 | 0 of 4999 ✓ |
| `investments.t_vposition_analytics_fact.portfolio_sk` NULL count | 4999 of 4999 | 0 of 4999 ✓ |
| `investments.t_vposition_analytics_fact.business_unit_sk` NULL count | 4999 of 4999 | 0 of 4999 ✓ |
| Smallest team gold position count | 0 | 351 ✓ |
| `gold_pd_consolidated.t_vpd_position_book` row count = sum of 5 teams | 0 ≠ 0 (trivial) | 2301 = 468+455+494+533+351 ✓ |
| `05_validate/02_fk_integrity.sql` orphan checks | would FAIL | PASS ✓ |

## Validate harness state

| Gate | Status | Notes |
| ---- | ------ | ----- |
| 01_object_inventory | ✓ PASS | |
| 02_fk_integrity | ✓ PASS | The load-bearing assertion for #17 fix |
| 03_view_mv_derivability | ✗ FAIL (expected) | References gold MVs; we skipped MV creation per option B |
| 04_scd2_integrity | ✓ PASS | |
| 05_provenance_audit | ✓ PASS | |
| 06_refresh_smoke | ✓ PASS | (33 min — re-runs full orchestrator) |

Follow-up: gate 03 should detect skipped-MV state and PASS-or-SKIP rather than FAIL.

## Metrics

| Metric | Pre-plan-2 | Post-plan-2 |
| ------ | ---------- | ----------- |
| Seed positions (1y window) | 23K (5y) | 4,999 |
| Seed transactions | 18K | 6,128 |
| Crosswalk rows | 111K | 27.9K |
| Cross-system FK entries (state_street SS_PORT_*) | 0 | 10 |
| Distinct portfolio EKs in bronze.vposition | 0 | 10 |
| Gold team-fact row counts | 0 each | 351–533 each |
| Gold consolidated position_book | 0 | 2,301 |
| Gold consolidated transaction_book | 0 | 3,238 |
| Gold consolidated contract_book | 0 | 1,152 |

## Bugs surfaced this round

| # | File | Symptom | Fix |
| - | ---- | ------- | --- |
| #17 | `02_bronze/02_crosswalk.sql` + `03_silver/03_views.sql` `vportfolio_dim` | Cross-system FK resolution returned NULL → all gold empty | Crosswalk MERGE UNION arms + canonical EK derivation in silver dim |
| #18 | `03_silver/03_views.sql` + `04_materialized_views.sql` `vsecurity_master_fact` | Spark `Cannot find column index for attribute 'bronze_loaded_at#NNNNN'` during INSERT OVERWRITE | Drop bronze.vsecurity LEFT JOIN; set `latest_close_price_*` and `bronze_loaded_at` to NULL. View only joins to its primary dim now. |
| (re-confirm) | (already-fixed) | `vincome_bridge` LEFT JOIN → JOIN | (Already in c143f4d / 1d06bc3) |

## Key files

**Modified:**
- `packages/0.1.1/02_bronze/02_crosswalk.sql` — UNION arms for cross-system FKs
- `packages/0.1.1/03_silver/03_views.sql` — `vportfolio_dim` canonical EK; `vsecurity_master_fact` simplified
- `packages/0.1.1/03_silver/04_materialized_views.sql` — same edits in cascading mv bodies
- `packages/0.1.1/00_setup/01_config.sql` — 1y default
- `packages/0.1.1/01_pre_bronze/08_seed.sql` — 1y default (the file declares its own default; needed for the new helper architecture where each file is its own compound block)
- `DECISIONS.md` — #17 marked closed; #18 added
- `.claude/plans/p01_live_deploy_and_helper/01/01_setup_run_20260506.md` — status updated

**New:** `docs/changelog/CHANGELOG_20260511_plan_2_phase_1_clean_redeploy.md` (this file).

## What's deferred

- **53 gold MVs**: skipped this round per option B. Background-create on demand via `pnpm run query 'CREATE OR REPLACE MATERIALIZED VIEW …'` or by running `04_gold/04_materialized_views.sql`. Each MV ~5 min on Free Edition.
- **Gate 03 fix**: should handle the skipped-MV state gracefully.
- **DECISIONS #18 root cause**: workaround in place; the underlying Spark planner bug worth a Databricks bug report if we keep hitting it.
- **Token rotation**: Free Edition demo account, low blast radius. Defer.

## Verification commands

```bash
# Reproduce the gold population check
pnpm run query 'SELECT count(*) FROM medallion_demo.gold_pd_consolidated.t_vpd_position_book'
# Expected: 2301

# Reproduce the consolidated = sum of teams check
pnpm run query "
SELECT
  (SELECT count(*) FROM medallion_demo.gold_pd_consolidated.t_vpd_position_book) -
  ((SELECT count(*) FROM medallion_demo.team_pd_direct_lending.t_vposition_analytics_fact) +
   (SELECT count(*) FROM medallion_demo.team_pd_distressed.t_vposition_analytics_fact) +
   (SELECT count(*) FROM medallion_demo.team_pd_mezzanine.t_vposition_analytics_fact) +
   (SELECT count(*) FROM medallion_demo.team_pd_real_estate_debt.t_vposition_analytics_fact) +
   (SELECT count(*) FROM medallion_demo.team_pd_specialty_finance.t_vposition_analytics_fact))
"
# Expected: 0
```
