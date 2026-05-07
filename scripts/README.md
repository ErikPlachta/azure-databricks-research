# `scripts/` — execution helpers

Two-layer architecture so we don't write `curl` + `jq` incantations for every Bash call:

```
runbook.sh   ←  thin dispatcher: high-level commands, runbook order
   │
   ▼
dbx_run.py   ←  engine: SQL submission + compound-block wrapping + polling
   │
   ▼
curl         ←  REST → Databricks Statement Execution API
```

## `dbx_run.py` — engine

Submits SQL files (or inline SQL) to the Databricks SQL warehouse. Wraps each file in a `BEGIN..END;` compound block so all statements (including `DECLARE`s) share one Spark SQL Scripting scope per submission. Long-running statements are handled by polling (4 s cadence) until terminal.

```bash
# Run files in order, stop on first failure
DATABRICKS_HOST=… DATABRICKS_TOKEN=… DATABRICKS_WAREHOUSE_ID=… \
    python3 scripts/dbx_run.py file1.sql file2.sql

# Ad-hoc SQL
python3 scripts/dbx_run.py --inline 'SELECT current_catalog()'

# Don't stop on failure
python3 scripts/dbx_run.py --continue file1.sql file2.sql

# Submit a file as-is (no auto BEGIN..END wrap — for files with their own compound block)
python3 scripts/dbx_run.py --no-wrap file.sql
```

Backend uses `subprocess + curl` rather than Python's `urllib`. Reason: macOS/Zscaler corp environments often have a self-signed root in Keychain that the system `curl` trusts but Python's bundled CAs don't, so urllib fails with `CERTIFICATE_VERIFY_FAILED`.

## `runbook.sh` — dispatcher

Orchestrates higher-level operations. Defines the runbook file order in one place; delegates submission to `dbx_run.py`.

```bash
bash scripts/runbook.sh deploy        # full 0.1.1 deploy in dependency order
bash scripts/runbook.sh seed          # re-seed only
bash scripts/runbook.sh refresh       # CALL bronze_silver_gold_refresh()
bash scripts/runbook.sh validate      # 05_validate/*.sql gates
bash scripts/runbook.sh demo          # print 06_demos/ reading order
bash scripts/runbook.sh query 'SELECT current_catalog()'

# Destructive — gated:
TEARDOWN_CONFIRM=YES bash scripts/runbook.sh teardown   # drop all 15 schemas (catalog kept)
NUKE_CONFIRM=YES bash scripts/runbook.sh nuke           # DROP CATALOG ... CASCADE
```

`pnpm run <subcommand>` is wired through `package.json`.

## Auth

Three required env vars:

```bash
DATABRICKS_HOST=adb-…azuredatabricks.net          # or dbc-….cloud.databricks.com
DATABRICKS_TOKEN=dapi…                             # PAT
DATABRICKS_WAREHOUSE_ID=…                          # SQL warehouse id (from Connection details)
```

Loaded from any of (in priority order):

1. Process env (e.g. exported via `~/.claude/load-secrets.sh` from macOS Keychain).
2. `.env` at repo root (auto-sourced by `runbook.sh`; git-ignored).
3. `.env.example` shows the format.

## Adding new commands

Edit `runbook.sh` — add a `cmd_<name>` function and a `case` arm. Use `run …` (which expands to `python3 scripts/dbx_run.py …`) for SQL submission. Keep file orderings inside `runbook.sh` — `dbx_run.py` should stay free of project-specific paths.

For ad-hoc SQL embedded in a subcommand, use `run --inline "BEGIN … END;"` (compound) or `run --inline 'SELECT …'` (single statement).

## Adding new SQL files

Append to `deploy_files` (and/or `validate_files`) in `runbook.sh`. Files don't need to declare their own catalog/session vars — but if they reference vars (like `seed_n_securities`), declare them inside the same file (the compound-block wrapping makes each file self-contained for its own scope).

## What `dbx_run.py` does NOT do

- No retry on transient failures. Re-run the file (most DDL is idempotent via `IF NOT EXISTS` / `OR REPLACE`).
- No multi-warehouse support. One `DATABRICKS_WAREHOUSE_ID` per session.
- No bundle deploy / job orchestration. That's `databricks bundle` territory (planned for 0.1.7).
- No transaction. Each file's `BEGIN..END` is one Spark SQL script — atomicity is per-statement, not per-file.

## Future additions (deferred)

- Streaming results for long-running SELECTs (currently buffered).
- Cost telemetry pull from `system.query.history` after long ops.
- Optional Asset Bundle deploy path (when 0.1.7 lands).
