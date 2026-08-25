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

# shellcheck source=lib/azure-common.sh
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

ACTION="${1:-}"
[ -n "$ACTION" ] || { usage; exit 2; }
shift || true

case "$ACTION" in
  validate|what-if|deploy|verify|status|inventory) ;;
  *)
    usage
    fail_fast "$DATA_KEY" "$ACTION" "$(operation_id shared unknown)" "UNKNOWN_ACTION" "Unknown action: $ACTION"
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

SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

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
SHARED_ROUTE_NAME="route-shared"

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

  swa_id=$(echo "$inventory_json" | jq -r '.staticWebApps[0] // ""')
  storage_id=$(echo "$inventory_json" | jq -r '.storageAccounts[0] // ""')
  storage_name=$(echo "$storage_id" | sed 's#.*/##')
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

  # Only the shared origin group's origins count as application origins; a
  # legacy origin in another group must never inflate this number.
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
    --argjson logicalInstanceCount "$instance_count" \
    --argjson inventory "$inventory_json" \
    --arg originGroupName "$SHARED_ORIGIN_GROUP_NAME" \
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
      logicalInstanceCount: $logicalInstanceCount,
      resourceCounts: {
        staticWebApps: ($inventory.counts.staticWebApps // 0),
        storageAccounts: ($inventory.counts.storageAccounts // 0),
        endpoints: ($inventory.counts.endpoints // 0),
        routes: ($inventory.counts.routes // 0),
        originGroups: ($inventory.counts.originGroups // 0),
        applicationOrigins: ([$inventory.origins[]? | select(contains("/originGroups/" + $originGroupName + "/"))] | length)
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

ensure_shared_resource_group() {  log_info "Ensuring shared resource group exists: $SHARED_RESOURCE_GROUP"
  az group show --name "$SHARED_RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1 && return 0
  [ -n "$LOCATION" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "shared resource group '$SHARED_RESOURCE_GROUP' does not exist; --location is required to create it"
  log_info "Creating shared resource group in $LOCATION"
  az group create \
    --name "$SHARED_RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --tags application="GameVault Tracker" environment="$ENVIRONMENT" managedBy="Bicep" component="shared-service" \
    >/dev/null
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
  [ -f "$SCRATCH_DIR/whatif-raw.json" ] || return 0
  offenders=$(jq -r '
    [ .changes[]?
      | select(.changeType == "Delete" or .changeType == "Modify")
      | .resourceId
      | select(
          (test("/originGroups/og-shared";  "i") | not) and
          (test("-shared($|/)";             "i") | not)
        )
    ] | unique | join(", ")
  ' "$SCRATCH_DIR/whatif-raw.json" 2>/dev/null)

  if [ -n "$offenders" ] && [ "$offenders" != "null" ]; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "LEGACY_MUTATION_DETECTED" \
      "What-if preview would delete or modify non-shared resources; refusing to proceed: $offenders"
  fi
}

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

azure_deploy_route() {
  swa_name="$1"
  deployment_name="gamevault-shared-route-${ENVIRONMENT}"
  log_info "Creating shared route deployment: $deployment_name"
  az deployment group create \
    --resource-group "$PLATFORM_RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$deployment_name" \
    --template-file "$ROUTE_TEMPLATE" \
    --parameters \
      environment="$ENVIRONMENT" \
      baseName="$BASE_NAME" \
      frontDoorProfileName="$FRONT_DOOR_PROFILE" \
      sharedResourceGroupName="$SHARED_RESOURCE_GROUP" \
      staticWebAppName="$swa_name" \
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
  assert_no_legacy_mutation

  route_changes=0
  swa_name="$(shared_swa_name)"
  if [ -n "$swa_name" ] && [ "$swa_name" != "None" ]; then
    log_info "Running what-if for the shared route (no resources are mutated)"
    if ! route_changes="$(whatif_change_count "$PLATFORM_RESOURCE_GROUP" "$ROUTE_TEMPLATE" \
      --parameters \
        environment="$ENVIRONMENT" \
        baseName="$BASE_NAME" \
        frontDoorProfileName="$FRONT_DOOR_PROFILE" \
        sharedResourceGroupName="$SHARED_RESOURCE_GROUP" \
        staticWebAppName="$swa_name" \
      2>"$SCRATCH_DIR/whatif-route.err")"; then
      err="$(mask_secrets < "$SCRATCH_DIR/whatif-route.err")"
      fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_WHATIF_FAILED" "Shared route what-if failed: $err"
    fi
    assert_no_legacy_mutation
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
  ensure_shared_resource_group

  # Stage 1: capture the pre-mutation inventory. This is both the
  # constant-resource evidence and the record used to prove legacy
  # preservation if a later stage fails.
  before_inventory="$(current_inventory)"
  echo "$before_inventory" > "$SCRATCH_DIR/inventory-before.json"

  # A previously working public address must survive any failure below.
  last_known_url="$(current_public_url)"

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

  # Stage 2: validate before any mutation.
  if ! azure_validate_shared >"$SCRATCH_DIR/validate.out" 2>"$SCRATCH_DIR/validate.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/validate.err")"
    fail_preserving "AZURE_VALIDATION_FAILED" "Deployment validation failed; no resources were changed: $err"
  fi

  # Stage 3: preview, and refuse to proceed if a legacy resource would change.
  if ! whatif_change_count "$SHARED_RESOURCE_GROUP" "$SHARED_TEMPLATE" --parameters "$PARAMS_FILE" >"$SCRATCH_DIR/app-changes" 2>"$SCRATCH_DIR/whatif.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/whatif.err")"
    fail_preserving "AZURE_WHATIF_FAILED" "Shared application what-if failed: $err"
  fi
  assert_no_legacy_mutation

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

  # Stage 6: deploy the one shared Front Door route.
  if ! azure_deploy_route "$swa_name" >"$SCRATCH_DIR/deploy-route.json" 2>"$SCRATCH_DIR/deploy-route.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/deploy-route.err")"
    fail_preserving "SHARED_ROUTE_DEPLOY_FAILED" "Shared route deployment failed: $err"
  fi
  log_success "Shared route deployment complete"

  public_url=$(jq -r '.properties.outputs.url.value // ""' "$SCRATCH_DIR/deploy-route.json" 2>/dev/null)
  [ -n "$public_url" ] || public_url="$(current_public_url)"

  # Stage 7: allow the shared public origin to reach Table Storage.
  storage_name=$(jq -r '.properties.outputs.storageAccountName.value // ""' "$SCRATCH_DIR/deploy-app.json" 2>/dev/null)
  if ! configure_shared_cors "$storage_name" "$public_url"; then
    err="$(mask_secrets < "$SCRATCH_DIR/cors.err")"
    fail_preserving "SHARED_CORS_FAILED" "Shared-origin CORS configuration failed: $err"
  fi

  # Stage 8: verify the deployed control-plane graph.
  if ! verify_control_plane; then
    findings="$(tr '\n' '; ' < "$SCRATCH_DIR/verify-findings.txt" | mask_secrets)"
    fail_preserving "SHARED_ROUTE_VERIFICATION_FAILED" "Shared route verification failed: $findings"
  fi
  log_success "Shared route verification passed"

  # Stage 9: capture the resulting inventory as constant-resource evidence.
  after_inventory="$(current_inventory)"
  echo "$after_inventory" > "$SCRATCH_DIR/inventory-after.json"

  shared_obj="$(shared_service_object "$after_inventory" "$public_url" "Healthy")"

  app_changes="$(cat "$SCRATCH_DIR/app-changes" 2>/dev/null || echo 0)"
  if [ "$app_changes" -eq 0 ] && compare_shared_inventory "$SCRATCH_DIR/inventory-before.json" "$SCRATCH_DIR/inventory-after.json" 2>/dev/null; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "NoChange" "$OP_ID" "$shared_obj"
  else
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj"
  fi
}

cmd_verify() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  inventory="$(current_inventory)"
  public_url="$(current_public_url)"

  if verify_control_plane; then
    shared_obj="$(shared_service_object "$inventory" "$public_url" "Healthy")"
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$shared_obj"
    return 0
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
