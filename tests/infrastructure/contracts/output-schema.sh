#!/bin/bash
# ============================================================================
# output-schema.sh - Validate command-result JSON documents against the
# contract schemas in tests/infrastructure/contracts/*.schema.json
# ============================================================================
# Usage:
#   output-schema.sh <schema-file> <json-file>   # validate one document
#   output-schema.sh --self-test                 # run built-in fixtures
#
# Bash 3.2 compatible: no associative arrays, no ${var,,}, no mapfile.
# Requires: jq
# ============================================================================

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_SCHEMA="$SCRIPT_DIR/platform-output.schema.json"
INSTANCE_SCHEMA="$SCRIPT_DIR/instance-route-output.schema.json"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_cmd jq

# Generic, dependency-free JSON Schema validator (jq program). Supports the
# subset of JSON Schema used by this project's schemas: type, properties,
# required, oneOf, const, enum, pattern, minLength, minimum, maximum, array
# items. Not a full JSON Schema implementation.
JQ_VALIDATE_PROGRAM='
def validate(schema; doc):
  if (schema | has("oneOf")) then
    (schema.oneOf | map(try (validate(.; doc) | true) catch false)) as $results
    | if ($results | any(.)) then true else error("value matched no oneOf branch") end
  elif (schema.type? == "null") then
    if doc == null then true else error("expected null, got " + (doc | tostring)) end
  elif (schema.type? == "object") or (schema | has("properties")) then
    if (doc | type) != "object" then
      error("expected object, got " + (doc | type))
    else
      ((schema.required // []) - (doc | keys)) as $missing
      | if ($missing | length) > 0 then
          error("missing required keys: " + ($missing | join(", ")))
        else
          reduce (schema.properties // {} | to_entries[]) as $p (true;
            . and (
              if (doc | has($p.key) | not) then true
              else validate($p.value; doc[$p.key])
              end
            )
          )
        end
    end
  elif (schema.type? == "array") then
    if (doc | type) != "array" then
      error("expected array, got " + (doc | type))
    else
      reduce (doc[]) as $item (true; . and validate(schema.items; $item))
    end
  else
    (if (schema.const? != null) and (doc != schema.const) then error("const mismatch: " + (doc | tostring)) else true end)
    and (if (schema.enum? != null) and ((schema.enum | index(doc)) == null) then error("enum mismatch: " + (doc | tostring)) else true end)
    and (if (schema.pattern? != null) and ((doc | type) == "string") and ((doc | test(schema.pattern)) | not) then error("pattern mismatch: " + (doc | tostring)) else true end)
    and (if (schema.minLength? != null) and ((doc | type) == "string") and ((doc | length) < schema.minLength) then error("minLength violation") else true end)
    and (if (schema.minimum? != null) and ((doc | type) == "number") and (doc < schema.minimum) then error("minimum violation") else true end)
    and (if (schema.maximum? != null) and ((doc | type) == "number") and (doc > schema.maximum) then error("maximum violation") else true end)
  end;
validate($schema[0]; $doc[0])
'

# validate_document <schema-file> <json-file>
# Prints "PASS" or "FAIL: <reason>" to stdout, returns 0/1.
validate_document() {
  schema_file="$1"
  json_file="$2"

  [ -f "$schema_file" ] || die "schema not found: $schema_file"
  [ -f "$json_file" ] || die "document not found: $json_file"

  result=$(jq -n \
    --slurpfile schema "$schema_file" \
    --slurpfile doc "$json_file" \
    "$JQ_VALIDATE_PROGRAM" 2>&1) && {
    echo "PASS"
    return 0
  }
  echo "FAIL: $result"
  return 1
}

# ----------------------------------------------------------------------------
# Self-test: representative success, NoChange, and failure fixtures for both
# schemas, plus deliberately invalid fixtures to prove the validator catches
# real violations.
# ----------------------------------------------------------------------------
self_test() {
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT

  failures=0

  expect_pass() {
    label="$1"; schema="$2"; file="$3"
    if validate_document "$schema" "$file" >/dev/null 2>&1; then
      echo "  ok   (expected pass): $label"
    else
      echo "  FAIL (expected pass, got fail): $label"
      failures=$((failures + 1))
    fi
  }

  expect_fail() {
    label="$1"; schema="$2"; file="$3"
    if validate_document "$schema" "$file" >/dev/null 2>&1; then
      echo "  FAIL (expected fail, got pass): $label"
      failures=$((failures + 1))
    else
      echo "  ok   (expected fail): $label"
    fi
  }

  # --- platform-output: Succeeded ---
  cat > "$tmp_dir/platform-succeeded.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "deploy",
  "status": "Succeeded",
  "operationId": "platform-prod-20260721T120000Z",
  "platform": {
    "resourceGroupName": "rg-gamevault-platform-prod",
    "frontDoorProfileId": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-gamevault-platform-prod/providers/Microsoft.Cdn/profiles/gvt-afd-prod",
    "frontDoorId": "redacted-non-secret-identifier",
    "endpointCapacity": 25,
    "registeredEndpointCount": 0,
    "wafMode": "Detection"
  },
  "diagnostics": []
}
JSON

  # --- platform-output: NoChange ---
  cat > "$tmp_dir/platform-nochange.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "deploy",
  "status": "NoChange",
  "operationId": "platform-dev-20260721T120500Z",
  "platform": {
    "resourceGroupName": "rg-gamevault-platform-dev",
    "frontDoorProfileId": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-gamevault-platform-dev/providers/Microsoft.Cdn/profiles/gvt-afd-dev",
    "frontDoorId": "redacted-non-secret-identifier",
    "endpointCapacity": 25,
    "registeredEndpointCount": 2,
    "wafMode": "Detection"
  },
  "diagnostics": []
}
JSON

  # --- platform-output: Failed ---
  cat > "$tmp_dir/platform-failed.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "deploy",
  "status": "Failed",
  "operationId": "platform-prod-20260721T120000Z",
  "platform": null,
  "diagnostics": [
    { "code": "AZURE_VALIDATION_FAILED", "message": "Deployment validation failed; no resources were changed." }
  ]
}
JSON

  # --- platform-output: retire-profile Succeeded ---
  cat > "$tmp_dir/platform-retired.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "retire-profile",
  "status": "Succeeded",
  "operationId": "platform-prod-20260729T090000Z",
  "platform": {
    "resourceGroupName": "rg-gamevault-platform-prod",
    "frontDoorProfileId": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-gamevault-platform-prod/providers/Microsoft.Cdn/profiles/gvt-afd-prod",
    "frontDoorId": "redacted-non-secret-identifier",
    "endpointCapacity": 25,
    "registeredEndpointCount": 2,
    "wafMode": "Detection"
  },
  "diagnostics": [
    { "code": "PROFILE_RETIRED", "message": "Front Door profile and its WAF policy were deleted." },
    { "code": "REREGISTRATION_REQUIRED", "message": "Re-register 2 instance(s) after redeploying." },
    { "code": "RETIRED_INSTANCE", "message": "Instance requiring re-registration: abc12345" }
  ]
}
JSON

  # --- platform-output: invalid (missing required key, bad status enum) ---
  cat > "$tmp_dir/platform-invalid.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "deploy",
  "status": "Bogus",
  "platform": null,
  "diagnostics": []
}
JSON

  expect_pass "platform Succeeded"  "$PLATFORM_SCHEMA" "$tmp_dir/platform-succeeded.json"
  expect_pass "platform NoChange"   "$PLATFORM_SCHEMA" "$tmp_dir/platform-nochange.json"
  expect_pass "platform Failed"     "$PLATFORM_SCHEMA" "$tmp_dir/platform-failed.json"
  expect_pass "platform retired"    "$PLATFORM_SCHEMA" "$tmp_dir/platform-retired.json"
  expect_fail "platform invalid"    "$PLATFORM_SCHEMA" "$tmp_dir/platform-invalid.json"

  # --- instance-route-output: register Succeeded ---
  cat > "$tmp_dir/route-succeeded.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "register",
  "status": "Succeeded",
  "operationId": "route-abc12345-20260721T120000Z",
  "instance": {
    "instanceId": "abc12345",
    "resourceGroupName": "rg-gamevault-abc12345",
    "staticWebAppName": "swa-gamevault-prod-abc12345",
    "originHostName": "example.azurestaticapps.net"
  },
  "route": {
    "endpointName": "gvt-prod-abc12345-xyz",
    "endpointHostName": "gvt-prod-abc12345-xyz.z01.azurefd.net",
    "url": "https://gvt-prod-abc12345-xyz.z01.azurefd.net",
    "originGroupName": "og-abc12345",
    "originName": "origin-abc12345",
    "routeName": "route-abc12345",
    "provisioningState": "Succeeded"
  },
  "diagnostics": []
}
JSON

  # --- instance-route-output: NoChange (unregister of an absent instance) ---
  cat > "$tmp_dir/route-nochange.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "unregister",
  "status": "NoChange",
  "operationId": "route-abc12345-20260721T121000Z",
  "instance": null,
  "route": null,
  "diagnostics": []
}
JSON

  # --- instance-route-output: Failed (capacity exceeded) ---
  cat > "$tmp_dir/route-failed.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "register",
  "status": "Failed",
  "operationId": "route-zzz99999-20260721T121500Z",
  "instance": null,
  "route": null,
  "diagnostics": [
    { "code": "ENDPOINT_CAPACITY_EXCEEDED", "message": "Front Door profile already has 25 registered endpoints." }
  ]
}
JSON

  # --- instance-route-output: invalid (bad instanceId pattern, bad hostname) ---
  cat > "$tmp_dir/route-invalid.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "action": "register",
  "status": "Succeeded",
  "operationId": "route-BAD-20260721T121500Z",
  "instance": {
    "instanceId": "Not_Valid!",
    "resourceGroupName": "rg-gamevault-bad",
    "staticWebAppName": "swa-bad",
    "originHostName": "example.invalid-domain.com"
  },
  "route": {
    "endpointName": "gvt-prod-bad",
    "endpointHostName": "gvt-prod-bad.example.com",
    "url": "http://gvt-prod-bad.example.com",
    "originGroupName": "og-bad",
    "originName": "origin-bad",
    "routeName": "route-bad",
    "provisioningState": "Succeeded"
  },
  "diagnostics": []
}
JSON

  expect_pass "instance-route register Succeeded" "$INSTANCE_SCHEMA" "$tmp_dir/route-succeeded.json"
  expect_pass "instance-route unregister NoChange" "$INSTANCE_SCHEMA" "$tmp_dir/route-nochange.json"
  expect_pass "instance-route register Failed"     "$INSTANCE_SCHEMA" "$tmp_dir/route-failed.json"
  expect_fail "instance-route invalid"             "$INSTANCE_SCHEMA" "$tmp_dir/route-invalid.json"

  if [ "$failures" -gt 0 ]; then
    echo "output-schema.sh self-test: $failures failure(s)" >&2
    return 1
  fi
  echo "output-schema.sh self-test: all checks passed"
  return 0
}

# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------
main() {
  if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
  fi

  if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <schema-file> <json-file>" >&2
    echo "       $0 --self-test" >&2
    exit 2
  fi

  validate_document "$1" "$2"
}

main "$@"
