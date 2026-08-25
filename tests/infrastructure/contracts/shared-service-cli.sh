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
TMP_PARENT="$ROOT_DIR/.shared-service-contract-scratch"
TMP_DIR="$TMP_PARENT/$$"
mkdir -p "$TMP_PARENT"
rm -rf "$TMP_DIR"
mkdir "$TMP_DIR" || exit 2
trap 'rm -rf "$TMP_DIR"; rmdir "$TMP_PARENT" 2>/dev/null || true' EXIT

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
elif "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1 && \
  jq -e 'type == "object" and .action == "validate" and .diagnostics[0].code == "UNKNOWN_ACTION"' "$TMP_DIR/out.json" >/dev/null 2>&1; then
  pass "unknown action: emits schema-valid JSON-only diagnostic stdout"
else
  fail "unknown action: stdout is not valid schema-conformant diagnostic JSON"
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

# --- Forwarding-gateway hardening is ordered after route verification -------
# The deploy implementation must not generate/apply Static Web Apps
# forwarding-gateway restrictions until verify_control_plane has succeeded.

verify_line="$(grep -n 'if ! verify_control_plane; then' "$CLI" | head -n 1 | cut -d: -f1)"
gateway_line="$(grep -n 'forwarding_result="$(forwarding_gateway_state' "$CLI" | head -n 1 | cut -d: -f1)"
if [ -n "$verify_line" ] && [ -n "$gateway_line" ] && [ "$verify_line" -lt "$gateway_line" ]; then
  pass "forwarding-gateway restriction is reached only after deploy route verification"
else
  fail "forwarding-gateway restriction must be ordered after verify_control_plane in deploy"
fi

if awk '
  /# Stage 9: verify the deployed control-plane graph\./ { seen_verify = 1 }
  /forwarding_gateway_state/ && seen_verify { seen_gateway = 1 }
  /# Stage 11: capture the resulting inventory/ && seen_gateway { found = 1 }
  END { exit(found ? 0 : 1) }
' "$CLI"; then
  pass "deploy stages place forwarding-gateway hardening between verification and inventory"
else
  fail "deploy stages must place forwarding-gateway hardening between verification and inventory"
fi

if awk '
  /cmd_deploy\(\)/ { in_deploy = 1 }
  in_deploy && /azure_whatif_route "\$route_params_file"/ { seen_route_whatif = 1 }
  in_deploy && /azure_deploy_route "\$route_params_file"/ && seen_route_whatif { found = 1 }
  in_deploy && /^}/ { in_deploy = 0 }
  END { exit(found ? 0 : 1) }
' "$CLI"; then
  pass "deploy runs route what-if with the deploy parameter file before route deployment"
else
  fail "deploy must run route what-if before deploying the route template"
fi

# --- Legacy-mutation guard fixtures -----------------------------------------

cat >"$TMP_DIR/whatif-shared-only.json" <<'JSON'
{
  "changes": [
    {
      "changeType": "Modify",
      "resourceId": "/subscriptions/s/resourceGroups/rg-gvt-shared/providers/Microsoft.Cdn/profiles/afd/afdEndpoints/gvt-dev-shared"
    },
    {
      "changeType": "Modify",
      "resourceId": "/subscriptions/s/resourceGroups/rg-gvt-shared/providers/Microsoft.Cdn/profiles/afd/securityPolicies/waf-shared-dev"
    }
  ]
}
JSON

if SHARED_SERVICE_TEST_ASSERT_NO_LEGACY_MUTATION="$TMP_DIR/whatif-shared-only.json" \
  "$CLI" validate --environment dev --local-only >"$TMP_DIR/guard-ok.json" 2>"$TMP_DIR/guard-ok.err"; then
  pass "legacy-mutation guard allows shared leaf resources and the shared security policy"
else
  fail "legacy-mutation guard should allow shared-only changes: $(cat "$TMP_DIR/guard-ok.json")"
fi

cat >"$TMP_DIR/whatif-rg-shared-offenders.json" <<'JSON'
{
  "changes": [
    {
      "changeType": "Delete",
      "resourceId": "/subscriptions/s/resourceGroups/rg-gvt-shared/providers/Microsoft.Web/staticSites/swa-legacy-instance-prod"
    },
    {
      "changeType": "Modify",
      "resourceId": "/subscriptions/s/resourceGroups/rg-gamevault-shared/providers/Microsoft.Storage/storageAccounts/stlegacyprod"
    }
  ]
}
JSON

if SHARED_SERVICE_TEST_ASSERT_NO_LEGACY_MUTATION="$TMP_DIR/whatif-rg-shared-offenders.json" \
  "$CLI" validate --environment dev --local-only >"$TMP_DIR/guard-rg.json" 2>"$TMP_DIR/guard-rg.err"; then
  fail "legacy-mutation guard must reject legacy resources in resource groups ending with -shared"
elif jq -e '.diagnostics[0].code == "LEGACY_MUTATION_DETECTED"' "$TMP_DIR/guard-rg.json" >/dev/null 2>&1; then
  pass "legacy-mutation guard flags legacy resources in resource groups ending with -shared"
else
  fail "legacy-mutation guard rejected rg-shared fixture with unexpected envelope: $(cat "$TMP_DIR/guard-rg.json")"
fi

cat >"$TMP_DIR/whatif-security-delete.json" <<'JSON'
{
  "changes": [
    {
      "changeType": "Delete",
      "resourceId": "/subscriptions/s/resourceGroups/rg-gvt-shared/providers/Microsoft.Cdn/profiles/afd/securityPolicies/waf-shared-dev"
    }
  ]
}
JSON

if SHARED_SERVICE_TEST_ASSERT_NO_LEGACY_MUTATION="$TMP_DIR/whatif-security-delete.json" \
  "$CLI" validate --environment dev --local-only >"$TMP_DIR/guard-security.json" 2>"$TMP_DIR/guard-security.err"; then
  fail "legacy-mutation guard must reject security policy deletes"
elif jq -e '.diagnostics[0].code == "LEGACY_MUTATION_DETECTED"' "$TMP_DIR/guard-security.json" >/dev/null 2>&1; then
  pass "legacy-mutation guard flags security policy deletes"
else
  fail "legacy-mutation guard rejected security delete fixture with unexpected envelope: $(cat "$TMP_DIR/guard-security.json")"
fi

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
