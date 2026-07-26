#!/bin/bash
# T030: Ensures rejected registrations leave an existing route untouched.
# Opt-in Azure test: set RUN_AZURE_INTEGRATION=1 and ROUTE_* variables.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/instance-route.sh"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[registration-rejection] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${ROUTE_INSTANCE_ID:?required}"
: "${ROUTE_INSTANCE_RESOURCE_GROUP:?required}"
: "${ROUTE_STATIC_WEB_APP_NAME:?required}"
: "${ROUTE_PLATFORM_RESOURCE_GROUP:?required}"
: "${ROUTE_FRONT_DOOR_PROFILE:?required}"
: "${ROUTE_SUBSCRIPTION_ID:?required}"
: "${ROUTE_ENVIRONMENT:?required}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

common_args() {
  echo "--instance-resource-group $ROUTE_INSTANCE_RESOURCE_GROUP --static-web-app-name $ROUTE_STATIC_WEB_APP_NAME --platform-resource-group $ROUTE_PLATFORM_RESOURCE_GROUP --front-door-profile $ROUTE_FRONT_DOOR_PROFILE --subscription-id $ROUTE_SUBSCRIPTION_ID --environment $ROUTE_ENVIRONMENT"
}

"$CLI" status --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" >"$TMP_DIR/before.json"
before_hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/before.json")
[ -n "$before_hostname" ] && [ "$before_hostname" != "null" ] || { echo "[registration-rejection] baseline route is required" >&2; exit 1; }

expect_rejected() {
  label="$1"
  shift
  if "$CLI" register "$@" >"$TMP_DIR/rejected.json" 2>"$TMP_DIR/rejected.err"; then
    echo "[registration-rejection] $label unexpectedly succeeded" >&2
    exit 1
  fi
  "$CLI" status --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" >"$TMP_DIR/after.json"
  after_hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/after.json")
  [ "$before_hostname" = "$after_hostname" ] || { echo "[registration-rejection] $label changed active hostname" >&2; exit 1; }
  echo "[registration-rejection] ok: $label preserved $before_hostname" >&2
}

expect_rejected "malformed ID" --instance-id BAD_ID --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT"
expect_rejected "invalid origin hostname" --instance-id "$ROUTE_INSTANCE_ID" --origin-hostname invalid.example --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT"
expect_rejected "invalid scope" --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT"

echo "[registration-rejection] passed" >&2
