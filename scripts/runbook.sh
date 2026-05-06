#!/usr/bin/env bash
# ============================================================================
# scripts/runbook.sh
# Programmatic deploy / refresh / teardown / validate / demo runner for the
# 0.1.1 medallion stack. Submits each SQL file to a Databricks SQL warehouse
# via the /api/2.0/sql/statements REST endpoint (stable across CLI versions).
#
# Subcommands:
#   deploy    — runs every 0.1.1 SQL file in run order (excludes teardown).
#   seed      — runs only 01_pre_bronze/08_seed.sql.
#   refresh   — calls bronze_silver_gold_refresh().
#   validate  — runs every 05_validate/*.sql in order.
#   demo      — prints reading order for 06_demos/ (interactive — you pick).
#   teardown  — runs 02_teardown.sql with RUN_TEARDOWN=TRUE (requires
#               TEARDOWN_CONFIRM=YES env var to actually fire).
#
# Auth: requires DATABRICKS_HOST, DATABRICKS_TOKEN, DATABRICKS_WAREHOUSE_ID
# in env (or .env loaded via shell). See .env.example.
#
# Manual flow remains primary — this script is for batch deploys, CI dry
# runs, and 0.1.7 foundation.
# ============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_ROOT="$REPO_ROOT/packages/0.1.1"

# Load .env if present
if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
    set +a
fi

: "${DATABRICKS_HOST:?DATABRICKS_HOST not set; cp .env.example .env and fill in}"
: "${DATABRICKS_TOKEN:?DATABRICKS_TOKEN not set}"
: "${DATABRICKS_WAREHOUSE_ID:?DATABRICKS_WAREHOUSE_ID not set}"

# ---------------------------------------------------------------------------
# Submit one SQL statement and poll until terminal state. Returns 0 on
# success, non-zero on FAILED / CANCELED / TIMED_OUT.
# ---------------------------------------------------------------------------
exec_sql_file() {
    local file="$1"
    local label
    label="$(basename "$file")"
    echo "▶ $label"

    local sql
    sql="$(cat "$file")"

    local payload
    payload=$(jq -nR --arg s "$sql" --arg w "$DATABRICKS_WAREHOUSE_ID" \
        '{statement: $s, warehouse_id: $w, wait_timeout: "50s", on_wait_timeout: "CONTINUE"}')

    local resp
    resp=$(curl -sS -X POST "https://$DATABRICKS_HOST/api/2.0/sql/statements" \
        -H "Authorization: Bearer $DATABRICKS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload")

    local statement_id state
    statement_id=$(echo "$resp" | jq -r '.statement_id')
    state=$(echo "$resp" | jq -r '.status.state')

    # Poll if not yet terminal
    while [[ "$state" == "PENDING" || "$state" == "RUNNING" ]]; do
        sleep 5
        resp=$(curl -sS "https://$DATABRICKS_HOST/api/2.0/sql/statements/$statement_id" \
            -H "Authorization: Bearer $DATABRICKS_TOKEN")
        state=$(echo "$resp" | jq -r '.status.state')
    done

    if [[ "$state" == "SUCCEEDED" ]]; then
        echo "  ✓ $label"
        return 0
    else
        echo "  ✗ $label — state=$state" >&2
        echo "$resp" | jq '.status.error // .' >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Run every SQL file in a directory, sorted lexicographically.
# ---------------------------------------------------------------------------
exec_dir_sorted() {
    local dir="$1"
    while IFS= read -r f; do
        exec_sql_file "$f"
    done < <(find "$dir" -maxdepth 1 -name '*.sql' | sort)
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_deploy() {
    echo "═══ deploy: 0.1.1 medallion runbook ═══"
    exec_sql_file "$PKG_ROOT/00_setup/00_create_catalog.sql"
    exec_sql_file "$PKG_ROOT/00_setup/01_config.sql"
    exec_dir_sorted "$PKG_ROOT/01_pre_bronze"
    exec_dir_sorted "$PKG_ROOT/02_bronze"
    exec_dir_sorted "$PKG_ROOT/03_silver"
    exec_dir_sorted "$PKG_ROOT/04_gold"
    exec_sql_file "$PKG_ROOT/00_setup/03_refresh_orchestrator.sql"
    echo "═══ deploy complete. Run \`pnpm run refresh\` to populate tables. ═══"
}

cmd_seed() {
    exec_sql_file "$PKG_ROOT/00_setup/01_config.sql"
    exec_sql_file "$PKG_ROOT/01_pre_bronze/08_seed.sql"
}

cmd_refresh() {
    exec_sql_file "$PKG_ROOT/00_setup/01_config.sql"
    # Inline statement — call the orchestrator
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;
CALL bronze_silver_gold_refresh();
EOF
    exec_sql_file "$tmp"
    rm -f "$tmp"
}

cmd_validate() {
    echo "═══ validate: running 05_validate/ gates ═══"
    exec_sql_file "$PKG_ROOT/00_setup/01_config.sql"
    exec_dir_sorted "$PKG_ROOT/05_validate"
    echo "═══ validate complete ═══"
}

cmd_demo() {
    echo "═══ 06_demos/ reading order ═══"
    echo "Run each in a SQL editor (not via this script — they're pedagogical):"
    echo
    cat <<'EOF'
  01_what_is_a_view.sql       — view = stored query
  02_what_is_an_mv.sql        — MV = view + cached results; REFRESH demo
  03_what_is_a_table.sql      — table = explicit INSERT-driven population
  04_parity_demo.sql          — v/mv/t agree after refresh
  05_timing_demo.sql          — cold/warm cache + materialized comparison
  06_freshness_demo.sql       — what each artifact sees when raw mutates
  07_refresh_cost_demo.sql    — event_log() per-MV cost telemetry
  08_concurrency_demo.sql     — multi-tab: read v while mv refreshes
  09_cascade_demo.sql         — Decision #13 made visible (2.5h+ → 5–10 min)
  99_adhoc_playground.sql     — open-ended analyst queries
EOF
    echo
    echo "See packages/0.1.1/06_demos/README.md for the full pedagogical arc."
}

cmd_teardown() {
    if [[ "${TEARDOWN_CONFIRM:-NO}" != "YES" ]]; then
        echo "✗ teardown blocked. Set TEARDOWN_CONFIRM=YES to actually run." >&2
        echo "  This will drop all 15 schemas in $DATABRICKS_HOST." >&2
        exit 2
    fi
    local tmp
    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
DECLARE OR REPLACE VARIABLE catalog_name STRING DEFAULT 'medallion_demo';
EXECUTE IMMEDIATE 'USE CATALOG ' || catalog_name;
SET VARIABLE RUN_TEARDOWN = TRUE;
EOF
    cat "$PKG_ROOT/00_setup/02_teardown.sql" >> "$tmp"
    exec_sql_file "$tmp"
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
    deploy)   cmd_deploy ;;
    seed)     cmd_seed ;;
    refresh)  cmd_refresh ;;
    validate) cmd_validate ;;
    demo)     cmd_demo ;;
    teardown) cmd_teardown ;;
    *)
        echo "Usage: $0 {deploy|seed|refresh|validate|demo|teardown}" >&2
        exit 1
        ;;
esac
