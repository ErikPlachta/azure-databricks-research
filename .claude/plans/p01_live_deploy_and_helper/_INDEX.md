# p01 — Live deploy + helper-script architecture ✅ CLOSED 2026-05-13

Plan group covering the first end-to-end deploy of `packages/0.1.1/` against a real Databricks Free Edition workspace, and the `scripts/dbx_run.py` + `runbook.sh` helper-library work that emerged from it.

Predecessor: the framework plan tracked in `~/.claude/plans/evalautet-his-repo-and-iridescent-fern.md` (committed as `f46fdb3 feat(0.1.1): base framework`). This plan picks up from "everything is structurally on disk and pushed to GitHub; now actually run it."

**Status (2026-05-13):** research closed. Three iterations executed end-to-end:
1. Initial live deploy + helper library (commits `c143f4d`, `1d06bc3`, `f46fdb3`).
2. Clean redeploy with #17 fix + 1y seed (`f3987a1`).
3. Non-PD gold schemas (0.1.2) + plan-2 close-out (`106917c`).

All deliverables pushed to `origin/main`. End-state catalog has all 10 business units' gold tables populated (4,999 silver positions distributed across teams; 2,301 consolidated). 32/53 gold MVs created (Free Edition metastore 500-cap blocks the remaining 21; deferred). Validate harness passes 6/6 with the rewritten gate 03 skip-tolerance.

## Phases

| Phase                             | Status | Description                                                                                                                                  |
| --------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| [01](01/01_setup_run_20260506.md) | ✅     | Initial live deploy + helper library + clean redeploy + 0.1.2 non-PD schemas. Three iterations across 2026-05-06 through 2026-05-13.        |

## Plan group artifacts

- `01/01_setup_run_20260506.md` — phase 1 plan + state (closed)
- `_RESEARCH/` — empty; live-deploy findings landed in `DECISIONS.md` #16, #17, #18

## Linked artifacts

- `docs/changelog/CHANGELOG_20260506_plan_1_phase_1_base_framework.md` — framework + first deploy
- `docs/changelog/CHANGELOG_20260511_plan_2_phase_1_clean_redeploy.md` — 1y seed + #17 fix
- `docs/changelog/CHANGELOG_20260513_plan_3_0_1_2_non_pd_gold.md` — non-PD schemas + close-out
- `DECISIONS.md` #16 (Free Edition reality), #17 (crosswalk fix — closed), #18 (Spark INSERT bug — workaround)

## Workspace under test

- Host: `dbc-40c058d4-649b.cloud.databricks.com`
- Account: `plachtastar@gmail.com` (Free Edition)
- Catalog: `medallion_demo`
- Warehouse: `Serverless Starter Warehouse` (`f979deaceacd90ed`, 2X-Small)

## Carried forward to future plans (not regressions)

- 21 remaining gold MVs (Free Edition metastore 500-cap; awaits async GC)
- 50 non-PD gold MVs (same constraint; same option-B pattern as plan-2)
- DECISIONS #18 Spark planner bug — file with Databricks if encountered again
- PLAN.md roadmap milestones 0.1.3 → 0.2.0 (unstarted)
