#!/bin/bash
# ============================================================================
# instance-route.sh - Instance Route lifecycle CLI
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
#   --environment <dev|staging|prod> (register only)
#   --base-name <name>             (register only; default: gvt)
#   --origin-hostname <hostname>   (register only; optional override)
#   --forwarding-config-file <path> (register only; optional)
#   --confirm                      (required for unregister)
#
# See specs/001-multi-instance-platform/contracts/instance-route-cli.md.
#
# `register` validates the instance origin, runs Azure validation and what-if,
# then deploys only that instance's deterministic Front Door resource graph.
# `verify` performs read-only association and endpoint checks. Guarded
# deregistration is deferred to User Story 3 (T052).
#
# Bash 3.2 compatible. Writes human-readable progress to stderr and exactly
# one JSON document (matching
# tests/infrastructure/contracts/instance-route-output.schema.json) to
# stdout.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$PROJECT_ROOT/infra/platform/instance-route.bicep"

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
  --environment <dev|staging|prod>      (register only)
  --base-name <name>                    (register only; default: gvt)
  --origin-hostname <hostname>   (register only; optional override)
  --forwarding-config-file <path>       (register only; optional)
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
ENVIRONMENT=""
BASE_NAME="gvt"
ORIGIN_HOSTNAME=""
FORWARDING_CONFIG_FILE=""
CONFIRM=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance-id) INSTANCE_ID="${2:-}"; shift 2 ;;
    --instance-resource-group) INSTANCE_RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --static-web-app-name) STATIC_WEB_APP_NAME="${2:-}"; shift 2 ;;
    --platform-resource-group) PLATFORM_RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --front-door-profile) FRONT_DOOR_PROFILE="${2:-}"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --base-name) BASE_NAME="${2:-gvt}"; shift 2 ;;
    --origin-hostname) ORIGIN_HOSTNAME="${2:-}"; shift 2 ;;
    --forwarding-config-file) FORWARDING_CONFIG_FILE="${2:-}"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    *)
      usage
      fail_route "$ACTION" "$(operation_id route unknown)" "UNKNOWN_OPTION" "Unknown option: $1"
      ;;
  esac
done

[ -n "$INSTANCE_ID" ] || fail_route "$ACTION" "$(operation_id route unknown)" "MISSING_REQUIRED_OPTION" "missing value for required option: --instance-id"
case "$INSTANCE_ID" in
  [a-z0-9]|[a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9][a-z0-9]|\
  [a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]|\
  [a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]|[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]) ;;
  *) fail_route "$ACTION" "$(operation_id route "$INSTANCE_ID")" "INVALID_INSTANCE_ID" "instance-id must match ^[a-z0-9]{1,8}\$" ;;
esac

OP_ID="$(operation_id route "$INSTANCE_ID")"

[ -n "$PLATFORM_RESOURCE_GROUP" ] || fail_route "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --platform-resource-group"
[ -n "$FRONT_DOOR_PROFILE" ] || fail_route "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --front-door-profile"
[ -n "$SUBSCRIPTION_ID" ] || fail_route "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --subscription-id"
[ -n "$INSTANCE_RESOURCE_GROUP" ] || fail_route "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --instance-resource-group"
[ -n "$STATIC_WEB_APP_NAME" ] || fail_route "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --static-web-app-name"

SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

endpoint_for_instance() {
  az afd endpoint list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?tags.instanceId=='${INSTANCE_ID}'] | [0]" \
    -o json 2>/dev/null
}

route_object_from_azure() {
  endpoint_json="$1"
  endpoint_name=$(echo "$endpoint_json" | jq -r '.name // empty')
  endpoint_hostname=$(echo "$endpoint_json" | jq -r '.hostName // empty')
  [ -n "$endpoint_name" ] && [ -n "$endpoint_hostname" ] || return 1

  route_json=$(az afd route show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint_name" \
    --route-name "route-${INSTANCE_ID}" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || return 1

  echo "$route_json" | jq \
    --arg endpointName "$endpoint_name" \
    --arg endpointHostName "$endpoint_hostname" \
    --arg originGroupName "og-${INSTANCE_ID}" \
    --arg originName "origin-${INSTANCE_ID}" \
    --arg routeName "route-${INSTANCE_ID}" \
    '{
      endpointName: $endpointName,
      endpointHostName: $endpointHostName,
      url: ("https://" + $endpointHostName),
      originGroupName: $originGroupName,
      originName: $originName,
      routeName: $routeName,
      provisioningState: (.provisioningState // "Succeeded")
    }'
}

instance_object() {
  jq -n \
    --arg instanceId "$INSTANCE_ID" \
    --arg resourceGroupName "$INSTANCE_RESOURCE_GROUP" \
    --arg staticWebAppName "$STATIC_WEB_APP_NAME" \
    --arg originHostName "$ORIGIN_HOSTNAME" \
    '{instanceId: $instanceId, resourceGroupName: $resourceGroupName, staticWebAppName: $staticWebAppName, originHostName: $originHostName}'
}

write_forwarding_gateway_config() {
  endpoint_hostname="$1"
  front_door_id=$(az afd profile show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" \
    --query 'frontDoorId' -o tsv 2>/dev/null)

  if [ -z "$front_door_id" ] || [ "$front_door_id" = "None" ]; then
    log_warn "could not resolve frontDoorId; skipping forwarding-gateway config generation"
    return 0
  fi

  output_file="$FORWARDING_CONFIG_FILE"
  if [ -z "$output_file" ]; then
    output_file="$PROJECT_ROOT/.forwarding-gateway/${INSTANCE_ID}.json"
  fi
  mkdir -p "$(dirname "$output_file")"

  jq -n \
    --arg instanceId "$INSTANCE_ID" \
    --arg frontDoorId "$front_door_id" \
    --arg endpointHostName "$endpoint_hostname" \
    --arg backendServiceTag 'AzureFrontDoor.Backend' \
    '{
      instanceId: $instanceId,
      frontDoorId: $frontDoorId,
      backendServiceTag: $backendServiceTag,
      endpointHostName: $endpointHostName,
      staticWebAppConfig: {
        forwardingGateway: {
          requiredHeaders: {"X-Azure-FDID": $frontDoorId},
          allowedForwardedHosts: [$endpointHostName]
        }
      }
    }' > "$output_file"
  log_success "forwarding-gateway config written to $output_file"
}

cmd_register() {
  [ -n "$ENVIRONMENT" ] || fail_route "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --environment"
  case "$ENVIRONMENT" in
    dev|staging|prod) ;;
    *) fail_route "$ACTION" "$OP_ID" "INVALID_ENVIRONMENT" "environment must be one of: dev, staging, prod" ;;
  esac
  if [ "$INSTANCE_RESOURCE_GROUP" = "$PLATFORM_RESOURCE_GROUP" ]; then
    fail_route "$ACTION" "$OP_ID" "INVALID_INSTANCE_SCOPE" "Instance resource group must be distinct from the shared platform resource group"
  fi
  if [ -n "$ORIGIN_HOSTNAME" ]; then
    case "$ORIGIN_HOSTNAME" in
      *.azurestaticapps.net) ;;
      *) fail_route "$ACTION" "$OP_ID" "INVALID_ORIGIN_HOSTNAME" "origin hostname must end in .azurestaticapps.net" ;;
    esac
  fi

  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$INSTANCE_RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_route "$ACTION" "$OP_ID" "INSTANCE_RESOURCE_GROUP_NOT_FOUND" "Instance resource group '$INSTANCE_RESOURCE_GROUP' does not exist"
  fi

  swa_json=$(az staticwebapp show \
    --name "$STATIC_WEB_APP_NAME" \
    --resource-group "$INSTANCE_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null)
  if [ -z "$swa_json" ]; then
    fail_route "$ACTION" "$OP_ID" "STATIC_WEB_APP_NOT_FOUND" "Static Web App '$STATIC_WEB_APP_NAME' was not found in resource group '$INSTANCE_RESOURCE_GROUP'"
  fi
  if [ "$(echo "$swa_json" | jq -r '.type // empty')" != "Microsoft.Web/staticSites" ]; then
    fail_route "$ACTION" "$OP_ID" "INVALID_RESOURCE_TYPE" "Resource '$STATIC_WEB_APP_NAME' is not a Microsoft.Web/staticSites resource"
  fi

  if [ -z "$ORIGIN_HOSTNAME" ]; then
    ORIGIN_HOSTNAME=$(echo "$swa_json" | jq -r '.defaultHostname // empty')
  fi
  case "$ORIGIN_HOSTNAME" in
    *.azurestaticapps.net) ;;
    *) fail_route "$ACTION" "$OP_ID" "INVALID_ORIGIN_HOSTNAME" "origin hostname must end in .azurestaticapps.net" ;;
  esac

  log_info "checking origin HTTPS reachability: https://${ORIGIN_HOSTNAME}/"
  if ! curl -fsS -o /dev/null --max-time 15 "https://${ORIGIN_HOSTNAME}/" 2>"$SCRATCH_DIR/origin.err"; then
    origin_error=$(mask_secrets < "$SCRATCH_DIR/origin.err")
    fail_route "$ACTION" "$OP_ID" "ORIGIN_UNREACHABLE" "Origin hostname is not HTTPS reachable: $origin_error"
  fi

  if ! az afd profile show --resource-group "$PLATFORM_RESOURCE_GROUP" --profile-name "$FRONT_DOOR_PROFILE" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_route "$ACTION" "$OP_ID" "FRONT_DOOR_PROFILE_NOT_FOUND" "Front Door profile '$FRONT_DOOR_PROFILE' does not exist in resource group '$PLATFORM_RESOURCE_GROUP'"
  fi

  endpoints_json=$(az afd endpoint list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || \
    fail_route "$ACTION" "$OP_ID" "ENDPOINT_LIST_FAILED" "Could not list Front Door endpoints"

  endpoint_name="$(echo "$BASE_NAME" | tr '[:upper:]' '[:lower:]')-${ENVIRONMENT}-${INSTANCE_ID}"
  conflict_count=$(echo "$endpoints_json" | jq --arg name "$endpoint_name" --arg id "$INSTANCE_ID" '[.[] | select(.name == $name and (.tags.instanceId // "") != $id)] | length')
  if [ "$conflict_count" -gt 0 ]; then
    fail_route "$ACTION" "$OP_ID" "ENDPOINT_NAME_CONFLICT" "Endpoint name '$endpoint_name' is already owned by a different instance"
  fi

  existing_endpoint=$(echo "$endpoints_json" | jq -c --arg id "$INSTANCE_ID" '[.[] | select(.tags.instanceId == $id)] | .[0] // null')
  endpoint_count=$(echo "$endpoints_json" | jq 'length')
  if [ "$existing_endpoint" = "null" ] && [ "$endpoint_count" -ge 25 ]; then
    fail_route "$ACTION" "$OP_ID" "ENDPOINT_CAPACITY_EXCEEDED" "Front Door profile already has $endpoint_count endpoints (limit: 25)"
  fi

  tags_json=$(jq -n \
    --arg application 'GameVault Tracker' \
    --arg environment "$ENVIRONMENT" \
    --arg instanceResourceGroup "$INSTANCE_RESOURCE_GROUP" \
    --arg staticWebAppName "$STATIC_WEB_APP_NAME" \
    --arg managedBy 'scripts/instance-route.sh' \
    '{application: $application, environment: $environment, instanceResourceGroup: $instanceResourceGroup, staticWebAppName: $staticWebAppName, managedBy: $managedBy}')

  common_parameters=(
    "instanceId=$INSTANCE_ID"
    "environment=$ENVIRONMENT"
    "baseName=$BASE_NAME"
    "frontDoorProfileName=$FRONT_DOOR_PROFILE"
    "instanceResourceGroupName=$INSTANCE_RESOURCE_GROUP"
    "instanceSubscriptionId=$SUBSCRIPTION_ID"
    "staticWebAppName=$STATIC_WEB_APP_NAME"
    "originHostNameOverride=$ORIGIN_HOSTNAME"
    "tags=$tags_json"
  )

  log_info "running Azure deployment validation (no resources are mutated)"
  if ! az deployment group validate \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "${common_parameters[@]}" \
    -o none 2>"$SCRATCH_DIR/validate.err"; then
    validation_error=$(mask_secrets < "$SCRATCH_DIR/validate.err")
    fail_route "$ACTION" "$OP_ID" "AZURE_VALIDATION_FAILED" "Deployment validation failed; no route was changed: $validation_error"
  fi

  log_info "running Azure what-if (no resources are mutated)"
  if ! whatif_json=$(az deployment group what-if \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "${common_parameters[@]}" \
    --result-format FullResourcePayloads --no-pretty-print -o json 2>"$SCRATCH_DIR/whatif.err"); then
    whatif_error=$(mask_secrets < "$SCRATCH_DIR/whatif.err")
    fail_route "$ACTION" "$OP_ID" "AZURE_WHATIF_FAILED" "What-if failed; no route was changed: $whatif_error"
  fi
  change_count=$(echo "$whatif_json" | jq '[.changes[]? | select(.changeType != "NoChange" and .changeType != "Ignore")] | length')

  deployment_name="instance-route-${INSTANCE_ID}"
  if [ "$change_count" -gt 0 ]; then
    log_info "deploying deterministic instance route: $deployment_name"
    if ! az deployment group create \
      --name "$deployment_name" \
      --resource-group "$PLATFORM_RESOURCE_GROUP" \
      --subscription "$SUBSCRIPTION_ID" \
      --template-file "$TEMPLATE_FILE" \
      --parameters "${common_parameters[@]}" \
      --mode Incremental -o none 2>"$SCRATCH_DIR/deploy.err"; then
      deploy_error=$(mask_secrets < "$SCRATCH_DIR/deploy.err")
      fail_route "$ACTION" "$OP_ID" "AZURE_DEPLOY_FAILED" "Deployment failed; a prior route, if present, was preserved: $deploy_error"
    fi
    result_status="Succeeded"
  else
    log_success "what-if reports no changes; converged"
    result_status="NoChange"
  fi

  endpoint_json=$(endpoint_for_instance)
  route_json=$(route_object_from_azure "$endpoint_json") || \
    fail_route "$ACTION" "$OP_ID" "ROUTE_LOOKUP_FAILED" "Registration completed but the expected endpoint or route could not be read"
  instance_json=$(instance_object)

  # Do not harden the origin until the generated endpoint itself is reachable.
  endpoint_hostname=$(echo "$route_json" | jq -r '.endpointHostName')
  if curl -fsS -o /dev/null --max-time 15 "https://${endpoint_hostname}/" 2>/dev/null; then
    write_forwarding_gateway_config "$endpoint_hostname"
    emit_envelope "$ACTION" "$result_status" "$OP_ID" "$instance_json" "$route_json"
  else
    diagnostics=$(diagnostic_array "ENDPOINT_VERIFICATION_PENDING" "Route deployed but the Front Door endpoint is not reachable yet; forwarding-gateway configuration was not generated")
    emit_envelope "$ACTION" "Degraded" "$OP_ID" "$instance_json" "$route_json" "$diagnostics"
  fi
}

cmd_verify() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  endpoint_json=$(endpoint_for_instance)
  if [ -z "$endpoint_json" ] || [ "$endpoint_json" = "null" ]; then
    fail_route "$ACTION" "$OP_ID" "ROUTE_NOT_FOUND" "No endpoint is registered for instance '$INSTANCE_ID'"
  fi
  route_json=$(route_object_from_azure "$endpoint_json") || \
    fail_route "$ACTION" "$OP_ID" "ROUTE_NOT_FOUND" "No matching route is registered for instance '$INSTANCE_ID'"

  endpoint_hostname=$(echo "$route_json" | jq -r '.endpointHostName')
  provisioning_state=$(echo "$route_json" | jq -r '.provisioningState')
  origin_json=$(az afd origin show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --origin-group-name "og-${INSTANCE_ID}" \
    --origin-name "origin-${INSTANCE_ID}" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || origin_json='{}'
  origin_host_header=$(echo "$origin_json" | jq -r '.originHostHeader // empty')
  if [ -z "$ORIGIN_HOSTNAME" ]; then
    ORIGIN_HOSTNAME="$origin_host_header"
  fi

  diagnostics='[]'
  failures=0
  add_failure() {
    diagnostics=$(echo "$diagnostics" | jq --arg code "$1" --arg message "$2" '. + [{code: $code, message: $message}]')
    failures=$((failures + 1))
  }
  [ "$provisioning_state" = "Succeeded" ] || add_failure "ROUTE_NOT_PROVISIONED" "Route provisioning state is '$provisioning_state'"
  [ -n "$origin_host_header" ] || add_failure "ORIGIN_NOT_FOUND" "The expected application origin could not be read"
  [ -z "$ORIGIN_HOSTNAME" ] || [ "$origin_host_header" = "$ORIGIN_HOSTNAME" ] || add_failure "ORIGIN_HOST_HEADER_MISMATCH" "Origin host header does not match the expected Static Web App hostname"

  http_status=$(curl -s -o /dev/null -w '%{http_code}' --max-redirs 0 --max-time 15 "http://${endpoint_hostname}/" 2>/dev/null)
  case "$http_status" in 301|302|307|308) ;; *) add_failure "HTTPS_REDIRECT_MISSING" "Expected an HTTP redirect, received status ${http_status:-<none>}" ;; esac
  https_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://${endpoint_hostname}/" 2>/dev/null)
  case "$https_status" in 2*|3*) ;; *) add_failure "ENDPOINT_RESPONSE_UNHEALTHY" "Expected a 2xx/3xx endpoint response, received status ${https_status:-<none>}" ;; esac

  instance_json=$(instance_object)
  if [ "$failures" -eq 0 ]; then
    write_forwarding_gateway_config "$endpoint_hostname"
    emit_envelope "$ACTION" "Succeeded" "$OP_ID" "$instance_json" "$route_json" "$diagnostics"
  else
    emit_envelope "$ACTION" "Degraded" "$OP_ID" "$instance_json" "$route_json" "$diagnostics"
  fi
}

NOT_IMPLEMENTED_MESSAGE="Guarded deregistration is delivered by User Story 3 (T052). Use the direct Bicep deployment harness documented in tests/infrastructure/integration/README.md until then."

cmd_status() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  route_name="route-${INSTANCE_ID}"

  endpoint_nm=$(az afd endpoint list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?tags.instanceId=='${INSTANCE_ID}'] | [0].name" -o tsv 2>/dev/null)

  if [ -z "$endpoint_nm" ] || [ "$endpoint_nm" = "None" ]; then
    emit_envelope "$ACTION" "NoChange" "$OP_ID" "null" "null"
    return 0
  fi

  route_json=$(az afd route show \
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

  origin_json=$(az afd origin show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --origin-group-name "og-${INSTANCE_ID}" \
    --origin-name "origin-${INSTANCE_ID}" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || origin_json='{}'
  if [ -z "$ORIGIN_HOSTNAME" ]; then
    ORIGIN_HOSTNAME=$(echo "$origin_json" | jq -r '.originHostHeader // empty')
  fi
  if [ -z "$ORIGIN_HOSTNAME" ]; then
    fail_route "$ACTION" "$OP_ID" "ORIGIN_NOT_FOUND" "Route exists but its application origin could not be read"
  fi

  endpoint_hostname=$(az afd endpoint list --resource-group "$PLATFORM_RESOURCE_GROUP" --profile-name "$FRONT_DOOR_PROFILE" --subscription "$SUBSCRIPTION_ID" --query "[?tags.instanceId=='${INSTANCE_ID}'] | [0].hostName" -o tsv 2>/dev/null)

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
  register) cmd_register ;;
  verify) cmd_verify ;;
  unregister) fail_route "$ACTION" "$OP_ID" "NOT_IMPLEMENTED" "$NOT_IMPLEMENTED_MESSAGE" ;;
esac
