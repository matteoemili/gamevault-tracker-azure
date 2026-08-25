#!/bin/bash
# Contract tests for scripts/shared-service.sh. No Azure mutation is
# performed: every case either fails before touching Azure or runs with
# --local-only. Bash 3.2 compatible. Requires: jq, az (for --local-only).
#
# Asserts the contract in
# specs/003-shared-entry-scale/contracts/shared-service-cli.md:
#   - the validate|what-if|deploy|verify|status action surface
#   - required options are enforced
#   - deploy is gated on --confirm
#   - --local-only is restricted to validate
#   - stdout is always exactly one schema-valid JSON document

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/shared-service.sh"
SCHEMA="$ROOT_DIR/tests/infrastructure/contracts/shared-service-output.schema.json"
VALIDATOR="$ROOT_DIR/tests/infrastructure/contracts/output-schema.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILURES=0
log() { echo "[shared-service-cli] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

# assert_single_json_document <file>: the CLI contract requires exactly one
# JSON document on stdout, so a concatenation of two objects must fail.
assert_single_json_document() {
  jq -e -s 'length == 1' "$1" >/dev/null 2>&1
}

run_failure() {
  label="$1"
  shift
  if "$CLI" "$@" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
    fail "$label: expected nonzero exit"
    return
  fi
  if ! assert_single_json_document "$TMP_DIR/out.json"; then
    fail "$label: stdout is not exactly one JSON document"
    return
  fi
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1; then
    pass "$label: emits schema-valid JSON on stdout"
  else
    fail "$label: stdout is not schema-valid JSON: $(cat "$TMP_DIR/out.json")"
  fi
}

# --- Usage and option enforcement -------------------------------------------

run_failure "missing environment" validate --local-only
run_failure "invalid environment" validate --environment invalid --local-only
run_failure "unknown option" validate --environment dev --local-only --bogus
run_failure "missing subscription id" validate --environment dev
run_failure "missing shared resource group" validate --environment dev --subscription-id sub-invalid

# --- Action surface ---------------------------------------------------------

if "$CLI" unknown --environment dev --local-only >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
  fail "unknown action: expected nonzero exit"
elif jq -e 'type == "object" and .diagnostics[0].code == "UNKNOWN_ACTION"' "$TMP_DIR/out.json" >/dev/null 2>&1; then
  pass "unknown action: emits JSON-only diagnostic stdout"
else
  fail "unknown action: stdout is not valid diagnostic JSON"
fi

if "$CLI" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
  fail "no action: expected nonzero exit"
else
  pass "no action: exits nonzero with usage on stderr"
fi

# Every documented action must be recognised, i.e. must NOT fail with
# UNKNOWN_ACTION. They are invoked with deliberately incomplete options so
# they fail early, before any Azure call.
for action in validate what-if deploy verify status inventory; do
  "$CLI" "$action" >"$TMP_DIR/out.json" 2>/dev/null
  if jq -e '.diagnostics[0].code == "UNKNOWN_ACTION"' "$TMP_DIR/out.json" >/dev/null 2>&1; then
    fail "action '$action' should be part of the supported action surface"
  else
    pass "action '$action' is recognised"
  fi
done

# --- deploy is gated on --confirm -------------------------------------------

"$CLI" deploy --environment dev --subscription-id sub-invalid \
  --shared-resource-group rg-shared-invalid \
  --platform-resource-group rg-platform-invalid \
  --front-door-profile afd-invalid \
  >"$TMP_DIR/out.json" 2>/dev/null
if jq -e '.status == "Failed" and .diagnostics[0].code == "CONFIRMATION_REQUIRED"' "$TMP_DIR/out.json" >/dev/null 2>&1; then
  pass "deploy without --confirm is refused before any Azure call"
else
  fail "deploy without --confirm must fail with CONFIRMATION_REQUIRED"
fi

# --- --local-only is restricted to validate ---------------------------------

for action in what-if deploy verify status inventory; do
  "$CLI" "$action" --environment dev --local-only >"$TMP_DIR/out.json" 2>/dev/null
  if jq -e '.diagnostics[0].code == "LOCAL_ONLY_NOT_SUPPORTED"' "$TMP_DIR/out.json" >/dev/null 2>&1; then
    pass "--local-only is rejected for '$action'"
  else
    fail "--local-only must be rejected for '$action'"
  fi
done

# --- The shared CLI must not accept an instance identifier ------------------
# Adding a logical instance is a data operation, never a deployment input.

run_failure "instance-id is not a shared-service option" validate --environment dev --local-only --instance-id abc

# --- Local-only success path ------------------------------------------------

if "$CLI" validate --environment dev --local-only >"$TMP_DIR/local.json" 2>"$TMP_DIR/local.err"; then
  if ! assert_single_json_document "$TMP_DIR/local.json"; then
    fail "local-only validation stdout is not exactly one JSON document"
  elif ! "$VALIDATOR" "$SCHEMA" "$TMP_DIR/local.json" >/dev/null 2>&1; then
    fail "local-only validation stdout is not schema-valid JSON"
  elif jq -e '.action == "validate" and .status == "Succeeded" and .operationId != ""' "$TMP_DIR/local.json" >/dev/null 2>&1; then
    pass "local-only validation emits a schema-valid success envelope"
  else
    fail "local-only validation envelope has unexpected action/status"
  fi
else
  fail "local-only validation should succeed: $(cat "$TMP_DIR/local.err")"
fi

# --- No secrets may appear on stdout ----------------------------------------

if grep -Eiq 'AccountKey=|sig=|client_secret|deploymentToken' "$TMP_DIR/local.json"; then
  fail "local-only validation stdout contains secret-bearing material"
else
  pass "stdout contains no secret-bearing material"
fi

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES contract test(s) failed"
  exit 1
fi
log "all contract tests passed"
