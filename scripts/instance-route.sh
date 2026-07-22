#!/bin/bash
# ============================================================================
# instance-route.sh - Instance Route lifecycle CLI (dispatch skeleton)
# ============================================================================
# Usage:
#   ./scripts/instance-route.sh <register|verify|status|unregister> [options]
#
# Options:
#   --instance-id <lowercase-alphanumeric, 1-8 chars>
#   --instance-resource-group <name>
#   --static-web-app-name <name>
#   --platform-resource-group <name>
#   --front-door-profile <name>
#   --subscription-id <uuid>
#   --origin-hostname <hostname>   (register only; optional override)
#   --confirm                      (required for unregister)
#
# See specs/001-multi-instance-platform/contracts/instance-route-cli.md.
#
# SCOPE NOTE: This is the Foundational-phase command dispatcher (usage
# parsing, validation, envelope emission). Full register/verify/unregister
# automation is implemented by later User Story 2 tasks (T033-T035) and is
# NOT part of this version. Until then:
#   - `status` performs a real, read-only Azure lookup.
#   - `register`, `verify`, and `unregister` return a clear "not yet
#     implemented" failure that points to the direct Bicep deployment
#     harness (infra/platform/instance-route.bicep) documented in
#     tests/infrastructure/integration/README.md, which IS fully usable
#     today for User Story 1 validation.
#
# Bash 3.2 compatible. Writes human-readable progress to stderr and exactly
# one JSON document (matching
# tests/infrastructure/contracts/instance-route-output.schema.json) to
# stdout.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/azure-common.sh
. "$SCRIPT_DIR/lib/azure-common.sh"

DATA_KEY_INSTANCE="instance"
DATA_KEY_ROUTE="route"

usage() {
  cat >&2 <<'USAGE'
Usage: instance-route.sh <register|verify|status|unregister> [options]
  --instance-id <lowercase-alphanumeric, 1-8 chars>
  --instance-resource-group <name>
  --static-web-app-name <name>
  --platform-resource-group <name>
  --front-door-profile <name>
  --subscription-id <uuid>
  --origin-hostname <hostname>   (register only; optional override)
  --confirm                      (required for unregister)
USAGE
}

# emit envelopes with BOTH instance and route data keys populated (this
# script's schema requires both keys present, each independently nullable).
emit_envelope() {
  action="$1"
  status="$2"
  op_id="$3"
  instance_json="$4"
  route_json="$5"
  diagnostics_json="${6:-[]}"

  require_cmd jq
  jq -n \
    --arg action "$action" \
    --arg status "$status" \
    --arg operationId "$op_id" \
    --argjson instance "$instance_json" \
    --argjson route "$route_json" \
    --argjson diagnostics "$diagnostics_json" \
    '{
      schemaVersion: "1.0",
      action: $action,
      status: $status,
      operationId: $operationId,
      instance: $instance,
      route: $route,
      diagnostics: $diagnostics
    }'
}

fail_route() {
  action="$1"; op_id="$2"; code="$3"; message="$4"
  emit_envelope "$action" "Failed" "$op_id" "null" "null" "$(diagnostic_array "$code" "$message")"
  log_error "$message" || true
  exit 1
}

ACTION="${1:-}"
[ -n "$ACTION" ] || { usage; exit 2; }
shift || true

case "$ACTION" in
  register|verify|status|unregister) ;;
  *)
    usage
    fail_route "$ACTION" "$(operation_id route unknown)" "UNKNOWN_ACTION" "Unknown action: $ACTION"
    ;;
esac

INSTANCE_ID=""
INSTANCE_RESOURCE_GROUP=""
STATIC_WEB_APP_NAME=""
PLATFORM_RESOURCE_GROUP=""
FRONT_DOOR_PROFILE=""
SUBSCRIPTION_ID=""
ORIGIN_HOSTNAME=""
CONFIRM=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance-id) INSTANCE_ID="${2:-}"; shift 2 ;;
    --instance-resource-group) INSTANCE_RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --static-web-app-name) STATIC_WEB_APP_NAME="${2:-}"; shift 2 ;;
    --platform-resource-group) PLATFORM_RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --front-door-profile) FRONT_DOOR_PROFILE="${2:-}"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --origin-hostname) ORIGIN_HOSTNAME="${2:-}"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    *)
      usage
      fail_route "$ACTION" "$(operation_id route unknown)" "UNKNOWN_OPTION" "Unknown option: $1"
      ;;
  esac
done

require_value "--instance-id" "$INSTANCE_ID"
case "$INSTANCE_ID" in
  [a-z0-9]|[a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9][a-z0-9]|\
  [a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]|\
  [a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]) ;;
  *) fail_route "$ACTION" "$(operation_id route "$INSTANCE_ID")" "INVALID_INSTANCE_ID" "instance-id must match ^[a-z0-9]{1,8}\$" ;;
esac

OP_ID="$(operation_id route "$INSTANCE_ID")"

require_value "--platform-resource-group" "$PLATFORM_RESOURCE_GROUP"
require_value "--front-door-profile" "$FRONT_DOOR_PROFILE"
require_value "--subscription-id" "$SUBSCRIPTION_ID"

NOT_IMPLEMENTED_MESSAGE="Not yet implemented in scripts/instance-route.sh. Use the direct Bicep deployment harness (infra/platform/instance-route.bicep) documented in tests/infrastructure/integration/README.md, or wait for the User Story 2 automation tasks (T033-T035)."

cmd_status() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  route_name="route-${INSTANCE_ID}"

  endpoint_nm=$(az cdn afd endpoint list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?tags.instanceId=='${INSTANCE_ID}'] | [0].name" -o tsv 2>/dev/null)

  if [ -z "$endpoint_nm" ] || [ "$endpoint_nm" = "None" ]; then
    emit_envelope "$ACTION" "NoChange" "$OP_ID" "null" "null"
    return 0
  fi

  route_json=$(az cdn afd route show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint_nm" \
    --route-name "$route_name" \
    --subscription "$SUBSCRIPTION_ID" \
    -o json 2>/dev/null)

  if [ -z "$route_json" ]; then
    emit_envelope "$ACTION" "NoChange" "$OP_ID" "null" "null"
    return 0
  fi

  endpoint_hostname=$(az cdn afd endpoint list --resource-group "$PLATFORM_RESOURCE_GROUP" --profile-name "$FRONT_DOOR_PROFILE" --subscription "$SUBSCRIPTION_ID" --query "[?tags.instanceId=='${INSTANCE_ID}'] | [0].hostName" -o tsv 2>/dev/null)

  instance_json=$(jq -n \
    --arg instanceId "$INSTANCE_ID" \
    --arg resourceGroupName "${INSTANCE_RESOURCE_GROUP:-}" \
    --arg staticWebAppName "${STATIC_WEB_APP_NAME:-}" \
    --arg originHostName "${ORIGIN_HOSTNAME:-}" \
    '{instanceId: $instanceId, resourceGroupName: $resourceGroupName, staticWebAppName: $staticWebAppName, originHostName: $originHostName}')

  route_obj=$(echo "$route_json" | jq \
    --arg endpointName "$endpoint_nm" \
    --arg endpointHostName "$endpoint_hostname" \
    --arg originGroupName "og-${INSTANCE_ID}" \
    --arg originName "origin-${INSTANCE_ID}" \
    --arg routeName "$route_name" \
    '{
      endpointName: $endpointName,
      endpointHostName: $endpointHostName,
      url: ("https://" + $endpointHostName),
      originGroupName: $originGroupName,
      originName: $originName,
      routeName: $routeName,
      provisioningState: (.provisioningState // "Succeeded")
    }')

  emit_envelope "$ACTION" "Succeeded" "$OP_ID" "$instance_json" "$route_obj"
}

case "$ACTION" in
  status) cmd_status ;;
  register|verify|unregister)
    fail_route "$ACTION" "$OP_ID" "NOT_IMPLEMENTED" "$NOT_IMPLEMENTED_MESSAGE"
    ;;
esac
