#!/bin/bash
# T031: Verifies a rejected origin update preserves the active route, then a
# valid replacement origin retains the same Azure-managed endpoint hostname.
# Opt-in Azure test: set RUN_AZURE_INTEGRATION=1, ROUTE_* variables, and
# ROUTE_REPLACEMENT_ORIGIN (an HTTPS-reachable *.azurestaticapps.net hostname).

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/instance-route.sh"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[origin-update-preservation] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${ROUTE_INSTANCE_ID:?required}"
: "${ROUTE_INSTANCE_RESOURCE_GROUP:?required}"
: "${ROUTE_STATIC_WEB_APP_NAME:?required}"
: "${ROUTE_PLATFORM_RESOURCE_GROUP:?required}"
: "${ROUTE_FRONT_DOOR_PROFILE:?required}"
: "${ROUTE_SUBSCRIPTION_ID:?required}"
: "${ROUTE_ENVIRONMENT:?required}"
: "${ROUTE_REPLACEMENT_ORIGIN:?required}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

status_args="--instance-id $ROUTE_INSTANCE_ID --instance-resource-group $ROUTE_INSTANCE_RESOURCE_GROUP --static-web-app-name $ROUTE_STATIC_WEB_APP_NAME --platform-resource-group $ROUTE_PLATFORM_RESOURCE_GROUP --front-door-profile $ROUTE_FRONT_DOOR_PROFILE --subscription-id $ROUTE_SUBSCRIPTION_ID"
"$CLI" status $status_args >"$TMP_DIR/before.json"
before_hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/before.json")
[ -n "$before_hostname" ] && [ "$before_hostname" != "null" ] || { echo "[origin-update-preservation] baseline route is required" >&2; exit 1; }

if "$CLI" register --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT" --origin-hostname invalid.example >"$TMP_DIR/rejected.json" 2>"$TMP_DIR/rejected.err"; then
  echo "[origin-update-preservation] invalid replacement unexpectedly succeeded" >&2
  exit 1
fi
"$CLI" status $status_args >"$TMP_DIR/after-rejected.json"
[ "$(jq -r '.route.endpointHostName' "$TMP_DIR/after-rejected.json")" = "$before_hostname" ] || { echo "[origin-update-preservation] rejected update changed active endpoint" >&2; exit 1; }

"$CLI" register --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT" --origin-hostname "$ROUTE_REPLACEMENT_ORIGIN" >"$TMP_DIR/updated.json"
updated_hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/updated.json")
[ "$updated_hostname" = "$before_hostname" ] || { echo "[origin-update-preservation] origin update changed endpoint hostname" >&2; exit 1; }

echo "[origin-update-preservation] passed: rejected update preserved active route; valid update retained $before_hostname" >&2
