#!/bin/bash
# ============================================================================
# platform.sh - Shared Multi-Instance Entry Platform lifecycle CLI
# ============================================================================
# Usage:
#   ./scripts/platform.sh <validate|what-if|deploy|outputs|status> [options]
#
# Options:
#   --environment <dev|staging|prod>   (required for all actions)
#   --subscription-id <uuid>           (required unless --local-only)
#   --resource-group <name>            (required unless --local-only)
#   --location <azure-region>          (required for deploy; defaults applied otherwise)
#   --base-name <name>                 (optional, defaults to "gvt")
#   --local-only                       (validate: skip all Azure calls, offline Bicep build only)
#   --confirm                          (required for deploy)
#   --non-interactive                  (informational; still requires --confirm for deploy)
#
# See specs/001-multi-instance-platform/contracts/platform-cli.md for the
# full command contract and specs/001-multi-instance-platform/quickstart.md
# for end-to-end usage.
#
# Bash 3.2 compatible. Writes human-readable progress to stderr and exactly
# one JSON document (matching tests/infrastructure/contracts/platform-output.schema.json)
# to stdout.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLATFORM_DIR="$PROJECT_ROOT/infra/platform"
TEMPLATE_FILE="$PLATFORM_DIR/main.bicep"

# shellcheck source=lib/azure-common.sh
. "$SCRIPT_DIR/lib/azure-common.sh"

DATA_KEY="platform"

usage() {
  cat >&2 <<'USAGE'
Usage: platform.sh <validate|what-if|deploy|outputs|status> [options]
  --environment <dev|staging|prod>
  --subscription-id <uuid>
  --resource-group <name>
  --location <azure-region>
  --base-name <name>            (default: gvt)
  --local-only                  (validate only: skip Azure, offline Bicep build)
  --confirm                     (required for deploy)
  --non-interactive              (informational flag; --confirm still required)
USAGE
}

ACTION="${1:-}"
[ -n "$ACTION" ] || { usage; exit 2; }
shift || true

case "$ACTION" in
  validate|what-if|deploy|outputs|status) ;;
  *)
    usage
    fail_fast "$DATA_KEY" "$ACTION" "$(operation_id platform unknown)" "UNKNOWN_ACTION" "Unknown action: $ACTION"
    ;;
esac

ENVIRONMENT=""
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
LOCATION=""
BASE_NAME="gvt"
LOCAL_ONLY=0
CONFIRM=0
NON_INTERACTIVE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --location) LOCATION="${2:-}"; shift 2 ;;
    --base-name) BASE_NAME="${2:-}"; shift 2 ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    *)
      usage
      fail_fast "$DATA_KEY" "$ACTION" "$(operation_id platform unknown)" "UNKNOWN_OPTION" "Unknown option: $1"
      ;;
  esac
done

OP_ID="$(operation_id platform "${ENVIRONMENT:-unknown}")"

[ -n "$ENVIRONMENT" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --environment"
case "$ENVIRONMENT" in
  dev|staging|prod) ;;
  *) fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "INVALID_ENVIRONMENT" "environment must be one of: dev, staging, prod" ;;
esac

PARAMS_FILE="$PLATFORM_DIR/main.${ENVIRONMENT}.bicepparam"

if [ "$LOCAL_ONLY" -eq 0 ]; then
  [ -n "$SUBSCRIPTION_ID" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --subscription-id"
  [ -n "$RESOURCE_GROUP" ] || fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "MISSING_REQUIRED_OPTION" "missing value for required option: --resource-group"
fi

# ----------------------------------------------------------------------------
# Bicep helpers
# ----------------------------------------------------------------------------

bicep_local_build() {
  require_cmd az
  log_info "Building Bicep template offline: $TEMPLATE_FILE"
  az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null 2>"$SCRATCH_DIR/bicep-build.err"
}

# ----------------------------------------------------------------------------
# Azure helpers
# ----------------------------------------------------------------------------

front_door_profile_name() {
  echo "$(echo "$BASE_NAME" | tr '[:upper:]' '[:lower:]')-afd-${ENVIRONMENT}"
}

registered_endpoint_count() {
  profile_name="$1"
  count=$(az afd endpoint list \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$profile_name" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "length(@)" -o tsv 2>/dev/null)
  if [ -z "$count" ]; then
    echo 0
  else
    echo "$count"
  fi
}

# platform_object_from_outputs <outputs-json>
# Builds the "platform" data object required by the schema from a Bicep
# deployment outputs document (properties.outputs shape from az CLI).
platform_object_from_outputs() {
  outputs_json="$1"
  profile_name="$(front_door_profile_name)"
  endpoint_count="$(registered_endpoint_count "$profile_name")"

  echo "$outputs_json" | jq \
    --arg resourceGroupName "$RESOURCE_GROUP" \
    --argjson registeredEndpointCount "$endpoint_count" \
    '{
      resourceGroupName: $resourceGroupName,
      frontDoorProfileId: (.frontDoorProfileId.value // ""),
      frontDoorId: (.frontDoorId.value // ""),
      endpointCapacity: (.endpointCapacity.value // 25),
      registeredEndpointCount: $registeredEndpointCount,
      wafMode: (.wafMode.value // "Detection")
    }'
}

ensure_resource_group() {
  log_info "Ensuring resource group exists: $RESOURCE_GROUP"
  az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1 && return 0
  require_value "--location" "$LOCATION"
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --tags application="GameVault Tracker Platform" environment="$ENVIRONMENT" managedBy="Bicep" \
    >/dev/null
}

azure_validate() {
  log_info "Running Azure deployment validation (no resources are mutated)"
  az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMS_FILE" \
    -o json
}

azure_whatif_change_count() {
  log_info "Running Azure what-if (no resources are mutated)"
  whatif_json=$(az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMS_FILE" \
    --result-format FullResourcePayloads \
    --no-pretty-print \
    -o json) || return 1
  echo "$whatif_json" | jq '[.changes[]? | select(.changeType != "NoChange" and .changeType != "Ignore")] | length'
}

azure_deploy() {
  deployment_name="gvt-platform-${ENVIRONMENT}-$(iso_now)"
  log_info "Creating deployment: $deployment_name"
  az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$deployment_name" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMS_FILE" \
    --mode Incremental \
    -o json
}

latest_deployment_outputs() {
  latest_name=$(az deployment group list \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[0].name" -o tsv 2>/dev/null)
  if [ -z "$latest_name" ] || [ "$latest_name" = "None" ]; then
    echo "{}"
    return 0
  fi
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$latest_name" \
    --query "properties.outputs" -o json 2>/dev/null || echo "{}"
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$SCRATCH_DIR"' EXIT

cmd_validate() {
  if ! bicep_local_build; then
    build_err="$(mask_secrets < "$SCRATCH_DIR/bicep-build.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "BICEP_BUILD_FAILED" "Local Bicep build failed: $build_err"
  fi
  log_success "Local Bicep build passed"

  if [ "$LOCAL_ONLY" -eq 1 ]; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "null"
    return 0
  fi

  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "RESOURCE_GROUP_NOT_FOUND" "Resource group '$RESOURCE_GROUP' does not exist yet; run 'deploy' first to create it"
  fi

  if ! validate_json="$(azure_validate 2>"$SCRATCH_DIR/validate.err")"; then
    err="$(mask_secrets < "$SCRATCH_DIR/validate.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_VALIDATION_FAILED" "Deployment validation failed; no resources were changed: $err"
  fi

  outputs_json=$(echo "$validate_json" | jq '.properties.outputs // {} | with_entries(.value |= {value: .value.value})' 2>/dev/null || echo "{}")
  platform_obj=$(platform_object_from_outputs "$outputs_json")
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$platform_obj"
}

cmd_whatif() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "RESOURCE_GROUP_NOT_FOUND" "Resource group '$RESOURCE_GROUP' does not exist yet; run 'deploy' first to create it"
  fi

  if ! change_count="$(azure_whatif_change_count 2>"$SCRATCH_DIR/whatif.err")"; then
    err="$(mask_secrets < "$SCRATCH_DIR/whatif.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_WHATIF_FAILED" "What-if failed: $err"
  fi

  outputs_json="$(latest_deployment_outputs | jq 'with_entries(.value |= {value: .value.value})' 2>/dev/null || echo "{}")"
  platform_obj=$(platform_object_from_outputs "$outputs_json")

  if [ "$change_count" -eq 0 ]; then
    emit_json_envelope "$DATA_KEY" "$ACTION" "NoChange" "$OP_ID" "$platform_obj"
  else
    log_info "what-if reports $change_count pending change(s)"
    emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$platform_obj"
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
  ensure_resource_group

  if ! azure_validate >"$SCRATCH_DIR/validate.out" 2>"$SCRATCH_DIR/validate.err"; then
    err="$(mask_secrets < "$SCRATCH_DIR/validate.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_VALIDATION_FAILED" "Deployment validation failed; no resources were changed: $err"
  fi

  if ! change_count="$(azure_whatif_change_count 2>"$SCRATCH_DIR/whatif.err")"; then
    err="$(mask_secrets < "$SCRATCH_DIR/whatif.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_WHATIF_FAILED" "What-if failed: $err"
  fi

  if [ "$change_count" -eq 0 ]; then
    log_success "what-if reports no changes; converged (NoChange)"
    outputs_json="$(latest_deployment_outputs | jq 'with_entries(.value |= {value: .value.value})' 2>/dev/null || echo "{}")"
    platform_obj=$(platform_object_from_outputs "$outputs_json")
    emit_json_envelope "$DATA_KEY" "$ACTION" "NoChange" "$OP_ID" "$platform_obj"
    return 0
  fi

  if ! deploy_json="$(azure_deploy 2>"$SCRATCH_DIR/deploy.err")"; then
    err="$(mask_secrets < "$SCRATCH_DIR/deploy.err")"
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "AZURE_DEPLOY_FAILED" "Deployment failed: $err"
  fi

  outputs_json=$(echo "$deploy_json" | jq '.properties.outputs // {} | with_entries(.value |= {value: .value.value})' 2>/dev/null || echo "{}")
  platform_obj=$(platform_object_from_outputs "$outputs_json")
  log_success "Deployment succeeded"
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$platform_obj"
}

cmd_outputs() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "RESOURCE_GROUP_NOT_FOUND" "Resource group '$RESOURCE_GROUP' does not exist"
  fi

  outputs_json="$(latest_deployment_outputs | jq 'with_entries(.value |= {value: .value.value})' 2>/dev/null || echo "{}")"
  if [ "$outputs_json" = "{}" ]; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "NO_DEPLOYMENT_FOUND" "No prior deployment found in resource group '$RESOURCE_GROUP'"
  fi
  platform_obj=$(platform_object_from_outputs "$outputs_json")
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$platform_obj"
}

cmd_status() {
  require_azure_login
  require_subscription "$SUBSCRIPTION_ID"

  if ! az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "RESOURCE_GROUP_NOT_FOUND" "Resource group '$RESOURCE_GROUP' does not exist"
  fi

  profile_name="$(front_door_profile_name)"
  if ! az profile show --resource-group "$RESOURCE_GROUP" --profile-name "$profile_name" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail_fast "$DATA_KEY" "$ACTION" "$OP_ID" "PROFILE_NOT_FOUND" "Front Door profile '$profile_name' does not exist; run 'deploy' first"
  fi

  outputs_json="$(latest_deployment_outputs | jq 'with_entries(.value |= {value: .value.value})' 2>/dev/null || echo "{}")"
  platform_obj=$(platform_object_from_outputs "$outputs_json")
  emit_json_envelope "$DATA_KEY" "$ACTION" "Succeeded" "$OP_ID" "$platform_obj"
}

case "$ACTION" in
  validate) cmd_validate ;;
  what-if) cmd_whatif ;;
  deploy) cmd_deploy ;;
  outputs) cmd_outputs ;;
  status) cmd_status ;;
esac
