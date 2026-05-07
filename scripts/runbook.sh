#!/usr/bin/env bash
# ============================================================================
# scripts/runbook.sh
# High-level command dispatcher for the 0.1.1 medallion stack. Thin wrapper
# over scripts/dbx_run.py — keeps the runbook order and command names here,
# delegates SQL submission to the Python engine.
#
# Subcommands:
#   deploy     — run every 0.1.1 SQL file in run order (excludes teardown)
#   seed       — re-run 01_pre_bronze/08_seed.sql only
#   refresh    — CALL bronze_silver_gold_refresh()
#   validate   — run every 05_validate/*.sql gate
#   demo       — print 06_demos/ reading order (interactive)
#   teardown   — run 02_teardown.sql with RUN_TEARDOWN=TRUE (gated)
#   nuke       — DROP CATALOG ... CASCADE (more aggressive than teardown)
#   query      — ad-hoc SQL: ./runbook.sh query 'SELECT current_catalog()'
#
# Auth: needs DATABRICKS_HOST + DATABRICKS_TOKEN + DATABRICKS_WAREHOUSE_ID
# in env (or .env).
# ============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_ROOT="$REPO_ROOT/packages/0.1.1"
DBX_RUN="$REPO_ROOT/scripts/dbx_run.py"

# Load .env if present
if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
    set +a
fi

: "${DATABRICKS_HOST:?DATABRICKS_HOST not set; cp .env.example .env or export from keychain}"
: "${DATABRICKS_TOKEN:?DATABRICKS_TOKEN not set}"
: "${DATABRICKS_WAREHOUSE_ID:?DATABRICKS_WAREHOUSE_ID not set}"
export DATABRICKS_HOST DATABRICKS_TOKEN DATABRICKS_WAREHOUSE_ID

run() { python3 "$DBX_RUN" "$@"; }

# ---------------------------------------------------------------------------
# Runbook order — single source of truth. Keep this list aligned with
# packages/0.1.1/EXECUTION_CHECKLIST.md.
# ---------------------------------------------------------------------------

deploy_files=(
    "$PKG_ROOT/00_setup/00_create_catalog.sql"
    "$PKG_ROOT/00_setup/01_config.sql"
    "$PKG_ROOT/01_pre_bronze/01_schemas.sql"
    "$PKG_ROOT/01_pre_bronze/02_tables_state_street.sql"
    "$PKG_ROOT/01_pre_bronze/03_tables_aladdin.sql"
    "$PKG_ROOT/01_pre_bronze/04_tables_aspen.sql"
    "$PKG_ROOT/01_pre_bronze/05_tables_efront.sql"
    "$PKG_ROOT/01_pre_bronze/06_tables_internal_admin.sql"
    "$PKG_ROOT/01_pre_bronze/07_tables_bloomberg.sql"
    "$PKG_ROOT/01_pre_bronze/08_seed.sql"
    "$PKG_ROOT/02_bronze/01_schema.sql"
    "$PKG_ROOT/02_bronze/02_crosswalk.sql"
    "$PKG_ROOT/02_bronze/03_tables.sql"
    "$PKG_ROOT/02_bronze/04_views.sql"
    "$PKG_ROOT/02_bronze/05_materialized_views.sql"
    "$PKG_ROOT/02_bronze/06_refresh_procs.sql"
    "$PKG_ROOT/02_bronze/07_lineage_audit.sql"
    "$PKG_ROOT/03_silver/01_schema.sql"
    "$PKG_ROOT/03_silver/02_tables.sql"
    "$PKG_ROOT/03_silver/03_views.sql"
    "$PKG_ROOT/03_silver/04_materialized_views.sql"
    "$PKG_ROOT/03_silver/05_refresh_procs.sql"
    "$PKG_ROOT/03_silver/06_documentation.sql"
    "$PKG_ROOT/04_gold/01_schemas.sql"
    "$PKG_ROOT/04_gold/02_tables.sql"
    "$PKG_ROOT/04_gold/03_views.sql"
    "$PKG_ROOT/04_gold/04_materialized_views.sql"
    "$PKG_ROOT/04_gold/05_refresh_procs.sql"
    "$PKG_ROOT/00_setup/03_refresh_orchestrator.sql"
)

validate_files=(
    "$PKG_ROOT/05_validate/01_object_inventory.sql"
    "$PKG_ROOT/05_validate/02_fk_integrity.sql"
    "$PKG_ROOT/05_validate/03_view_mv_derivability.sql"
    "$PKG_ROOT/05_validate/04_scd2_integrity.sql"
    "$PKG_ROOT/05_validate/05_provenance_audit.sql"
    "$PKG_ROOT/05_validate/06_refresh_smoke.sql"
)

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_deploy() {
    echo "═══ deploy: 0.1.1 medallion runbook ═══"
    run "${deploy_files[@]}"
    echo "═══ deploy complete. Next: \`pnpm run refresh\` to populate t_ tables. ═══"
}

cmd_seed() {
    run "$PKG_ROOT/00_setup/01_config.sql" "$PKG_ROOT/01_pre_bronze/08_seed.sql"
}

cmd_refresh() {
    run --inline "BEGIN
DECLARE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;
CALL bronze_silver_gold_refresh();
END;"
}

cmd_validate() {
    echo "═══ validate: running 05_validate/ gates ═══"
    run "${validate_files[@]}"
    echo "═══ validate complete ═══"
}

cmd_demo() {
    cat <<'EOF'
═══ 06_demos/ reading order ═══
Run each in a SQL editor (or via `query` subcommand). Pedagogical files —
read the docstring + result panel together.

  01_what_is_a_view.sql       — view = stored query
  02_what_is_an_mv.sql        — MV = view + cached results; REFRESH demo
  03_what_is_a_table.sql      — table = explicit INSERT-driven population
  04_parity_demo.sql          — v/mv/t agree after refresh
  05_timing_demo.sql          — cold/warm cache + materialized comparison
  06_freshness_demo.sql       — what each artifact sees when raw mutates
  07_refresh_cost_demo.sql    — event_log() per-MV cost telemetry
  08_concurrency_demo.sql     — solo via Delta time-travel + multi-tab option
  09_cascade_demo.sql         — Decision #13 made visible (2.5h+ → 5–10 min)
  99_adhoc_playground.sql     — open-ended analyst queries

See packages/0.1.1/06_demos/README.md for the full pedagogical arc.
EOF
}

cmd_teardown() {
    if [[ "${TEARDOWN_CONFIRM:-NO}" != "YES" ]]; then
        echo "✗ teardown blocked. Set TEARDOWN_CONFIRM=YES to actually run." >&2
        echo "  This will drop all 15 schemas in the medallion_demo catalog." >&2
        exit 2
    fi
    run --inline "BEGIN
DECLARE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;
DROP SCHEMA IF EXISTS team_pd_direct_lending     CASCADE;
DROP SCHEMA IF EXISTS team_pd_distressed         CASCADE;
DROP SCHEMA IF EXISTS team_pd_mezzanine          CASCADE;
DROP SCHEMA IF EXISTS team_pd_real_estate_debt   CASCADE;
DROP SCHEMA IF EXISTS team_pd_specialty_finance  CASCADE;
DROP SCHEMA IF EXISTS gold_pd_consolidated       CASCADE;
DROP SCHEMA IF EXISTS investments                CASCADE;
DROP SCHEMA IF EXISTS investments_history        CASCADE;
DROP SCHEMA IF EXISTS bronze                     CASCADE;
DROP SCHEMA IF EXISTS raw_state_street           CASCADE;
DROP SCHEMA IF EXISTS raw_aladdin                CASCADE;
DROP SCHEMA IF EXISTS raw_aspen                  CASCADE;
DROP SCHEMA IF EXISTS raw_efront                 CASCADE;
DROP SCHEMA IF EXISTS raw_internal_admin         CASCADE;
DROP SCHEMA IF EXISTS raw_bloomberg              CASCADE;
SELECT 'teardown complete' AS status;
END;"
}

cmd_nuke() {
    if [[ "${NUKE_CONFIRM:-NO}" != "YES" ]]; then
        echo "✗ nuke blocked. Set NUKE_CONFIRM=YES to actually run." >&2
        echo "  This drops the medallion_demo catalog itself (CASCADE)." >&2
        echo "  Re-run 00_setup/00_create_catalog.sql afterward." >&2
        exit 2
    fi
    run --inline "DROP CATALOG IF EXISTS medallion_demo CASCADE"
}

cmd_query() {
    [[ $# -eq 0 ]] && { echo "usage: $0 query 'SQL HERE'" >&2; exit 2; }
    run --inline "$*"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
sub="${1:-}"; shift || true
case "$sub" in
    deploy)   cmd_deploy "$@" ;;
    seed)     cmd_seed "$@" ;;
    refresh)  cmd_refresh "$@" ;;
    validate) cmd_validate "$@" ;;
    demo)     cmd_demo "$@" ;;
    teardown) cmd_teardown "$@" ;;
    nuke)     cmd_nuke "$@" ;;
    query)    cmd_query "$@" ;;
    *)
        echo "Usage: $0 {deploy|seed|refresh|validate|demo|teardown|nuke|query <sql>}" >&2
        exit 1 ;;
esac
