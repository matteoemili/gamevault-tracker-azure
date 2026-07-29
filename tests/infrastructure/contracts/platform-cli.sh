#!/bin/bash
# Contract tests for scripts/platform.sh. No Azure mutation is performed.
# Bash 3.2 compatible. Requires: jq.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/platform.sh"
SCHEMA="$ROOT_DIR/tests/infrastructure/contracts/platform-output.schema.json"
VALIDATOR="$ROOT_DIR/tests/infrastructure/contracts/output-schema.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILURES=0
log() { echo "[platform-cli] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

run_failure() {
  label="$1"
  shift
  if "$CLI" "$@" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
    fail "$label: expected nonzero exit"
    return
  fi
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1; then
    pass "$label: emits schema-valid JSON on stdout"
  else
    fail "$label: stdout is not schema-valid JSON: $(cat "$TMP_DIR/out.json")"
  fi
}

run_failure "missing environment" validate --local-only
run_failure "invalid environment" validate --environment invalid --local-only
run_failure "deploy requires confirmation" deploy --environment dev --subscription-id invalid --resource-group invalid
run_failure "retire-profile requires confirmation" retire-profile --environment dev --subscription-id invalid --resource-group invalid
if "$CLI" unknown --environment dev --local-only >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
  fail "unknown action: expected nonzero exit"
elif jq -e 'type == "object" and .diagnostics[0].code == "UNKNOWN_ACTION"' "$TMP_DIR/out.json" >/dev/null 2>&1; then
  pass "unknown action: emits JSON-only diagnostic stdout"
else
  fail "unknown action: stdout is not valid diagnostic JSON"
fi
run_failure "unknown option" validate --environment dev --local-only --bogus

if "$CLI" validate --environment dev --local-only >"$TMP_DIR/local.json" 2>"$TMP_DIR/local.err"; then
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/local.json" >/dev/null 2>&1; then
    pass "local-only validation emits schema-valid JSON"
  else
    fail "local-only validation stdout is not schema-valid JSON"
  fi
else
  fail "local-only validation should succeed"
fi

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES contract test(s) failed"
  exit 1
fi
log "all contract tests passed"
