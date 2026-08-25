#!/bin/bash
# ============================================================================
# shared-service.sh - Shared Entry Scale service lifecycle CLI
# ============================================================================
# Usage:
#   ./scripts/shared-service.sh <validate|what-if|deploy|verify|status|inventory> [options]
#
# Options:
#   --environment <dev|staging|prod>        (required for all actions)
#   --subscription-id <uuid>                (required unless --local-only)
#   --shared-resource-group <name>          (required unless --local-only)
#   --platform-resource-group <name>        (required for route actions)
#   --front-door-profile <name>             (required for route actions)
#   --location <azure-region>               (required for first deploy)
#   --base-name <name>                      (optional, defaults to "gvt")
#   --local-only                            (validate only: skip Azure, offline build)
#   --confirm                               (required for deploy)
#   --non-interactive                       (informational; --confirm still required)
#
# Deploys and validates the ONE shared GameVault application behind the ONE
# shared Front Door entry point for an environment. There is no instance
# identifier anywhere in this CLI: adding a logical instance is a Table
# Storage data operation handled by scripts/logical-instance.sh, and must
# never deploy infrastructure.
#
# This CLI never enumerates, mutates, or deletes legacy per-instance
# resources. scripts/instance-route.sh and infra/main.bicep remain the
# explicit legacy-only paths for existing instances.
#
# See specs/003-shared-entry-scale/contracts/shared-service-cli.md for the
# full command contract and specs/003-shared-entry-scale/quickstart.md for
# end-to-end usage.
#
# Bash 3.2 compatible. Writes human-readable progress to stderr and exactly
# one JSON document (matching
# tests/infrastructure/contracts/shared-service-output.schema.json) to stdout.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SHARED_DIR="$PROJECT_ROOT/infra/shared"
PLATFORM_DIR="$PROJECT_ROOT/infra/platform"
SHARED_TEMPLATE="$SHARED_DIR/main.bicep"
ROUTE_TEMPLATE="$PLATFORM_DIR/shared-route.bicep"
FORWARDING_GATEWAY_ARTIFACT="$PROJECT_ROOT/shared-forwarding-gateway.json"
STATICWEBAPP_CONFIG_FILE="$PROJECT_ROOT/public/staticwebapp.config.json"
STATICWEBAPP_DIST_CONFIG_FILE="$PROJECT_ROOT/dist/staticwebapp.config.json"

# shellcheck source=scripts/lib/azure-common.sh
. "$SCRIPT_DIR/lib/azure-common.sh"

DATA_KEY="sharedService"

usage() {
  cat >&2 <<'USAGE'
Usage: shared-service.sh <validate|what-if|deploy|verify|status|inventory> [options]
  --environment <dev|staging|prod>
  --subscription-id <uuid>
  --shared-resource-group <name>
  --platform-resource-group <name>
  --front-door-profile <name>
  --location <azure-region>
  --base-name <name>            (default: gvt)
  --local-only                  (validate only: skip Azure, offline Bicep build)
  --confirm                     (required for deploy)
  --non-interactive             (informational flag; --confirm still required)

deploy is idempotent: repeated runs converge on the same shared resources and
preserve the same public address. It never modifies legacy per-instance
deployments.
USAGE
}

action_label() {
  case "$1" in
    validate) echo "validate" ;;
    what-if) echo "what-if" ;;
    deploy) echo "deploy" ;;
    verify) echo "verify" ;;
    status) echo "status" ;;
    inventory) echo "inventory" ;;
    *) echo "validate" ;;
  esac
}

ACTION="${1:-}"
[ -n "$ACTION" ] || { usage; exit 2; }
shift || true

case "$ACTION" in
  validate|what-if|deploy|verify|status|inventory) ;;
  *)
    usage
    fail_fast "$DATA_KEY" "$(action_label "$ACTION")" "$(operation_id shared unknown)" "UNKNOWN_ACTION" "Unknown action: $ACTION"
    ;;
esac

ENVIRONMENT=""
SUBSCRIPTION_ID=""
SHARED_RESOURCE_GROUP=""
PLATFORM_RESOURCE_GROUP=""
FRONT_DOOR_PROFILE=""
LOCATION=""
BASE_NAME="gvt"
LOCAL_ONLY=0
CONFIRM=0
NON_INTERACTIVE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --shared-resource-group) SHARED_RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --platform-resource-group) PLATFORM_RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --front-door-profile) FRONT_DOOR_PROFILE="${2:-}"; shift 2 ;;
    --location) LOCATION="${2:-}"; shift 2 ;;
    --base-name) BASE_NAME="${2:-}"; shift 2 ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    *)
      usage
      fail_fast "$DATA_KEY" "$ACTION" "$(operation_id shared unknown)" "UNKNOWN_OPTION" "Unknown option: $1"
      ;;
  esac
done

: "$NON_INTERACTIVE"

OP_ID="$(operation_id shared "${ENVIRONMENT:-unknown}")"

[ -n "$ENVIRONMENT" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --environment"
case "$ENVIRONMENT" in
  dev|staging|prod) ;;
  *) fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "INVALID_ENVIRONMENT" "environment must be one of: dev, staging, prod" ;;
esac

PARAMS_FILE="$SHARED_DIR/main.${ENVIRONMENT}.bicepparam"

# --local-only is a validate-only affordance: every other action mutates or
# reads real Azure state and must not silently succeed offline.
if [ "$LOCAL_ONLY" -eq 1 ] && [ "$ACTION" != "validate" ]; then
  fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "LOCAL_ONLY_NOT_SUPPORTED" "--local-only is supported only by the validate action"
fi

if [ "$LOCAL_ONLY" -eq 0 ]; then
  [ -n "$SUBSCRIPTION_ID" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --subscription-id"
  [ -n "$SHARED_RESOURCE_GROUP" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --shared-resource-group"
fi

# Route-touching actions additionally need the shared platform coordinates.
case "$ACTION" in
  what-if|deploy|verify|status|inventory)
    if [ "$LOCAL_ONLY" -eq 0 ]; then
      [ -n "$PLATFORM_RESOURCE_GROUP" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --platform-resource-group"
      [ -n "$FRONT_DOOR_PROFILE" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --front-door-profile"
    fi
    ;;
esac

if [ "$SHARED_RESOURCE_GROUP" != "" ] && [ "$SHARED_RESOURCE_GROUP" = "$PLATFORM_RESOURCE_GROUP" ]; then
  fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "SCOPE_CONFLICT" "--shared-resource-group must differ from --platform-resource-group"
fi

SCRATCH_PARENT="$PROJECT_ROOT/.shared-service-scratch"
SCRATCH_DIR="$SCRATCH_PARENT/$$"
mkdir -p "$SCRATCH_PARENT"
rm -rf "$SCRATCH_DIR"
mkdir "$SCRATCH_DIR" || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "SCRATCH_CREATE_FAILED" "Unable to create local scratch directory"
trap 'rm -rf "$SCRATCH_DIR"; rmdir "$SCRATCH_PARENT" 2>/dev/null || true' EXIT

# ----------------------------------------------------------------------------
# Bicep helpers
# ----------------------------------------------------------------------------

bicep_local_build() {
  require_cmd az
  log_info "Building shared Bicep templates offline"
  az bicep build --file "$SHARED_TEMPLATE" --stdout >/dev/null 2>"$SCRATCH_DIR/bicep-build.err" || return 1
  az bicep build --file "$ROUTE_TEMPLATE" --stdout >/dev/null 2>>"$SCRATCH_DIR/bicep-build.err" || return 1
  return 0
}

# ----------------------------------------------------------------------------
# Deterministic naming (must match infra/shared/main.bicep and
# infra/platform/modules/shared-route.bicep)
# ----------------------------------------------------------------------------

shared_endpoint_name() {
  echo "$(echo "$BASE_NAME" | tr '[:upper:]' '[:lower:]')-${ENVIRONMENT}-shared"
}

SHARED_ORIGIN_GROUP_NAME="og-shared"
SHARED_ORIGIN_NAME="origin-shared"
SHARED_MAINTENANCE_ORIGIN_NAME="origin-shared-maintenance"
SHARED_ROUTE_NAME="route-shared"
SHARED_AUTH_ROUTE_NAME="route-shared-auth"

# ----------------------------------------------------------------------------
# Azure helpers
# ----------------------------------------------------------------------------

shared_swa_name() {
  az staticwebapp list \
    --resource-group "$SHARED_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[0].name" -o tsv 2>/dev/null
}

shared_swa_hostname() {
  az staticwebapp list \
    --resource-group "$SHARED_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[0].defaultHostname" -o tsv 2>/dev/null
}

shared_storage_name() {
  az storage account list \
    --resource-group "$SHARED_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[0].name" -o tsv 2>/dev/null
}

shared_endpoint_id() {
  endpoint_name="$(shared_endpoint_name)"
  echo "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${PLATFORM_RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONT_DOOR_PROFILE}/afdEndpoints/${endpoint_name}"
}

waf_policy_id() {
  echo "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${PLATFORM_RESOURCE_GROUP}/providers/Microsoft.Network/frontdoorWebApplicationFirewallPolicies/$(echo "$FRONT_DOOR_PROFILE" | tr -d '-')"
}

shared_waf_security_policy_name() {
  echo "waf-shared-${ENVIRONMENT}"
}

waf_associated_endpoint_ids() {
  endpoint_id="$(shared_endpoint_id)"
  policy_name="$(shared_waf_security_policy_name)"

  az afd endpoint list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" -o json >/dev/null 2>/dev/null || return 1

  security_policies_json=$(az afd security-policy list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || return 1

  echo "$security_policies_json" | jq -c \
    --arg policyName "$policy_name" \
    --arg endpointId "$endpoint_id" '
    [ .[]
      | select((.name // "" | ascii_downcase) == ($policyName | ascii_downcase))
      | .parameters.associations[]?.domains[]?.id
    ]
    + [$endpointId]
    | map(ascii_downcase)
    | unique'
}

waf_security_policy_name() {
  shared_waf_security_policy_name
}

maintenance_origin_hostname() {
  deployments_json=$(az deployment group list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || {
      echo ""
      return 0
    }
  deployment_name=$(echo "$deployments_json" | jq -r --arg prefix "gvt-platform-${ENVIRONMENT}-" \
    '[.[] | select(.name | startswith($prefix))] | sort_by(.properties.timestamp) | last.name // empty')
  if [ -z "$deployment_name" ]; then
    echo ""
    return 0
  fi
  az deployment group show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$deployment_name" \
    --query "properties.outputs.maintenanceOriginHostName.value" -o tsv 2>/dev/null
}

logical_instance_count() {
  storage_account="$1"
  if [ -z "$storage_account" ] || [ "$storage_account" = "None" ]; then
    echo 0
    return 0
  fi
  count=$(az storage entity query \
    --table-name "logicalinstances" \
    --account-name "$storage_account" \
    --auth-mode login \
    --filter "PartitionKey eq 'instance'" \
    --query "length(items)" -o tsv 2>/dev/null)
  if [ -z "$count" ] || [ "$count" = "None" ]; then
    echo 0
  else
    echo "$count"
  fi
}

# shared_service_object <inventory-json> <public-url-or-empty> <health-state>
# Builds the "sharedService" data object required by the schema.
shared_service_object() {
  inventory_json="$1"
  public_url="$2"
  health_state="$3"
  forwarding_state="${4:-Unknown}"
  forwarding_config_file="${5:-}"
  direct_origin_access="${6:-Unknown}"

  swa_id=$(echo "$inventory_json" | jq -r '.staticWebApps[0] // ""')
  storage_id=$(echo "$inventory_json" | jq -r '.storageAccounts[0] // ""')
  storage_name="${storage_id##*/}"
  endpoint_name="$(shared_endpoint_name)"
  endpoint_id=$(echo "$inventory_json" | jq -r --arg n "$endpoint_name" '[.endpoints[] | select(test("/" + $n + "$"))][0] // ""')
  origin_host=$(shared_swa_hostname 2>/dev/null || echo "")
  instance_count=$(logical_instance_count "$storage_name")
  profile_id=""
  if [ -n "$PLATFORM_RESOURCE_GROUP" ] && [ -n "$FRONT_DOOR_PROFILE" ]; then
    profile_id=$(az afd profile show \
      --resource-group "$PLATFORM_RESOURCE_GROUP" \
      --profile-name "$FRONT_DOOR_PROFILE" \
      --subscription "$SUBSCRIPTION_ID" \
      --query "id" -o tsv 2>/dev/null)
    [ "$profile_id" != "None" ] || profile_id=""
  fi

  # Only the shared Static Web Apps origin counts as an application origin;
  # the lower-priority maintenance fallback is operational plumbing.
  jq -n \
    --arg environment "$ENVIRONMENT" \
    --arg resourceGroupName "$SHARED_RESOURCE_GROUP" \
    --arg staticWebAppId "$swa_id" \
    --arg storageAccountId "$storage_id" \
    --arg frontDoorProfileId "${profile_id:-}" \
    --arg endpointId "$endpoint_id" \
    --arg originHostName "${origin_host:-}" \
    --arg healthState "$health_state" \
    --arg publicUrl "$public_url" \
    --arg forwardingState "$forwarding_state" \
    --arg forwardingConfigFile "$forwarding_config_file" \
    --arg directOriginAccess "$direct_origin_access" \
    --argjson logicalInstanceCount "$instance_count" \
    --argjson inventory "$inventory_json" \
    --arg originGroupName "$SHARED_ORIGIN_GROUP_NAME" \
    --arg originName "$SHARED_ORIGIN_NAME" \
    '{
      environment: $environment,
      resourceGroupName: $resourceGroupName,
      staticWebAppId: $staticWebAppId,
      storageAccountId: $storageAccountId,
      frontDoorProfileId: $frontDoorProfileId,
      endpointId: $endpointId,
      publicUrl: (if $publicUrl == "" then null else $publicUrl end),
      originHostName: $originHostName,
      healthState: $healthState,
      forwardingGateway: {
        state: $forwardingState,
        configFile: (if $forwardingConfigFile == "" then null else $forwardingConfigFile end),
        directOriginAccess: $directOriginAccess,
        requiredHeaderName: "X-Azure-FDID",
        allowedForwardedHost: (if $publicUrl == "" then null else ($publicUrl | sub("^https://"; "")) end)
      },
      logicalInstanceCount: $logicalInstanceCount,
      resourceCounts: {
        staticWebApps: ($inventory.counts.staticWebApps // 0),
        storageAccounts: ($inventory.counts.storageAccounts // 0),
        endpoints: ($inventory.counts.endpoints // 0),
        routes: ($inventory.counts.routes // 0),
        originGroups: ($inventory.counts.originGroups // 0),
        applicationOrigins: ([$inventory.origins[]? | select(contains("/originGroups/" + $originGroupName + "/origins/" + $originName))] | length)
      }
    }'
}

current_inventory() {
  capture_shared_inventory "$SUBSCRIPTION_ID" "$SHARED_RESOURCE_GROUP" "$PLATFORM_RESOURCE_GROUP" "$FRONT_DOOR_PROFILE"
}

current_public_url() {
  endpoint_name="$(shared_endpoint_name)"
  host=$(az afd endpoint show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint_name" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "hostName" -o tsv 2>/dev/null)
  if [ -n "$host" ] && [ "$host" != "None" ]; then
    echo "https://$host"
  else
    echo ""
  fi
}

ensure_shared_resource_group() {
  log_info "Ensuring shared resource group exists: $SHARED_RESOURCE_GROUP"
  az group show --name "$SHARED_RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1 && return 0
  if [ -z "$LOCATION" ]; then
    echo "shared resource group '$SHARED_RESOURCE_GROUP' does not exist; --location is required to create it" >&2
    return 1
  fi
  log_info "Creating shared resource group in $LOCATION"
  az group create \
    --name "$SHARED_RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --tags application="GameVault Tracker" environment="$ENVIRONMENT" managedBy="Bicep" component="shared-service" \
    >/dev/null || return 1
  return 0
}

azure_validate_shared() {
  log_info "Validating shared application deployment (no resources are mutated)"
  az deployment group validate \
    --resource-group "$SHARED_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --template-file "$SHARED_TEMPLATE" \
    --parameters "$PARAMS_FILE" \
    -o json
}

# whatif_change_count <resource-group> <template> <params...>
# Emits the number of non-NoChange, non-Ignore changes. Also writes the raw
# what-if document to $SCRATCH_DIR/whatif-raw.json so callers can inspect it
# for forbidden legacy mutations.
whatif_change_count() {
  wi_rg="$1"; shift
  wi_template="$1"; shift
  whatif_json=$(az deployment group what-if \
    --resource-group "$wi_rg" \
    --subscription "$SUBSCRIPTION_ID" \
    --template-file "$wi_template" \
    "$@" \
    --result-format FullResourcePayloads \
    --no-pretty-print \
    -o json) || return 1
  echo "$whatif_json" > "$SCRATCH_DIR/whatif-raw.json"
  echo "$whatif_json" | jq '[.changes[]? | select(.changeType != "NoChange" and .changeType != "Ignore")] | length'
}

# assert_no_legacy_mutation: fails when a what-if preview would delete or
# modify a legacy per-instance resource. FR-014 and SC-008 require that
# introducing the shared service never touches an existing instance.
assert_no_legacy_mutation() {
  : > "$SCRATCH_DIR/legacy-mutation.err"
  echo "LEGACY_MUTATION_DETECTED" > "$SCRATCH_DIR/legacy-mutation.code"
  if [ ! -f "$SCRATCH_DIR/whatif-raw.json" ]; then
    echo "WHATIF_PREVIEW_MISSING" > "$SCRATCH_DIR/legacy-mutation.code"
    echo "What-if preview was not captured; refusing to proceed without legacy-mutation evidence" > "$SCRATCH_DIR/legacy-mutation.err"
    return 1
  fi

  endpoint_name="$(shared_endpoint_name)"
  security_policy_name="$(shared_waf_security_policy_name)"
  offenders=$(jq -r \
    --arg endpointName "$endpoint_name" \
    --arg securityPolicyName "$security_policy_name" \
    --arg originGroupName "$SHARED_ORIGIN_GROUP_NAME" \
    --arg originName "$SHARED_ORIGIN_NAME" \
    --arg maintenanceOriginName "$SHARED_MAINTENANCE_ORIGIN_NAME" \
    --arg routeName "$SHARED_ROUTE_NAME" \
    --arg authRouteName "$SHARED_AUTH_ROUTE_NAME" '
    def leaf_name: (.resourceId // "" | split("/") | last | ascii_downcase);
    def is_shared_leaf:
      (leaf_name == ($endpointName | ascii_downcase)) or
      (leaf_name == ($originGroupName | ascii_downcase)) or
      (leaf_name == ($originName | ascii_downcase)) or
      (leaf_name == ($maintenanceOriginName | ascii_downcase)) or
      (leaf_name == ($routeName | ascii_downcase)) or
      (leaf_name == ($authRouteName | ascii_downcase));
    def is_security_policy: (.resourceId // "" | test("/securityPolicies/"; "i"));
    def is_shared_security_policy:
      is_security_policy and (leaf_name == ($securityPolicyName | ascii_downcase));
    [ .changes[]?
      | select(.changeType == "Delete" or .changeType == "Modify")
      | select(
          if .changeType == "Modify" then
            ((is_shared_leaf and (is_security_policy | not)) or is_shared_security_policy) | not
          else
            (is_shared_leaf and (is_security_policy | not)) | not
          end
        )
      | (.resourceId // "")
    ] | unique | join(", ")
  ' "$SCRATCH_DIR/whatif-raw.json" 2>/dev/null) || {
    echo "WHATIF_PREVIEW_INVALID" > "$SCRATCH_DIR/legacy-mutation.code"
    echo "What-if preview could not be parsed; refusing to proceed without legacy-mutation evidence" > "$SCRATCH_DIR/legacy-mutation.err"
    return 1
  }

  if [ -n "$offenders" ] && [ "$offenders" != "null" ]; then
    echo "What-if preview would delete or modify non-shared resources; refusing to proceed: $offenders" > "$SCRATCH_DIR/legacy-mutation.err"
    return 1
  fi
  return 0
}

legacy_mutation_code() {
  cat "$SCRATCH_DIR/legacy-mutation.code" 2>/dev/null || echo "LEGACY_MUTATION_DETECTED"
}

legacy_mutation_message() {
  cat "$SCRATCH_DIR/legacy-mutation.err" 2>/dev/null || echo "What-if preview failed the legacy-mutation guard"
}

if [ -n "${SHARED_SERVICE_TEST_ASSERT_NO_LEGACY_MUTATION:-}" ]; then
  cp "$SHARED_SERVICE_TEST_ASSERT_NO_LEGACY_MUTATION" "$SCRATCH_DIR/whatif-raw.json" || \
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "WHATIF_PREVIEW_MISSING" "Test what-if preview fixture could not be read"
  if assert_no_legacy_mutation; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "null"
    exit 0
  fi
  fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "$(legacy_mutation_code)" "$(legacy_mutation_message)"
fi

# configure_shared_cors <storage-account-name> <public-url>
# Allows the shared public origin to call Azure Table Storage from the
# browser. Delegates to the existing idempotent cors-add-origin.sh so there
# is one implementation of CORS rule merging in the repository.
configure_shared_cors() {
  cors_account="$1"
  cors_origin="$2"

  if [ -z "$cors_account" ] || [ "$cors_account" = "None" ]; then
    log_warn "Shared storage account not resolved; skipping CORS configuration"
    return 0
  fi
  if [ -z "$cors_origin" ]; then
    log_warn "Shared public URL not resolved; skipping CORS configuration"
    return 0
  fi

  log_info "Configuring shared-origin CORS on $cors_account"
  "$SCRIPT_DIR/cors-add-origin.sh" \
    --storage-account-name "$cors_account" \
    --resource-group "$SHARED_RESOURCE_GROUP" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --origin "$cors_origin" \
    >"$SCRATCH_DIR/cors.out" 2>"$SCRATCH_DIR/cors.err"
}

write_shared_forwarding_gateway_config() {
  endpoint_url="$1"
  endpoint_hostname="$(echo "$endpoint_url" | sed 's#^https://##; s#/$##')"
  [ -n "$endpoint_hostname" ] || return 1

  front_door_id=$(az afd profile show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" \
    --query 'frontDoorId' -o tsv 2>/dev/null)

  if [ -z "$front_door_id" ] || [ "$front_door_id" = "None" ]; then
    log_warn "could not resolve frontDoorId; skipping forwarding-gateway config generation"
    return 1
  fi

  mkdir -p "$(dirname "$FORWARDING_GATEWAY_ARTIFACT")" "$(dirname "$STATICWEBAPP_CONFIG_FILE")"

  jq -n \
    --arg environment "$ENVIRONMENT" \
    --arg frontDoorId "$front_door_id" \
    --arg endpointHostName "$endpoint_hostname" \
    --arg backendServiceTag 'AzureFrontDoor.Backend' \
    '{
      environment: $environment,
      frontDoorId: $frontDoorId,
      backendServiceTag: $backendServiceTag,
      endpointHostName: $endpointHostName,
      staticWebAppConfig: {
        forwardingGateway: {
          requiredHeaders: {"X-Azure-FDID": $frontDoorId},
          allowedForwardedHosts: [$endpointHostName]
        }
      }
    }' > "$FORWARDING_GATEWAY_ARTIFACT" || return 1

  jq '.staticWebAppConfig' "$FORWARDING_GATEWAY_ARTIFACT" > "$STATICWEBAPP_CONFIG_FILE" || return 1
  if [ -d "$(dirname "$STATICWEBAPP_DIST_CONFIG_FILE")" ]; then
    jq '.staticWebAppConfig' "$FORWARDING_GATEWAY_ARTIFACT" > "$STATICWEBAPP_DIST_CONFIG_FILE" || return 1
  fi
  log_success "forwarding-gateway config written to $FORWARDING_GATEWAY_ARTIFACT and $STATICWEBAPP_CONFIG_FILE"
  return 0
}

probe_url_status() {
  probe_url="$1"
  curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$probe_url" 2>/dev/null
}

public_route_is_healthy() {
  public_url="$1"
  [ -n "$public_url" ] || return 1
  status_code="$(probe_url_status "$public_url/")"
  case "$status_code" in
    2*|3*|503) return 0 ;;
    *) return 1 ;;
  esac
}

direct_origin_is_denied() {
  origin_host="$1"
  [ -n "$origin_host" ] && [ "$origin_host" != "None" ] || return 1
  status_code="$(probe_url_status "https://${origin_host}/")"
  case "$status_code" in
    401|403) return 0 ;;
    *) return 1 ;;
  esac
}

forwarding_gateway_state() {
  public_url="$1"
  origin_host="$2"

  if ! public_route_is_healthy "$public_url"; then
    echo "PublicRouteUnhealthy|Unknown|FORWARDING_GATEWAY_PUBLIC_ROUTE_UNHEALTHY|Forwarding-gateway configuration was not generated because the shared public URL did not return a healthy or controlled response"
    return 0
  fi

  if ! write_shared_forwarding_gateway_config "$public_url"; then
    echo "ConfigUnavailable|Unknown|FORWARDING_GATEWAY_CONFIG_UNAVAILABLE|Forwarding-gateway configuration could not be generated after route verification"
    return 0
  fi

  if direct_origin_is_denied "$origin_host"; then
    echo "Restricted|Denied|FORWARDING_GATEWAY_RESTRICTED|Direct Static Web Apps origin access is denied and the shared public URL remains healthy"
  else
    echo "BootstrapPending|Allowed|FORWARDING_GATEWAY_REUPLOAD_REQUIRED|Forwarding-gateway configuration was generated after route verification; rebuild and re-upload the application so direct-origin access is denied"
  fi
}

azure_deploy_shared() {
  deployment_name="gamevault-shared-${ENVIRONMENT}"
  log_info "Creating shared application deployment: $deployment_name"
  az deployment group create \
    --resource-group "$SHARED_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$deployment_name" \
    --template-file "$SHARED_TEMPLATE" \
    --parameters "$PARAMS_FILE" \
    --mode Incremental \
    -o json
}

write_route_parameters_file() {
  swa_name="$1"
  route_params_file="$2"
  maintenance_host="$(maintenance_origin_hostname)"
  enable_maintenance="false"
  if [ -n "$maintenance_host" ] && [ "$maintenance_host" != "None" ]; then
    enable_maintenance="true"
  else
    maintenance_host=""
  fi
  waf_endpoint_ids="$(waf_associated_endpoint_ids)" || return 1
  waf_security_name="$(waf_security_policy_name)"

  jq -n \
    --arg environment "$ENVIRONMENT" \
    --arg baseName "$BASE_NAME" \
    --arg frontDoorProfileName "$FRONT_DOOR_PROFILE" \
    --arg sharedResourceGroupName "$SHARED_RESOURCE_GROUP" \
    --arg staticWebAppName "$swa_name" \
    --arg maintenanceOriginHostName "$maintenance_host" \
    --argjson enableMaintenanceFallback "$enable_maintenance" \
    --arg wafSecurityPolicyName "$waf_security_name" \
    --argjson wafAssociatedEndpointIds "$waf_endpoint_ids" \
    '{
      "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
      contentVersion: "1.0.0.0",
      parameters: {
        environment: {value: $environment},
        baseName: {value: $baseName},
        frontDoorProfileName: {value: $frontDoorProfileName},
        sharedResourceGroupName: {value: $sharedResourceGroupName},
        staticWebAppName: {value: $staticWebAppName},
        maintenanceOriginHostName: {value: $maintenanceOriginHostName},
        enableMaintenanceFallback: {value: $enableMaintenanceFallback},
        wafSecurityPolicyName: {value: $wafSecurityPolicyName},
        wafAssociatedEndpointIds: {value: $wafAssociatedEndpointIds}
      }
    }' > "$route_params_file"
}

azure_whatif_route() {
  route_params_file="$1"
  whatif_change_count "$PLATFORM_RESOURCE_GROUP" "$ROUTE_TEMPLATE" --parameters "@$route_params_file"
}

azure_deploy_route() {
  route_params_file="$1"
  deployment_name="gamevault-shared-route-${ENVIRONMENT}"

  log_info "Creating shared route deployment: $deployment_name"
  az deployment group create \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$deployment_name" \
    --template-file "$ROUTE_TEMPLATE" \
    --parameters "@$route_params_file" \
    --mode Incremental \
    -o json
}

# ----------------------------------------------------------------------------
# Verification
# ----------------------------------------------------------------------------

# verify_control_plane: deterministic, read-only Azure control-plane checks.
# Returns 0 when every invariant holds, 1 otherwise, and appends findings to
# $SCRATCH_DIR/verify-findings.txt.
verify_control_plane() {
  endpoint_name="$(shared_endpoint_name)"
  : > "$SCRATCH_DIR/verify-findings.txt"
  verify_ok=0

  finding() {
    echo "$1" >> "$SCRATCH_DIR/verify-findings.txt"
    verify_ok=1
  }

  route_json=$(az afd route show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint_name" \
    --route-name "$SHARED_ROUTE_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    -o json 2>/dev/null)

  if [ -z "$route_json" ]; then
    finding "shared route '$SHARED_ROUTE_NAME' not found on endpoint '$endpoint_name'"
    return "$verify_ok"
  fi

  provisioning=$(echo "$route_json" | jq -r '.provisioningState // ""')
  [ "$provisioning" = "Succeeded" ] || finding "route provisioningState is '$provisioning', expected 'Succeeded'"

  https_redirect=$(echo "$route_json" | jq -r '.httpsRedirect // ""')
  [ "$https_redirect" = "Enabled" ] || finding "route httpsRedirect is '$https_redirect', expected 'Enabled'"

  forwarding=$(echo "$route_json" | jq -r '.forwardingProtocol // ""')
  [ "$forwarding" = "HttpsOnly" ] || finding "route forwardingProtocol is '$forwarding', expected 'HttpsOnly'"

  # The shared route must reference only the shared origin group. Pointing it
  # at any other group would let a legacy origin serve shared traffic.
  route_group=$(echo "$route_json" | jq -r '.originGroup.id // ""' | sed 's#.*/##')
  [ "$route_group" = "$SHARED_ORIGIN_GROUP_NAME" ] \
    || finding "route origin group is '$route_group', expected '$SHARED_ORIGIN_GROUP_NAME'"

  route_patterns=$(echo "$route_json" | jq -r '[.patternsToMatch[]?] | sort | join(",")')
  [ "$route_patterns" = "/*" ] || finding "shared route patterns are '$route_patterns', expected '/*'"

  endpoint_json=$(az afd endpoint show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint_name" \
    --subscription "$SUBSCRIPTION_ID" \
    -o json 2>/dev/null)
  if [ -z "$endpoint_json" ]; then
    finding "shared endpoint '$endpoint_name' not found"
  else
    endpoint_instance_tag=$(echo "$endpoint_json" | jq -r '.tags.instanceId // ""')
    [ -z "$endpoint_instance_tag" ] || finding "shared endpoint carries legacy instanceId tag"
  fi

  auth_route_json=$(az afd route show \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --endpoint-name "$endpoint_name" \
    --route-name "$SHARED_AUTH_ROUTE_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    -o json 2>/dev/null)

  if [ -z "$auth_route_json" ]; then
    finding "shared auth route '$SHARED_AUTH_ROUTE_NAME' not found on endpoint '$endpoint_name'"
  else
    auth_patterns=$(echo "$auth_route_json" | jq -r '[.patternsToMatch[]?] | sort | join(",")')
    auth_redirect=$(echo "$auth_route_json" | jq -r '.httpsRedirect // ""')
    auth_forwarding=$(echo "$auth_route_json" | jq -r '.forwardingProtocol // ""')
    auth_group=$(echo "$auth_route_json" | jq -r '.originGroup.id // ""' | sed 's#.*/##')
    auth_cache_present=$(echo "$auth_route_json" | jq -r 'has("cacheConfiguration") and (.cacheConfiguration != null)')
    auth_compression_present=$(echo "$auth_route_json" | jq -r 'has("compressionSettings") and (.compressionSettings != null)')
    [ "$auth_patterns" = "/.auth/*" ] || finding "auth route patterns are '$auth_patterns', expected '/.auth/*'"
    [ "$auth_redirect" = "Enabled" ] || finding "auth route httpsRedirect is '$auth_redirect', expected 'Enabled'"
    [ "$auth_forwarding" = "HttpsOnly" ] || finding "auth route forwardingProtocol is '$auth_forwarding', expected 'HttpsOnly'"
    [ "$auth_group" = "$SHARED_ORIGIN_GROUP_NAME" ] || finding "auth route origin group is '$auth_group', expected '$SHARED_ORIGIN_GROUP_NAME'"
    [ "$auth_cache_present" = "false" ] || finding "auth route cacheConfiguration must be unconfigured"
    [ "$auth_compression_present" = "false" ] || finding "auth route compressionSettings must be unconfigured"
  fi

  expected_host="$(shared_swa_hostname)"
  origins_json=$(az afd origin list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --origin-group-name "$SHARED_ORIGIN_GROUP_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    -o json 2>/dev/null || echo '[]')

  app_origin=$(echo "$origins_json" | jq -r --arg n "$SHARED_ORIGIN_NAME" '[.[] | select(.name == $n)][0] // empty')
  if [ -z "$app_origin" ]; then
    finding "shared application origin '$SHARED_ORIGIN_NAME' not found in group '$SHARED_ORIGIN_GROUP_NAME'"
  else
    actual_host=$(echo "$app_origin" | jq -r '.hostName // ""')
    actual_header=$(echo "$app_origin" | jq -r '.originHostHeader // ""')
    cert_check=$(echo "$app_origin" | jq -r '.enforceCertificateNameCheck // false')
    [ "$actual_host" = "$expected_host" ] || finding "origin hostName is '$actual_host', expected '$expected_host'"
    [ "$actual_header" = "$expected_host" ] || finding "origin originHostHeader is '$actual_header', expected '$expected_host'"
    [ "$cert_check" = "true" ] || finding "origin enforceCertificateNameCheck is disabled"
  fi

  # No legacy origin may hide inside the shared origin group.
  legacy_origins=$(echo "$origins_json" | jq -r --arg n "$SHARED_ORIGIN_NAME" \
    '[.[] | select(.name != $n) | select(.name | endswith("-maintenance") | not) | .name] | join(", ")')
  if [ -n "$legacy_origins" ] && [ "$legacy_origins" != "null" ]; then
    finding "unexpected non-shared origin(s) in shared origin group: $legacy_origins"
  fi

  maintenance_host="$(maintenance_origin_hostname)"
  if [ -n "$maintenance_host" ] && [ "$maintenance_host" != "None" ]; then
    maintenance_origin=$(echo "$origins_json" | jq -r --arg n "$SHARED_MAINTENANCE_ORIGIN_NAME" '[.[] | select(.name == $n)][0] // empty')
    if [ -z "$maintenance_origin" ]; then
      finding "shared maintenance origin '$SHARED_MAINTENANCE_ORIGIN_NAME' not found in group '$SHARED_ORIGIN_GROUP_NAME'"
    else
      maintenance_priority=$(echo "$maintenance_origin" | jq -r '.priority // ""')
      maintenance_actual_host=$(echo "$maintenance_origin" | jq -r '.hostName // ""')
      [ "$maintenance_priority" = "2" ] || finding "maintenance origin priority is '$maintenance_priority', expected '2'"
      [ "$maintenance_actual_host" = "$maintenance_host" ] || finding "maintenance origin hostName is '$maintenance_actual_host', expected '$maintenance_host'"
    fi
  fi

  endpoint_id="$(shared_endpoint_id)"
  policy_id="$(waf_policy_id)"
  security_policy_name="$(shared_waf_security_policy_name)"
  security_policies_json=$(az afd security-policy list \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --profile-name "$FRONT_DOOR_PROFILE" \
    --subscription "$SUBSCRIPTION_ID" -o json 2>/dev/null) || security_policies_json='[]'
  waf_covers_shared=$(echo "$security_policies_json" | jq -r --arg endpointId "$endpoint_id" --arg wafPolicyId "$policy_id" --arg policyName "$security_policy_name" '
    [ .[]
      | select((.name // "" | ascii_downcase) == ($policyName | ascii_downcase))
      | select((.parameters.wafPolicy.id // "" | ascii_downcase) == ($wafPolicyId | ascii_downcase))
      | .parameters.associations[]?.domains[]?.id
      | select((. | ascii_downcase) == ($endpointId | ascii_downcase))
    ] | length')
  [ "$waf_covers_shared" -gt 0 ] || finding "WAF security policy does not associate the shared endpoint"

  return "$verify_ok"
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

cmd_validate() {
  if ! bicep_local_build; then
    build_err="$(mask_secrets < "$SCRATCH_DIR/bicep-build.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "BICEP_BUILD_FAILED" "Local Bicep build failed: $build_err"
  fi
  log_success "Local Bicep build passed"

  if [ ! -f "$PARAMS_FILE" ]; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "PARAMS_FILE_NOT_FOUND" "Parameter file not found: $PARAMS_FILE"
  fi

  if [ "$LOCAL_ONLY" -eq 1 ]; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "null"
    return 0
  fi

  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$SHARED_RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "RESOURCE_GROUP_NOT_FOUND" "Shared resource group '$SHARED_RESOURCE_GROUP' does not exist yet; run 'deploy' first to create it"
  fi

  if ! azure_validate_shared >"$SCRATCH_DIR/validate.out" 2>"$SCRATCH_DIR/validate.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/validate.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_VALIDATION_FAILED" "Deployment validation failed; no resources were changed: $err"
  fi

  inventory="$(current_inventory)"
  shared_obj="$(shared_service_object "$inventory" "$(current_public_url)" "Unknown")"
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj"
}

cmd_whatif() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$SHARED_RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "RESOURCE_GROUP_NOT_FOUND" "Shared resource group '$SHARED_RESOURCE_GROUP' does not exist yet; run 'deploy' first to create it"
  fi

  log_info "Running what-if for the shared application (no resources are mutated)"
  if ! app_changes="$(whatif_change_count "$SHARED_RESOURCE_GROUP" "$SHARED_TEMPLATE" --parameters "$PARAMS_FILE" 2>"$SCRATCH_DIR/whatif.err")"; then
    err="$(mask_secrets < "$SCRATCH_DIR/whatif.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_WHATIF_FAILED" "Shared application what-if failed: $err"
  fi
  if ! assert_no_legacy_mutation; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "$(legacy_mutation_code)" "$(legacy_mutation_message)"
  fi

  route_changes=0
  swa_name="$(shared_swa_name)"
  if [ -n "$swa_name" ] && [ "$swa_name" != "None" ]; then
    log_info "Running what-if for the shared route (no resources are mutated)"
    route_params_file="$SCRATCH_DIR/route-parameters-whatif.json"
    if ! write_route_parameters_file "$swa_name" "$route_params_file" 2>"$SCRATCH_DIR/route-params.err"; then
      err="$(mask_secrets < "$SCRATCH_DIR/route-params.err")"
      fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "ROUTE_PARAMETERS_FAILED" "Shared route parameter resolution failed; endpoint/security-policy reads did not complete: $err"
    fi
    if ! route_changes="$(azure_whatif_route "$route_params_file" 2>"$SCRATCH_DIR/whatif-route.err")"; then
      err="$(mask_secrets < "$SCRATCH_DIR/whatif-route.err")"
      fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_WHATIF_FAILED" "Shared route what-if failed: $err"
    fi
    if ! assert_no_legacy_mutation; then
      fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "$(legacy_mutation_code)" "$(legacy_mutation_message)"
    fi
  else
    log_warn "Shared Static Web App not deployed yet; skipping route what-if"
  fi

  inventory="$(current_inventory)"
  shared_obj="$(shared_service_object "$inventory" "$(current_public_url)" "Unknown")"

  total_changes=$((app_changes + route_changes))
  if [ "$total_changes" -eq 0 ]; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "NoChange" "$OP_ID" "$shared_obj"
  else
    log_info "what-if reports $total_changes pending change(s)"
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj"
  fi
}

cmd_deploy() {
  if [ "$CONFIRM" -ne 1 ]; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "CONFIRMATION_REQUIRED" "deploy requires --confirm (add --non-interactive --confirm for CI use after its approval gate)"
  fi

  if ! bicep_local_build; then
    build_err="$(mask_secrets < "$SCRATCH_DIR/bicep-build.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "BICEP_BUILD_FAILED" "Local Bicep build failed: $build_err"
  fi

  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  # A previously working public address must survive any failure below.
  last_known_url="$(current_public_url)"
  before_inventory='{
    "staticWebApps": [],
    "storageAccounts": [],
    "endpoints": [],
    "originGroups": [],
    "routes": [],
    "origins": [],
    "counts": {
      "staticWebApps": 0,
      "storageAccounts": 0,
      "endpoints": 0,
      "originGroups": 0,
      "routes": 0,
      "origins": 0
    }
  }'

  fail_preserving() {
    code="$1"
    message="$2"
    after_inventory="$(current_inventory 2>/dev/null || echo "$before_inventory")"
    shared_obj="$(shared_service_object "$after_inventory" "$last_known_url" "Degraded")"
    preserved="last known working shared configuration preserved"
    if [ -z "$last_known_url" ]; then
      preserved="no previously working shared route existed"
    fi
    emit_json_envelope "$DATA_KEY" "$ACTION" "Failed" "$OP_ID" "$shared_obj" \
      "$(diagnostic_array "$code" "$message ($preserved)")"
    log_error "$message"
    exit 1
  }

  # Stage 0: ensure the shared resource group exists. This is the only
  # pre-validation mutation; failures are reported with a preserving envelope.
  if ! ensure_shared_resource_group >"$SCRATCH_DIR/group-create.out" 2>"$SCRATCH_DIR/group-create.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/group-create.err")"
    fail_preserving "RESOURCE_GROUP_CREATE_FAILED" "Shared resource group creation failed: $err"
  fi

  # Stage 1: capture the pre-deployment inventory. This is both the
  # constant-resource evidence and the record used to prove legacy
  # preservation if a later stage fails.
  before_inventory="$(current_inventory)"
  echo "$before_inventory" > "$SCRATCH_DIR/inventory-before.json"

  # Stage 2: validate the shared application template before route mutation.
  if ! azure_validate_shared >"$SCRATCH_DIR/validate.out" 2>"$SCRATCH_DIR/validate.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/validate.err")"
    fail_preserving "AZURE_VALIDATION_FAILED" "Deployment validation failed; no resources were changed: $err"
  fi

  # Stage 3: preview the shared application, and refuse to proceed if a
  # legacy resource would change.
  if ! whatif_change_count "$SHARED_RESOURCE_GROUP" "$SHARED_TEMPLATE" --parameters "$PARAMS_FILE" >"$SCRATCH_DIR/app-changes" 2>"$SCRATCH_DIR/whatif.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/whatif.err")"
    fail_preserving "AZURE_WHATIF_FAILED" "Shared application what-if failed: $err"
  fi
  if ! assert_no_legacy_mutation; then
    fail_preserving "$(legacy_mutation_code)" "$(legacy_mutation_message)"
  fi

  # Stage 4: deploy the shared application.
  if ! azure_deploy_shared >"$SCRATCH_DIR/deploy-app.json" 2>"$SCRATCH_DIR/deploy-app.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/deploy-app.err")"
    fail_preserving "SHARED_APP_DEPLOY_FAILED" "Shared application deployment failed: $err"
  fi
  log_success "Shared application deployment complete"

  # Stage 5: resolve the origin hostname produced by the shared application.
  swa_name=$(jq -r '.properties.outputs.staticWebAppName.value // ""' "$SCRATCH_DIR/deploy-app.json" 2>/dev/null)
  if [ -z "$swa_name" ]; then
    swa_name="$(shared_swa_name)"
  fi
  if [ -z "$swa_name" ] || [ "$swa_name" = "None" ]; then
    fail_preserving "SHARED_ORIGIN_UNRESOLVED" "Unable to resolve the shared Static Web App name after deployment"
  fi

  # Stage 6: preview the shared Front Door route in the legacy platform
  # resource group using the exact parameter file that Stage 7 deploys.
  route_params_file="$SCRATCH_DIR/route-parameters-deploy.json"
  if ! write_route_parameters_file "$swa_name" "$route_params_file" 2>"$SCRATCH_DIR/route-params.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/route-params.err")"
    fail_preserving "ROUTE_PARAMETERS_FAILED" "Shared route parameter resolution failed; endpoint/security-policy reads did not complete: $err"
  fi
  if ! azure_whatif_route "$route_params_file" >"$SCRATCH_DIR/route-changes" 2>"$SCRATCH_DIR/whatif-route.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/whatif-route.err")"
    fail_preserving "AZURE_WHATIF_FAILED" "Shared route what-if failed: $err"
  fi
  if ! assert_no_legacy_mutation; then
    fail_preserving "$(legacy_mutation_code)" "$(legacy_mutation_message)"
  fi

  # Stage 7: deploy the one shared Front Door route.
  if ! azure_deploy_route "$route_params_file" >"$SCRATCH_DIR/deploy-route.json" 2>"$SCRATCH_DIR/deploy-route.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/deploy-route.err")"
    fail_preserving "SHARED_ROUTE_DEPLOY_FAILED" "Shared route deployment failed: $err"
  fi
  log_success "Shared route deployment complete"

  public_url=$(jq -r '.properties.outputs.url.value // ""' "$SCRATCH_DIR/deploy-route.json" 2>/dev/null)
  [ -n "$public_url" ] || public_url="$(current_public_url)"

  # Stage 8: allow the shared public origin to reach Table Storage.
  storage_name=$(jq -r '.properties.outputs.storageAccountName.value // ""' "$SCRATCH_DIR/deploy-app.json" 2>/dev/null)
  if [ -z "$storage_name" ] || [ "$storage_name" = "None" ]; then
    storage_name="$(shared_storage_name)"
  fi
  if ! configure_shared_cors "$storage_name" "$public_url"; then
    err="$(mask_secrets < "$SCRATCH_DIR/cors.err")"
    fail_preserving "SHARED_CORS_FAILED" "Shared-origin CORS configuration failed: $err"
  fi

  # Stage 9: verify the deployed control-plane graph.
  if ! verify_control_plane; then
    findings="$(tr '\n' '; ' < "$SCRATCH_DIR/verify-findings.txt" | mask_secrets)"
    fail_preserving "SHARED_ROUTE_VERIFICATION_FAILED" "Shared route verification failed: $findings"
  fi
  log_success "Shared route verification passed"

  # Stage 10: after route verification succeeds, generate/apply the
  # forwarding-gateway configuration. Bootstrap deployments report that the
  # caller must rebuild/re-upload with the generated staticwebapp.config.json;
  # steady-state deployments confirm direct-origin denial.
  origin_host="$(shared_swa_hostname)"
  forwarding_result="$(forwarding_gateway_state "$public_url" "$origin_host")"
  forwarding_state="$(echo "$forwarding_result" | cut -d'|' -f1)"
  direct_origin_access="$(echo "$forwarding_result" | cut -d'|' -f2)"
  forwarding_code="$(echo "$forwarding_result" | cut -d'|' -f3)"
  forwarding_message="$(echo "$forwarding_result" | cut -d'|' -f4-)"
  diagnostics_json="$(diagnostic_array "$forwarding_code" "$forwarding_message")"
  case "$forwarding_state" in
    PublicRouteUnhealthy|ConfigUnavailable)
      fail_preserving "$forwarding_code" "$forwarding_message"
      ;;
  esac

  # Stage 11: capture the resulting inventory as constant-resource evidence.
  after_inventory="$(current_inventory)"
  echo "$after_inventory" > "$SCRATCH_DIR/inventory-after.json"

  shared_obj="$(shared_service_object "$after_inventory" "$public_url" "Healthy" "$forwarding_state" "$STATICWEBAPP_CONFIG_FILE" "$direct_origin_access")"

  app_changes="$(cat "$SCRATCH_DIR/app-changes" 2>/dev/null || echo 0)"
  if [ "$app_changes" -eq 0 ] && compare_shared_inventory "$SCRATCH_DIR/inventory-before.json" "$SCRATCH_DIR/inventory-after.json" 2>/dev/null; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "NoChange" "$OP_ID" "$shared_obj" "$diagnostics_json"
  else
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj" "$diagnostics_json"
  fi
}

cmd_verify() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  inventory="$(current_inventory)"
  public_url="$(current_public_url)"
  storage_name="$(shared_storage_name)"

  if ! configure_shared_cors "$storage_name" "$public_url"; then
    err="$(mask_secrets < "$SCRATCH_DIR/cors.err")"
    shared_obj="$(shared_service_object "$inventory" "$public_url" "Degraded")"
    emit_json_envelope "$DATA_KEY" "$ACTION" "Failed" "$OP_ID" "$shared_obj" \
      "$(diagnostic_array "SHARED_CORS_FAILED" "Shared-origin CORS configuration failed: $err")"
    log_error "Shared-origin CORS configuration failed"
    exit 1
  fi

  if verify_control_plane; then
    origin_host="$(shared_swa_hostname)"
    forwarding_result="$(forwarding_gateway_state "$public_url" "$origin_host")"
    forwarding_state="$(echo "$forwarding_result" | cut -d'|' -f1)"
    direct_origin_access="$(echo "$forwarding_result" | cut -d'|' -f2)"
    forwarding_code="$(echo "$forwarding_result" | cut -d'|' -f3)"
    forwarding_message="$(echo "$forwarding_result" | cut -d'|' -f4-)"
    shared_obj="$(shared_service_object "$inventory" "$public_url" "Healthy" "$forwarding_state" "$STATICWEBAPP_CONFIG_FILE" "$direct_origin_access")"
    if [ "$forwarding_state" = "Restricted" ]; then
      emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj" \
        "$(diagnostic_array "$forwarding_code" "$forwarding_message")"
      return 0
    fi
    emit_json_envelope "$DATA_KEY" "$ACTION" "Failed" "$OP_ID" "$shared_obj" \
      "$(diagnostic_array "$forwarding_code" "$forwarding_message")"
    log_error "$forwarding_message"
    exit 1
  fi

  findings="$(tr '\n' '; ' < "$SCRATCH_DIR/verify-findings.txt" | mask_secrets)"
  shared_obj="$(shared_service_object "$inventory" "$public_url" "Degraded")"
  emit_json_envelope "$DATA_KEY" "$ACTION" "Failed" "$OP_ID" "$shared_obj" \
    "$(diagnostic_array "SHARED_ROUTE_VERIFICATION_FAILED" "Shared route verification failed: $findings")"
  log_error "Shared route verification failed"
  exit 1
}

cmd_status() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  inventory="$(current_inventory)"
  public_url="$(current_public_url)"

  health="Unknown"
  if [ -n "$public_url" ]; then
    if verify_control_plane >/dev/null 2>&1; then
      health="Healthy"
    else
      health="Degraded"
    fi
  else
    health="Unavailable"
  fi

  shared_obj="$(shared_service_object "$inventory" "$public_url" "$health")"
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj"
}

# Read-only constant-resource evidence (FR-018). Deliberately separate from
# status so an operator or scale test can diff two inventory documents
# without interpreting health.
cmd_inventory() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  inventory="$(current_inventory)"
  shared_obj="$(shared_service_object "$inventory" "$(current_public_url)" "Unknown")"
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj"
}

case "$ACTION" in
  validate) cmd_validate ;;
  what-if) cmd_whatif ;;
  deploy) cmd_deploy ;;
  verify) cmd_verify ;;
  status) cmd_status ;;
  inventory) cmd_inventory ;;
esac
