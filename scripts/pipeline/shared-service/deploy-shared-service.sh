#!/bin/bash
# Run the shared service deployment CLI and retain sanitized JSON artifacts.
# Bash 3.2 compatible.

set -u
set -o pipefail

RESULT_FILE="${SHARED_PUBLICATION_RESULT_FILE:-shared-publication-result.json}"
ENVIRONMENT_NAME="${DEPLOYMENT_ENVIRONMENT:-${ENVIRONMENT:-}}"
BASE_NAME="${BASE_NAME:-gvt}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
LOCATION="${AZURE_LOCATION:-${LOCATION:-}}"

write_fallback() {
  file="$1"
  action="$2"
  status="$3"
  code="$4"
  message="$5"
  jq -n \
    --arg action "$action" \
    --arg status "$status" \
    --arg operationId "shared-${ENVIRONMENT_NAME:-unknown}-${GITHUB_RUN_ID:-local}" \
    --arg code "$code" \
    --arg message "$message" \
    '{
      schemaVersion: "1.0",
      action: $action,
      status: $status,
      operationId: $operationId,
      sharedService: null,
      diagnostics: [{code:$code,message:$message}]
    }' > "$file"
}

run_shared_service() {
  action="$1"
  output_file="$2"
  shift 2
  set +e
  ./scripts/shared-service.sh "$action" \
    --environment "$ENVIRONMENT_NAME" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --shared-resource-group "$SHARED_RESOURCE_GROUP" \
    --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
    --front-door-profile "$FRONT_DOOR_PROFILE" \
    --base-name "$BASE_NAME" \
    "$@" > "$output_file"
  rc=$?
  set -e
  if [ ! -s "$output_file" ] || ! jq -e 'type == "object" and has("status") and has("sharedService")' "$output_file" >/dev/null 2>&1; then
    write_fallback "$output_file" "$action" "Failed" "INVALID_SHARED_SERVICE_RESULT" "shared-service.sh did not emit a valid JSON result"
    return 1
  fi
  return "$rc"
}

set -e

if [ -z "$ENVIRONMENT_NAME" ] || [ -z "$SUBSCRIPTION_ID" ] || [ -z "${SHARED_RESOURCE_GROUP:-}" ] ||
   [ -z "${PLATFORM_RESOURCE_GROUP:-}" ] || [ -z "${FRONT_DOOR_PROFILE:-}" ]; then
  write_fallback shared-deployment.json deploy Failed MISSING_DEPLOYMENT_INPUT "Required shared deployment inputs are missing"
  exit 1
fi

run_shared_service inventory shared-inventory-before.json || true

if az group show --name "$SHARED_RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
  if ! run_shared_service validate shared-validation.json; then
    jq '.stage = "Validate" | .status = "Failed" |
      .diagnostics = [{code:"SHARED_VALIDATION_FAILED",message:"Shared-service validation failed before deployment"}]' \
      "$RESULT_FILE" > shared-publication-result.tmp 2>/dev/null || true
    [ -s shared-publication-result.tmp ] && mv shared-publication-result.tmp "$RESULT_FILE"
    exit 1
  fi
  if ! run_shared_service what-if shared-what-if.json; then
    jq '.stage = "WhatIf" | .status = "Failed" |
      .diagnostics = [{code:"SHARED_WHATIF_FAILED",message:"Shared-service what-if failed before deployment"}]' \
      "$RESULT_FILE" > shared-publication-result.tmp 2>/dev/null || true
    [ -s shared-publication-result.tmp ] && mv shared-publication-result.tmp "$RESULT_FILE"
    exit 1
  fi
else
  write_fallback shared-validation.json validate Succeeded FIRST_DEPLOYMENT_VALIDATION_DEFERRED "Shared resource group does not exist yet; deploy will create it and run validation before mutation"
  write_fallback shared-what-if.json what-if Succeeded FIRST_DEPLOYMENT_WHATIF_DEFERRED "Shared resource group does not exist yet; deploy will create it and run what-if before mutation"
fi

deploy_args="--confirm --non-interactive"
if [ -n "$LOCATION" ]; then
  if ! run_shared_service deploy shared-deployment.json --location "$LOCATION" --confirm --non-interactive; then
    DEPLOY_STATUS="$(jq -r '.status // "Invalid"' shared-deployment.json 2>/dev/null || echo Invalid)"
    jq --arg status "$DEPLOY_STATUS" \
      '.stage = "Deploy" | .status = "Failed" | .deploymentResultFile = "shared-deployment.json" |
       .diagnostics = [{code:"SHARED_DEPLOYMENT_FAILED",message:("Shared deployment returned " + $status)}]' \
      "$RESULT_FILE" > shared-publication-result.tmp 2>/dev/null || true
    [ -s shared-publication-result.tmp ] && mv shared-publication-result.tmp "$RESULT_FILE"
    run_shared_service inventory shared-inventory-after.json || true
    exit 1
  fi
else
  if ! run_shared_service deploy shared-deployment.json --confirm --non-interactive; then
    DEPLOY_STATUS="$(jq -r '.status // "Invalid"' shared-deployment.json 2>/dev/null || echo Invalid)"
    jq --arg status "$DEPLOY_STATUS" \
      '.stage = "Deploy" | .status = "Failed" | .deploymentResultFile = "shared-deployment.json" |
       .diagnostics = [{code:"SHARED_DEPLOYMENT_FAILED",message:("Shared deployment returned " + $status)}]' \
      "$RESULT_FILE" > shared-publication-result.tmp 2>/dev/null || true
    [ -s shared-publication-result.tmp ] && mv shared-publication-result.tmp "$RESULT_FILE"
    run_shared_service inventory shared-inventory-after.json || true
    exit 1
  fi
fi

run_shared_service inventory shared-inventory-after.json || true

DEPLOYMENT_STATUS="$(jq -r '.status // "Invalid"' shared-deployment.json)"
case "$DEPLOYMENT_STATUS" in
  Succeeded|NoChange) ;;
  *)
    echo "::error::Shared deployment returned $DEPLOYMENT_STATUS"
    exit 1
    ;;
esac

STATIC_WEB_APP_ID="$(jq -r '.sharedService.staticWebAppId // empty' shared-deployment.json)"
STORAGE_ACCOUNT_ID="$(jq -r '.sharedService.storageAccountId // empty' shared-deployment.json)"
ORIGIN_HOSTNAME="$(jq -r '.sharedService.originHostName // empty' shared-deployment.json)"
PUBLIC_URL="$(jq -r '.sharedService.publicUrl // empty' shared-deployment.json)"
STATIC_WEB_APP_NAME="${STATIC_WEB_APP_ID##*/}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_ID##*/}"

{
  echo "STATIC_WEB_APP=$STATIC_WEB_APP_NAME"
  echo "STATIC_WEB_APP_DEFAULT_HOSTNAME=$ORIGIN_HOSTNAME"
  echo "STORAGE_ACCOUNT=$STORAGE_ACCOUNT_NAME"
  echo "AZURE_RESOURCE_GROUP=$SHARED_RESOURCE_GROUP"
  echo "SHARED_PUBLIC_URL=$PUBLIC_URL"
} >> "${GITHUB_ENV:-/dev/null}"

{
  echo "staticWebAppName=$STATIC_WEB_APP_NAME"
  echo "staticWebAppDefaultHostname=$ORIGIN_HOSTNAME"
  echo "storageAccountName=$STORAGE_ACCOUNT_NAME"
  echo "sharedPublicUrl=$PUBLIC_URL"
} >> "${GITHUB_OUTPUT:-/dev/null}"

jq --arg status "$DEPLOYMENT_STATUS" --arg url "$PUBLIC_URL" \
  '.stage = "Deploy" | .status = $status | .publishedUrl = (if $url == "" then null else $url end) |
   .deploymentResultFile = "shared-deployment.json" |
   .diagnostics = [{code:("SHARED_DEPLOYMENT_" + $status),message:("Shared deployment returned " + $status)}]' \
  "$RESULT_FILE" > shared-publication-result.tmp
mv shared-publication-result.tmp "$RESULT_FILE"
