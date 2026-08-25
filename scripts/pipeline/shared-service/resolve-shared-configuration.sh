#!/bin/bash
# Resolve environment-scoped shared service coordinates. This adapter accepts
# no instance identifier because the persistent path deploys one shared service.
# Bash 3.2 compatible.

set -e

RESULT_FILE="${SHARED_PUBLICATION_RESULT_FILE:-shared-publication-result.json}"
ENVIRONMENT_NAME="${DEPLOYMENT_ENVIRONMENT:-${ENVIRONMENT:-}}"
CONFIG_OK=true
SHARED_RESOURCE_GROUP=""
PLATFORM_RESOURCE_GROUP=""
FRONT_DOOR_PROFILE=""

case "$ENVIRONMENT_NAME" in
  dev)
    SHARED_RESOURCE_GROUP="${SHARED_RESOURCE_GROUP_DEV:-}"
    PLATFORM_RESOURCE_GROUP="${PLATFORM_RESOURCE_GROUP_DEV:-}"
    FRONT_DOOR_PROFILE="${FRONT_DOOR_PROFILE_DEV:-}"
    ;;
  staging)
    SHARED_RESOURCE_GROUP="${SHARED_RESOURCE_GROUP_STAGING:-}"
    PLATFORM_RESOURCE_GROUP="${PLATFORM_RESOURCE_GROUP_STAGING:-}"
    FRONT_DOOR_PROFILE="${FRONT_DOOR_PROFILE_STAGING:-}"
    ;;
  prod)
    SHARED_RESOURCE_GROUP="${SHARED_RESOURCE_GROUP_PROD:-}"
    PLATFORM_RESOURCE_GROUP="${PLATFORM_RESOURCE_GROUP_PROD:-}"
    FRONT_DOOR_PROFILE="${FRONT_DOOR_PROFILE_PROD:-}"
    ;;
  *)
    CONFIG_OK=false
    ;;
esac

[ -n "$SHARED_RESOURCE_GROUP" ] || CONFIG_OK=false
[ -n "$PLATFORM_RESOURCE_GROUP" ] || CONFIG_OK=false
[ -n "$FRONT_DOOR_PROFILE" ] || CONFIG_OK=false

if [ "$CONFIG_OK" != "true" ]; then
  MISSING_INPUTS=""
  [ -n "$SHARED_RESOURCE_GROUP" ] || MISSING_INPUTS="shared resource group"
  [ -n "$PLATFORM_RESOURCE_GROUP" ] || MISSING_INPUTS="${MISSING_INPUTS:+$MISSING_INPUTS, }platform resource group"
  [ -n "$FRONT_DOOR_PROFILE" ] || MISSING_INPUTS="${MISSING_INPUTS:+$MISSING_INPUTS, }Front Door profile"
  case "$ENVIRONMENT_NAME" in
    dev|staging|prod) ;;
    *) MISSING_INPUTS="${MISSING_INPUTS:+$MISSING_INPUTS, }supported deployment environment" ;;
  esac

  if [ -f "$RESULT_FILE" ]; then
    jq --arg missing "$MISSING_INPUTS" \
      '.stage = "Preflight" | .status = "Failed" |
       .diagnostics = [{code:"MISSING_SHARED_CONFIGURATION",message:("Missing or invalid " + $missing)}]' \
      "$RESULT_FILE" > shared-publication-result.tmp
    mv shared-publication-result.tmp "$RESULT_FILE"
  fi
  echo "::error::Missing shared service configuration: $MISSING_INPUTS"
  exit 1
fi

{
  echo "DEPLOYMENT_ENVIRONMENT=$ENVIRONMENT_NAME"
  echo "SHARED_RESOURCE_GROUP=$SHARED_RESOURCE_GROUP"
  echo "PLATFORM_RESOURCE_GROUP=$PLATFORM_RESOURCE_GROUP"
  echo "FRONT_DOOR_PROFILE=$FRONT_DOOR_PROFILE"
} >> "${GITHUB_ENV:-/dev/null}"

{
  echo "environment=$ENVIRONMENT_NAME"
  echo "sharedResourceGroup=$SHARED_RESOURCE_GROUP"
  echo "platformResourceGroup=$PLATFORM_RESOURCE_GROUP"
  echo "frontDoorProfile=$FRONT_DOOR_PROFILE"
} >> "${GITHUB_OUTPUT:-/dev/null}"
