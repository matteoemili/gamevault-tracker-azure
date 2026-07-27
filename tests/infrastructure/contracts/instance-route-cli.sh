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
MOCK_BIN="$TMP_DIR/mock-bin"
mkdir -p "$MOCK_BIN"

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

write_route_mocks() {
  printf '%s\n' '#!/bin/bash' \
    'case "$1 $2 $3" in' \
    '  "account show"*) echo "{}" ;;' \
    '  "account set"*) exit 0 ;;' \
    '  "afd endpoint list"*)' \
    '    if [ "${MOCK_ROUTE_CASE:-}" = "ownership" ]; then' \
    '      echo "{\"name\":\"gvt-dev-a1\",\"hostName\":\"gvt-dev-a1.azurefd.net\",\"provisioningState\":\"Succeeded\",\"tags\":{\"instanceId\":\"a1\",\"instanceResourceGroup\":\"rg-other\",\"staticWebAppName\":\"swa-instance-a1\"}}"' \
    '    else' \
    '      echo "{\"name\":\"gvt-dev-a1\",\"hostName\":\"gvt-dev-a1.azurefd.net\",\"provisioningState\":\"Succeeded\",\"tags\":{\"instanceId\":\"a1\"}}"' \
    '    fi' \
    '    ;;' \
    '  "afd endpoint show"*)' \
    '    echo "{\"id\":\"/subscriptions/invalid/resourceGroups/rg-platform/providers/Microsoft.Cdn/profiles/gvt-afd-dev/afdEndpoints/gvt-dev-a1\",\"name\":\"gvt-dev-a1\",\"hostName\":\"gvt-dev-a1.azurefd.net\",\"enabledState\":\"Enabled\",\"provisioningState\":\"Succeeded\"}"' \
    '    ;;' \
    '  "afd route show"*)' \
    '    if [ "${MOCK_ROUTE_CASE:-}" = "route-properties" ]; then' \
    '      echo "{\"provisioningState\":\"Succeeded\",\"enabledState\":\"Enabled\",\"forwardingProtocol\":\"HttpsOnly\",\"httpsRedirect\":\"Disabled\",\"linkToDefaultDomain\":\"Enabled\",\"supportedProtocols\":[\"Http\",\"Https\"],\"patternsToMatch\":[\"/*\"],\"originGroup\":{\"id\":\"/subscriptions/invalid/resourceGroups/rg-platform/providers/Microsoft.Cdn/profiles/gvt-afd-dev/originGroups/og-a1\"}}"' \
    '    else' \
    '      echo "{\"provisioningState\":\"Succeeded\",\"enabledState\":\"Enabled\",\"forwardingProtocol\":\"HttpsOnly\",\"httpsRedirect\":\"Enabled\",\"linkToDefaultDomain\":\"Enabled\",\"supportedProtocols\":[\"Http\",\"Https\"],\"patternsToMatch\":[\"/*\"],\"originGroup\":{\"id\":\"/subscriptions/invalid/resourceGroups/rg-platform/providers/Microsoft.Cdn/profiles/gvt-afd-dev/originGroups/og-a1\"}}"' \
    '    fi' \
    '    ;;' \
    '  "afd origin-group show"*) echo "{\"provisioningState\":\"Succeeded\",\"loadBalancingSettings\":{\"sampleSize\":4,\"successfulSamplesRequired\":3,\"additionalLatencyInMilliseconds\":50},\"healthProbeSettings\":{\"probePath\":\"/\",\"probeRequestType\":\"HEAD\",\"probeProtocol\":\"Https\",\"probeIntervalInSeconds\":60}}" ;;' \
    '  "afd origin show"*)' \
    '    if [ "${MOCK_ROUTE_CASE:-}" = "origin-mismatch" ]; then' \
    '      echo "{\"id\":\"/subscriptions/invalid/resourceGroups/rg-platform/providers/Microsoft.Cdn/profiles/gvt-afd-dev/originGroups/og-a1/origins/origin-a1\",\"provisioningState\":\"Succeeded\",\"enabledState\":\"Enabled\",\"hostName\":\"actual.azurestaticapps.net\",\"originHostHeader\":\"actual.azurestaticapps.net\",\"httpPort\":80,\"httpsPort\":443,\"priority\":1,\"weight\":1000,\"enforceCertificateNameCheck\":true}"' \
    '    else' \
    '      echo "{\"id\":\"/subscriptions/invalid/resourceGroups/rg-platform/providers/Microsoft.Cdn/profiles/gvt-afd-dev/originGroups/og-a1/origins/origin-a1\",\"provisioningState\":\"Succeeded\",\"enabledState\":\"Enabled\",\"hostName\":\"expected.azurestaticapps.net\",\"originHostHeader\":\"expected.azurestaticapps.net\",\"httpPort\":80,\"httpsPort\":443,\"priority\":1,\"weight\":1000,\"enforceCertificateNameCheck\":true}"' \
    '    fi' \
    '    ;;' \
    '  *) exit 1 ;;' \
    'esac' >"$MOCK_BIN/az"
  chmod +x "$MOCK_BIN/az"

  printf '%s\n' '#!/bin/bash' \
    'echo "curl must not be called by verify" >&2' \
    'exit 99' >"$MOCK_BIN/curl"
  chmod +x "$MOCK_BIN/curl"
}

run_mock_failure() {
  label="$1"
  expected_code="$2"
  mock_case="$3"
  shift 3
  if MOCK_ROUTE_CASE="$mock_case" PATH="$MOCK_BIN:$PATH" "$CLI" "$@" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
    fail "$label: expected nonzero exit"
    return
  fi
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1 &&
    jq -e --arg code "$expected_code" 'any(.diagnostics[]?; .code == $code)' "$TMP_DIR/out.json" >/dev/null 2>&1; then
    if grep -Eqi '(sig=|accountkey=|client_secret=|password=|bearer )' "$TMP_DIR/out.json" "$TMP_DIR/err.log"; then
      fail "$label: output contains a possible secret"
    else
      pass "$label: emits redacted schema-valid JSON with $expected_code"
    fi
  else
    fail "$label: stdout is not schema-valid JSON with $expected_code: $(cat "$TMP_DIR/out.json")"
  fi
}

run_mock_degraded() {
  label="$1"
  expected_code="$2"
  mock_case="$3"
  shift 3
  if ! MOCK_ROUTE_CASE="$mock_case" PATH="$MOCK_BIN:$PATH" "$CLI" "$@" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
    fail "$label: expected degraded verification output"
    return
  fi
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1 &&
    jq -e --arg code "$expected_code" '(.status == "Degraded") and any(.diagnostics[]?; .code == $code)' "$TMP_DIR/out.json" >/dev/null 2>&1; then
    if grep -Eqi '(sig=|accountkey=|client_secret=|password=|bearer )' "$TMP_DIR/out.json" "$TMP_DIR/err.log"; then
      fail "$label: output contains a possible secret"
    else
      pass "$label: emits redacted schema-valid JSON with $expected_code"
    fi
  else
    fail "$label: stdout is not schema-valid degraded JSON with $expected_code: $(cat "$TMP_DIR/out.json")"
  fi
}

run_mock_success() {
  label="$1"
  mock_case="$2"
  shift 2
  if ! MOCK_ROUTE_CASE="$mock_case" PATH="$MOCK_BIN:$PATH" "$CLI" "$@" >"$TMP_DIR/out.json" 2>"$TMP_DIR/err.log"; then
    fail "$label: expected successful control-plane validation"
    return
  fi
  if "$VALIDATOR" "$SCHEMA" "$TMP_DIR/out.json" >/dev/null 2>&1 &&
    jq -e '(.status == "Succeeded") and (.route.endpointHostName == "gvt-dev-a1.azurefd.net")' "$TMP_DIR/out.json" >/dev/null 2>&1; then
    pass "$label: validates the complete Front Door property graph without curl"
  else
    fail "$label: output is not a successful schema-valid validation result: $(cat "$TMP_DIR/out.json")"
  fi
}

write_route_mocks
run_failure "missing instance ID" register --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev
run_failure "malformed instance ID" register --instance-id A_B --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev
run_failure "missing resource group" verify --instance-id a1 --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid
run_failure "invalid origin hostname" register --instance-id a1 --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev --origin-hostname invalid.example
run_failure "invalid expected origin hostname" verify --instance-id a1 --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --expected-origin-hostname invalid.example
run_failure "invalid instance scope" register --instance-id a1 --instance-resource-group rg-platform --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --environment dev
run_failure "unknown option" status --instance-id a1 --instance-resource-group rg-a --static-web-app-name swa-a --platform-resource-group rg-platform --front-door-profile fd --subscription-id invalid --bogus
run_failure "missing expected origin hostname" verify --instance-id a1 --instance-resource-group rg-instance-a1 --static-web-app-name swa-instance-a1 --platform-resource-group rg-platform --front-door-profile gvt-afd-dev --subscription-id invalid
run_mock_success "complete route property validation" success verify --instance-id a1 --instance-resource-group rg-instance-a1 --static-web-app-name swa-instance-a1 --platform-resource-group rg-platform --front-door-profile gvt-afd-dev --subscription-id invalid --expected-origin-hostname expected.azurestaticapps.net
run_mock_degraded "expected origin mismatch" ORIGIN_CONFIGURATION_MISMATCH origin-mismatch verify --instance-id a1 --instance-resource-group rg-instance-a1 --static-web-app-name swa-instance-a1 --platform-resource-group rg-platform --front-door-profile gvt-afd-dev --subscription-id invalid --expected-origin-hostname expected.azurestaticapps.net
run_mock_degraded "route property mismatch" ROUTE_CONFIGURATION_MISMATCH route-properties verify --instance-id a1 --instance-resource-group rg-instance-a1 --static-web-app-name swa-instance-a1 --platform-resource-group rg-platform --front-door-profile gvt-afd-dev --subscription-id invalid --expected-origin-hostname expected.azurestaticapps.net
run_mock_failure "ownership tag mismatch" OWNERSHIP_TAG_MISMATCH ownership unregister --instance-id a1 --instance-resource-group rg-instance-a1 --static-web-app-name swa-instance-a1 --platform-resource-group rg-platform --front-door-profile gvt-afd-dev --subscription-id invalid --confirm

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES contract test(s) failed"
  exit 1
fi
log "all contract tests passed"
