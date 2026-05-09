#!/usr/bin/env python3
"""Submit SQL files to Databricks SQL Statement Execution API.

The API takes ONE statement per call. Our SQL files have many statements +
session variables that must persist across them. The fix: wrap each file's
contents in a `BEGIN..END;` compound block — that's a single statement to
the API, but `DECLARE`s and other statements inside share a scope (Spark
SQL Scripting). One side-effect: compound blocks reject `DECLARE OR REPLACE`,
so we rewrite that to `DECLARE`.

Backend: subprocess + `curl` (uses macOS system trust store; Python urllib
fails on Zscaler/corp SSL inspection).

Env: DATABRICKS_HOST, DATABRICKS_TOKEN, DATABRICKS_WAREHOUSE_ID
Usage:
  dbx_run.py file1.sql [file2.sql ...]   # run files in order, stop on first failure
  dbx_run.py --inline 'SELECT 1'          # run an ad-hoc SQL statement
  dbx_run.py --no-wrap file.sql           # submit file as-is (no BEGIN..END wrap)
  dbx_run.py --continue file1.sql ...     # don't stop on failure
  dbx_run.py --quiet ...                  # less verbose output
"""
import json
import os
import re
import subprocess
import sys
import time

HOST = os.environ.get("DATABRICKS_HOST", "").rstrip("/")
TOKEN = os.environ.get("DATABRICKS_TOKEN")
WH = os.environ.get("DATABRICKS_WAREHOUSE_ID")

if not (HOST and TOKEN and WH):
    sys.stderr.write(
        "missing env: DATABRICKS_HOST + DATABRICKS_TOKEN + DATABRICKS_WAREHOUSE_ID required\n"
    )
    sys.exit(2)
if not HOST.startswith("http"):
    HOST = "https://" + HOST


# ---------------------------------------------------------------------------
# Compound-block wrapping
# ---------------------------------------------------------------------------

DECL_OR_REPLACE = re.compile(
    r"\bDECLARE\s+OR\s+REPLACE\s+VARIABLE\b", re.IGNORECASE
)


def wrap_compound(sql):
    """Wrap SQL in BEGIN..END for single-statement submission.

    - Substitutes `DECLARE OR REPLACE VARIABLE` → `DECLARE VARIABLE` (compound
      blocks treat declared vars as local; OR REPLACE not supported).
    - If the SQL already starts with a top-level `BEGIN` token, returns as-is
      (file is its own compound block, e.g. 02_teardown.sql).
    """
    sql = DECL_OR_REPLACE.sub("DECLARE", sql)
    head = re.sub(r"^(?:--[^\n]*\n|\s+)+", "", sql)  # skip leading comments / ws
    if head.upper().startswith("BEGIN"):
        return sql
    return f"BEGIN\n{sql}\nEND;"


# ---------------------------------------------------------------------------
# REST API (subprocess + curl)
# ---------------------------------------------------------------------------


def api(method, path, body=None, retries=12, retry_sleep=5.0):
    """Call Databricks API via curl. Retries on transient network errors.

    curl exit codes worth retrying:
      6  — couldn't resolve host
      7  — failed to connect
      28 — timeout
      35 — SSL handshake / TLS recv failure
      52 — empty reply
      56 — failure receiving network data

    With 12 retries and linear-attempt backoff (5s, 10s, ..., 60s = ~6.5 min
    total budget per call), survives multi-minute network outages.
    """
    transient = {6, 7, 28, 35, 52, 56}
    url = f"{HOST}{path}"
    cmd = [
        "curl",
        "-sS",
        "--max-time",
        "180",
        "-X",
        method,
        url,
        "-H",
        f"Authorization: Bearer {TOKEN}",
        "-H",
        "Content-Type: application/json",
    ]
    if body is not None:
        cmd += ["-d", json.dumps(body)]
    last_err = "no attempt"
    for attempt in range(1, retries + 1):
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0:
            try:
                return json.loads(res.stdout, strict=False)
            except json.JSONDecodeError as e:
                return {
                    "status": {
                        "state": "FAILED",
                        "error": {
                            "error_code": "BAD_JSON",
                            "message": f"{e}: {res.stdout[:300]}",
                        },
                    }
                }
        last_err = res.stderr.strip() or f"curl rc={res.returncode}"
        if res.returncode not in transient or attempt == retries:
            break
        time.sleep(retry_sleep * attempt)  # backoff
    return {
        "status": {
            "state": "FAILED",
            "error": {"error_code": "CURL", "message": last_err},
        }
    }


def submit(stmt):
    return api(
        "POST",
        "/api/2.0/sql/statements",
        {
            "statement": stmt,
            "warehouse_id": WH,
            "wait_timeout": "50s",
            "on_wait_timeout": "CONTINUE",
            "disposition": "INLINE",
            "format": "JSON_ARRAY",
        },
    )


def poll(sid):
    """Poll until terminal state. Caller handles long-runners (no overall timeout)."""
    while True:
        r = api("GET", f"/api/2.0/sql/statements/{sid}")
        state = r.get("status", {}).get("state", "UNKNOWN")
        if state in ("SUCCEEDED", "FAILED", "CANCELED", "CLOSED"):
            return r
        time.sleep(4)


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------


def fmt_first(stmt, w=92):
    line = re.sub(r"^(?:--[^\n]*\n|\s+)+", "", stmt).split("\n", 1)[0].strip()
    return line[: w - 3] + "..." if len(line) > w else line


def run_statement(stmt, label, quiet):
    sys.stdout.write(f"  {label} {fmt_first(stmt)} ")
    sys.stdout.flush()
    t0 = time.time()
    r = submit(stmt)
    sid = r.get("statement_id")
    state = r.get("status", {}).get("state", "?")
    if state in ("PENDING", "RUNNING") and sid:
        r = poll(sid)
        state = r.get("status", {}).get("state", "?")
    dt = time.time() - t0
    if state == "SUCCEEDED":
        data = r.get("result", {}).get("data_array") or []
        if not quiet and data and data[0]:
            summary = " | ".join(str(x)[:60] for x in data[0])
            print(f"✓ {dt:.1f}s — {summary[:140]}")
        else:
            print(f"✓ {dt:.1f}s")
        return True
    err = r.get("status", {}).get("error") or {}
    print(f"✗ {dt:.1f}s — {state}")
    print(f"    {err.get('error_code', '?')}: {err.get('message', '')[:600]}")
    return False


def run_file(path, wrap, quiet):
    print(f"━━━ {os.path.relpath(path)}")
    with open(path) as f:
        sql = f.read()
    payload = wrap_compound(sql) if wrap else sql
    return run_statement(payload, "▸", quiet)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    args = sys.argv[1:]
    quiet = False
    keep_going = False
    wrap = True
    inline = None
    while args and args[0].startswith("--"):
        a = args.pop(0)
        if a == "--quiet":
            quiet = True
        elif a == "--continue":
            keep_going = True
        elif a == "--no-wrap":
            wrap = False
        elif a == "--inline":
            inline = args.pop(0)
        elif a == "--help" or a == "-h":
            print(__doc__)
            return
        else:
            sys.stderr.write(f"unknown flag: {a}\n")
            sys.exit(2)
    if inline is not None:
        ok = run_statement(inline, "▸", quiet)
        sys.exit(0 if ok else 1)
    if not args:
        print(__doc__)
        sys.exit(2)
    failed = 0
    for path in args:
        ok = run_file(path, wrap, quiet)
        if not ok:
            failed += 1
            if not keep_going:
                sys.exit(1)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
