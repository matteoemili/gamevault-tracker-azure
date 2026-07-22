#!/bin/bash
# Contract tests for scripts/instance-route.sh. No Azure mutation is performed.
# Bash 3.2 compatible. Requires: jq.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/instance-route.sh"
SCHEMA="$ROOT_DIR/tests/infrastructure/contracts/instance-route-output.schema.json"
VALIDATOR="$ROOT_DIR/tests/infrastructure/contracts/output-schema.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILURES=0
log() { echo "[instance-route-cli] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

base_args() {
  echo "--instance-id a1 --instance-resource-group rg-instance-a1 --static-web-app-name swa-instance-a1 --platform-resource-group rg-platform --front-door-profile gvt-afd-dev --subscription-id invalid"
}

run_failure() {
  label="$1"
  shift
  if "$CLI" "$@" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
    fail "$label: expected nonzero exit"
    return
  fi
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1; then
    if grep -Eqi '(sig=|accountkey=|client_secret=|password=|bearer )' "$TMP_DIR/out.json" "$TMP_DIR/err.log"; then
      fail "$label: output contains a possible secret"
    else
      pass "$label: emits redacted schema-valid JSON"
    fi
  else
    fail "$label: stdout is not schema-valid JSON: $(cat "$TMP_DIR/out.json")"
  fi
}

run_failure "missing instance ID" register --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev
run_failure "malformed instance ID" register --instance-id A_B --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev
run_failure "missing resource group" verify --instance-id a1 --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid
run_failure "invalid origin hostname" register --instance-id a1 --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev --origin-hostname invalid.example
run_failure "invalid instance scope" register --instance-id a1 --instance-resource-group rg-platform --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev
run_failure "unknown option" status --instance-id a1 --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --bogus

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES contract test(s) failed"
  exit 1
fi
log "all contract tests passed"
