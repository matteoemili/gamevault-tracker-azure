#!/bin/bash
# Opt-in Azure integration test for shared-service coexistence with legacy
# instances. It snapshots legacy route/origin resources and public responses,
# deploys and verifies the shared service, performs a shared rollback command
# when provided, and asserts the legacy snapshots are unchanged.
# Bash 3.2 compatible.

set -u
set -o pipefail

if [ "${RUN_AZURE_INTEGRATION:-}" != "1" ]; then
  echo "[legacy-coexistence] skip: set RUN_AZURE_INTEGRATION=1 to run Azure coexistence validation"
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR" || exit 1

fail() {
  echo "[legacy-coexistence] FAIL: $*" >&2
  exit 1
}

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  [ -n "$value" ] || fail "missing required environment variable: $name"
}

snapshot_route_origin() {
  prefix="$1"
  endpoint_var="${prefix}_ENDPOINT_NAME"
  route_var="${prefix}_ROUTE_NAME"
  origin_group_var="${prefix}_ORIGIN_GROUP_NAME"
  origin_var="${prefix}_ORIGIN_NAME"
  eval "endpoint=\${$endpoint_var:-}"
  eval "route=\${$route_var:-}"
  eval "origin_group=\${$origin_group_var:-}"
  eval "origin=\${$origin_var:-}"
  [ -n "$endpoint" ] || fail "missing $endpoint_var"
  [ -n "$route" ] || fail "missing $route_var"
  [ -n "$origin_group" ] || fail "missing $origin_group_var"
  [ -n "$origin" ] || fail "missing $origin_var"

  az afd route show \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint" \
    --route-name "$route" \
    --query "{id:id,originGroup:originGroup.id,patternsToMatch:patternsToMatch,customDomains:customDomains[].id,enabledState:enabledState}" \
    -o json

  az afd origin show \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --origin-group-name "$origin_group" \
    --origin-name "$origin" \
    --query "{id:id,hostName:hostName,originHostHeader:originHostHeader,httpPort:httpPort,httpsPort:httpsPort,enabledState:enabledState}" \
    -o json
}

snapshot_response() {
  url="$1"
  curl --fail --silent --show-error --location "$url" | shasum -a 256 | awk '{print $1}'
}

assert_same() {
  label="$1"
  before="$2"
  after="$3"
  if [ "$before" != "$after" ]; then
    fail "$label changed during shared-service deployment/rollback"
  fi
}

require_env AZURE_SUBSCRIPTION_ID
require_env ENVIRONMENT
require_env AZURE_LOCATION
require_env SHARED_RESOURCE_GROUP
require_env PLATFORM_RESOURCE_GROUP
require_env FRONT_DOOR_PROFILE
require_env LEGACY_A_URL
require_env LEGACY_B_URL

echo "[legacy-coexistence] capturing legacy snapshots"
LEGACY_A_RESOURCE_BEFORE="$(snapshot_route_origin LEGACY_A)"
LEGACY_B_RESOURCE_BEFORE="$(snapshot_route_origin LEGACY_B)"
LEGACY_A_RESPONSE_BEFORE="$(snapshot_response "$LEGACY_A_URL")"
LEGACY_B_RESPONSE_BEFORE="$(snapshot_response "$LEGACY_B_URL")"

echo "[legacy-coexistence] deploying shared service"
./scripts/shared-service.sh deploy \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RESOURCE_GROUP" \
  --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$FRONT_DOOR_PROFILE" \
  --location "$AZURE_LOCATION" \
  --confirm \
  --non-interactive >/dev/null

./scripts/shared-service.sh verify \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RESOURCE_GROUP" \
  --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$FRONT_DOOR_PROFILE" >/dev/null

if [ -n "${SHARED_ROLLBACK_COMMAND:-}" ]; then
  echo "[legacy-coexistence] running provided shared rollback command"
  sh -c "$SHARED_ROLLBACK_COMMAND"
else
  echo "[legacy-coexistence] no SHARED_ROLLBACK_COMMAND provided; using idempotent shared redeploy as rollback proof"
  ./scripts/shared-service.sh deploy \
    --environment "$ENVIRONMENT" \
    --subscription-id "$AZURE_SUBSCRIPTION_ID" \
    --shared-resource-group "$SHARED_RESOURCE_GROUP" \
    --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
    --front-door-profile "$FRONT_DOOR_PROFILE" \
    --location "$AZURE_LOCATION" \
    --confirm \
    --non-interactive >/dev/null
fi

echo "[legacy-coexistence] verifying legacy snapshots are unchanged"
LEGACY_A_RESOURCE_AFTER="$(snapshot_route_origin LEGACY_A)"
LEGACY_B_RESOURCE_AFTER="$(snapshot_route_origin LEGACY_B)"
LEGACY_A_RESPONSE_AFTER="$(snapshot_response "$LEGACY_A_URL")"
LEGACY_B_RESPONSE_AFTER="$(snapshot_response "$LEGACY_B_URL")"

assert_same "legacy A route/origin resource snapshot" "$LEGACY_A_RESOURCE_BEFORE" "$LEGACY_A_RESOURCE_AFTER"
assert_same "legacy B route/origin resource snapshot" "$LEGACY_B_RESOURCE_BEFORE" "$LEGACY_B_RESOURCE_AFTER"
assert_same "legacy A public response hash" "$LEGACY_A_RESPONSE_BEFORE" "$LEGACY_A_RESPONSE_AFTER"
assert_same "legacy B public response hash" "$LEGACY_B_RESPONSE_BEFORE" "$LEGACY_B_RESPONSE_AFTER"

echo "[legacy-coexistence] legacy coexistence passed"
