#!/bin/bash
# T044: Removes one route twice and proves every supplied sibling resource ID
# remains present. The target instance must be a disposable integration fixture.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/instance-route.sh"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[deregistration-isolation] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${ROUTE_INSTANCE_ID:?required}"
: "${ROUTE_INSTANCE_RESOURCE_GROUP:?required}"
: "${ROUTE_STATIC_WEB_APP_NAME:?required}"
: "${ROUTE_PLATFORM_RESOURCE_GROUP:?required}"
: "${ROUTE_FRONT_DOOR_PROFILE:?required}"
: "${ROUTE_SUBSCRIPTION_ID:?required}"
: "${SIBLING_ENDPOINT_IDS_JSON:?required}"

before=$(printf '%s' "$SIBLING_ENDPOINT_IDS_JSON" | jq -c 'sort')
"$CLI" unregister \
  --instance-id "$ROUTE_INSTANCE_ID" \
  --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" \
  --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" \
  --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" \
  --subscription-id "$ROUTE_SUBSCRIPTION_ID" \
  --confirm | jq -e '.status == "Succeeded" or .status == "NoChange"' >/dev/null

"$CLI" unregister \
  --instance-id "$ROUTE_INSTANCE_ID" \
  --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" \
  --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" \
  --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" \
  --subscription-id "$ROUTE_SUBSCRIPTION_ID" \
  --confirm | jq -e '.status == "NoChange"' >/dev/null

after=$(az afd endpoint list \
  --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
  --profile-name "$ROUTE_FRONT_DOOR_PROFILE" \
  --subscription "$ROUTE_SUBSCRIPTION_ID" \
  --query '[].id' -o json | jq -c 'sort')
missing=$(jq -n --argjson before "$before" --argjson after "$after" '$before - $after | length')
[ "$missing" = "0" ] || { echo "[deregistration-isolation] a sibling endpoint disappeared" >&2; exit 1; }
echo "[deregistration-isolation] passed: sibling routes are unchanged" >&2