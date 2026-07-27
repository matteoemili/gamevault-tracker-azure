#!/usr/bin/env bash
set -e

set +e
SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null)"
PREFLIGHT_OK=true
test -n "$SUBSCRIPTION_ID" || PREFLIGHT_OK=false
test -n "$INSTANCE_ID" || PREFLIGHT_OK=false
test -n "$AZURE_RESOURCE_GROUP" || PREFLIGHT_OK=false
test -n "$STATIC_WEB_APP" || PREFLIGHT_OK=false
test -n "$STATIC_WEB_APP_DEFAULT_HOSTNAME" || PREFLIGHT_OK=false
test -n "$STATIC_WEB_APP_ORIGIN_HOSTNAME" || PREFLIGHT_OK=false
test -n "$STORAGE_ACCOUNT" || PREFLIGHT_OK=false
test -n "$PLATFORM_RESOURCE_GROUP" || PREFLIGHT_OK=false
test -n "$FRONT_DOOR_PROFILE" || PREFLIGHT_OK=false
test "$AZURE_RESOURCE_GROUP" != "$PLATFORM_RESOURCE_GROUP" || PREFLIGHT_OK=false
case "$STATIC_WEB_APP_ORIGIN_HOSTNAME" in
  *.azurestaticapps.net) ;;
  *) PREFLIGHT_OK=false ;;
esac
if [ "$PREFLIGHT_OK" != "true" ]; then
  jq '.stage = "Preflight" | .status = "Failed" |
    .diagnostics = [{code:"PREFLIGHT_FAILED",message:"Required publication inputs are missing or inconsistent"}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  exit 1
fi
jq --arg stage "Preflight" --arg subscriptionId "$SUBSCRIPTION_ID" \
  '.stage = $stage | .diagnostics = [{code:"PREFLIGHT_OK",message:("Inputs validated for subscription " + $subscriptionId)}]' \
  publication-result.json > publication-result.tmp
mv publication-result.tmp publication-result.json
echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> "$GITHUB_ENV"
