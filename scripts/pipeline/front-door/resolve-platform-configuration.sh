#!/usr/bin/env bash
set -e

set +e
CONFIG_OK=true
PLATFORM_RESOURCE_GROUP=""
FRONT_DOOR_PROFILE=""
case "$DEPLOYMENT_ENVIRONMENT" in
  dev) PLATFORM_RESOURCE_GROUP="$PLATFORM_RESOURCE_GROUP_DEV"; FRONT_DOOR_PROFILE="$FRONT_DOOR_PROFILE_DEV" ;;
  staging) PLATFORM_RESOURCE_GROUP="$PLATFORM_RESOURCE_GROUP_STAGING"; FRONT_DOOR_PROFILE="$FRONT_DOOR_PROFILE_STAGING" ;;
  prod) PLATFORM_RESOURCE_GROUP="$PLATFORM_RESOURCE_GROUP_PROD"; FRONT_DOOR_PROFILE="$FRONT_DOOR_PROFILE_PROD" ;;
  *) CONFIG_OK=false ;;
esac
[ -n "${PLATFORM_RESOURCE_GROUP:-}" ] || CONFIG_OK=false
[ -n "${FRONT_DOOR_PROFILE:-}" ] || CONFIG_OK=false
if [ "$CONFIG_OK" != "true" ]; then
  MISSING_INPUTS=""
  [ -n "$PLATFORM_RESOURCE_GROUP" ] || MISSING_INPUTS="platform resource group"
  [ -n "$FRONT_DOOR_PROFILE" ] || MISSING_INPUTS="${MISSING_INPUTS:+$MISSING_INPUTS, }Front Door profile"
  [ "$DEPLOYMENT_ENVIRONMENT" = "dev" ] || [ "$DEPLOYMENT_ENVIRONMENT" = "staging" ] || [ "$DEPLOYMENT_ENVIRONMENT" = "prod" ] ||
    MISSING_INPUTS="${MISSING_INPUTS:+$MISSING_INPUTS, }supported deployment environment"
  jq --arg missing "$MISSING_INPUTS" \
    '.stage = "Preflight" | .status = "Failed" |
     .diagnostics = [{code:"MISSING_PLATFORM_CONFIGURATION",message:("Missing or invalid " + $missing)}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  exit 1
fi
{
  echo "PLATFORM_RESOURCE_GROUP=$PLATFORM_RESOURCE_GROUP"
  echo "FRONT_DOOR_PROFILE=$FRONT_DOOR_PROFILE"
} >> "$GITHUB_ENV"
