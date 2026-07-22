#!/bin/bash
# ============================================================================
# cors-add-origin.sh - Ad-hoc operational script
# ============================================================================
# Adds one or more browser origins (e.g. a Front Door endpoint hostname) to
# an existing instance's Storage Account Table service CORS rules, WITHOUT
# redeploying the instance or touching infra/main.bicep's corsAllowedOrigins
# list.
#
# This is a stop-gap: once instance registration automation (User Story 2,
# T033-T037) lands, the Front Door endpoint hostname should be added to
# corsAllowedOrigins and redeployed through infra/main.bicep instead so it
# survives a full redeploy. Until then, existing instances with data need
# their storage account's CORS rules patched directly so the SPA (now
# served from the Front Door hostname) can call Azure Table Storage from
# the browser.
#
# Usage:
#   scripts/cors-add-origin.sh \
#     --storage-account-name <name> \
#     --origin https://<endpoint>.z01.azurefd.net \
#     [--origin https://<other-origin> ...] \
#     [--resource-group <rg>] \
#     [--subscription-id <sub-id>] \
#     [--services t] \
#     [--dry-run]
#
# Idempotent: an origin already present in the table service's CORS rules
# is skipped rather than re-added.
#
# Bash 3.2 compatible. Requires: az, jq.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/azure-common.sh
. "$SCRIPT_DIR/lib/azure-common.sh"

STORAGE_ACCOUNT_NAME=""
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
SERVICES="t"
DRY_RUN="false"
ORIGINS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --storage-account-name) STORAGE_ACCOUNT_NAME="${2:-}"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --services) SERVICES="${2:-t}"; shift 2 ;;
    --origin) ORIGINS="${ORIGINS} ${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift 1 ;;
    -h|--help)
      echo "Usage: $0 --storage-account-name <name> --origin <https://...> [--origin <https://...> ...] [--resource-group <rg>] [--subscription-id <sub-id>] [--services t] [--dry-run]"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

require_value "--storage-account-name" "$STORAGE_ACCOUNT_NAME"
[ -n "$(echo "$ORIGINS" | tr -d '[:space:]')" ] || die "at least one --origin is required"

require_cmd az
require_cmd jq
require_azure_login

if [ -n "$SUBSCRIPTION_ID" ]; then
  require_subscription "$SUBSCRIPTION_ID"
fi

if [ -z "$RESOURCE_GROUP" ]; then
  log_info "resolving resource group for storage account: $STORAGE_ACCOUNT_NAME"
  RESOURCE_GROUP=$(az storage account list \
    --query "[?name=='${STORAGE_ACCOUNT_NAME}'].resourceGroup | [0]" \
    -o tsv 2>/dev/null)
  [ -n "$RESOURCE_GROUP" ] || die "could not find storage account '$STORAGE_ACCOUNT_NAME' in the current subscription; pass --resource-group explicitly"
fi
log_info "storage account: $STORAGE_ACCOUNT_NAME (resource group: $RESOURCE_GROUP)"

ACCOUNT_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" -o tsv 2>/dev/null)
[ -n "$ACCOUNT_KEY" ] || die "unable to retrieve an account key for storage account: $STORAGE_ACCOUNT_NAME"

EXISTING_RULES_JSON=$(az storage cors list \
  --services "$SERVICES" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$ACCOUNT_KEY" \
  -o json 2>/dev/null)
[ -n "$EXISTING_RULES_JSON" ] || EXISTING_RULES_JSON="[]"

origin_already_present() {
  target_origin="$1"
  if echo "$EXISTING_RULES_JSON" | jq -e --arg o "$target_origin" \
    '[.[] | ((.allowedOrigins // []) + (.AllowedOrigins // []))[]] |
      any(. == $o or . == "*")' >/dev/null 2>&1; then
    return 0
  fi

  # The Azure CLI response is a snapshot, so also account for rules added
  # earlier in this invocation.
  for added_origin in $ADDED_ORIGINS; do
    [ "$added_origin" = "$target_origin" ] && return 0
  done
  return 1
}

ADDED=0
SKIPPED=0
ADDED_ORIGINS=""
for origin in $ORIGINS; do
  [ -n "$origin" ] || continue

  if origin_already_present "$origin"; then
    log_info "already allowed, skipping: $origin"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[dry-run] would add CORS rule for services='$SERVICES' origin: $origin"
    ADDED=$((ADDED + 1))
    ADDED_ORIGINS="${ADDED_ORIGINS} ${origin}"
    continue
  fi

  log_info "adding CORS rule for services='$SERVICES' origin: $origin"
  az storage cors add \
    --services "$SERVICES" \
    --methods GET POST PUT DELETE MERGE OPTIONS HEAD \
    --origins "$origin" \
    --allowed-headers '*' \
    --exposed-headers '*' \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$ACCOUNT_KEY" \
    --max-age 3600 \
    -o none \
    || die "failed to add CORS rule for origin: $origin"

  ADDED=$((ADDED + 1))
  ADDED_ORIGINS="${ADDED_ORIGINS} ${origin}"
done

log_success "done: $ADDED origin(s) added/dry-run, $SKIPPED already present"
