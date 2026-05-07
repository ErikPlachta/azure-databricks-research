# p01 — Live deploy + helper-script architecture

Plan group covering the first end-to-end deploy of `packages/0.1.1/` against a real Databricks Free Edition workspace, and the `scripts/dbx_run.py` + `runbook.sh` helper-library work that emerged from it.

Predecessor: the framework plan tracked in `~/.claude/plans/evalautet-his-repo-and-iridescent-fern.md` (committed as `f46fdb3 feat(0.1.1): base framework`). This plan picks up from "everything is structurally on disk and pushed to GitHub; now actually run it."

## Phases

| Phase                         | Status | Description                                                                                                                                                          |
| ----------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [01](01/01_setup_run_20260506.md) | 🔨     | Initial live deploy: connect to workspace, build `dbx_run.py` + refactor `runbook.sh`, deploy bronze + silver, decide gold strategy. Open issue: gold MV time budget. |

## Plan group artifacts

- `01/01_setup_run_20260506.md` — phase 1 plan + state
- `_RESEARCH/` — empty so far; live-deploy findings landed in `DECISIONS.md` #16

## Workspace under test

- Host: `dbc-40c058d4-649b.cloud.databricks.com`
- Account: `plachtastar@gmail.com` (Free Edition)
- Catalog: `medallion_demo`
- Warehouse: `Serverless Starter Warehouse` (`f979deaceacd90ed`, 2X-Small)
