#!/bin/bash
# T031: Verifies a rejected origin update preserves the active route, then a
# valid replacement origin retains the same endpoint and does not mutate a
# sibling's Front Door resource graph.
# Opt-in Azure test: set RUN_AZURE_INTEGRATION=1, ROUTE_* variables,
# ROUTE_REPLACEMENT_ORIGIN, and ROUTE_SIBLING_INSTANCE_ID.

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
: "${ROUTE_SIBLING_INSTANCE_ID:?required}"

[ "$ROUTE_SIBLING_INSTANCE_ID" != "$ROUTE_INSTANCE_ID" ] || {
  echo "[origin-update-preservation] sibling instance must differ from target" >&2
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

status_args="--instance-id $ROUTE_INSTANCE_ID --instance-resource-group $ROUTE_INSTANCE_RESOURCE_GROUP --static-web-app-name $ROUTE_STATIC_WEB_APP_NAME --platform-resource-group $ROUTE_PLATFORM_RESOURCE_GROUP --front-door-profile $ROUTE_FRONT_DOOR_PROFILE --subscription-id $ROUTE_SUBSCRIPTION_ID"

# Keep only stable resource properties. Azure-generated metadata and
# provisioning state are intentionally excluded from the comparison.
snapshot_sibling() {
  output_file="$1"
  endpoint_file="$TMP_DIR/sibling-endpoint.json"
  route_file="$TMP_DIR/sibling-route.json"
  origin_group_file="$TMP_DIR/sibling-origin-group.json"
  origin_file="$TMP_DIR/sibling-origin.json"
  waf_file="$TMP_DIR/sibling-waf.json"

  az afd endpoint list --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
    --profile-name "$ROUTE_FRONT_DOOR_PROFILE" --subscription "$ROUTE_SUBSCRIPTION_ID" \
    --query "[?tags.instanceId=='${ROUTE_SIBLING_INSTANCE_ID}'] | [0]" -o json \
    >"$endpoint_file" 2>/dev/null || return 1
  endpoint_name=$(jq -r '.name // empty' "$endpoint_file")
  endpoint_id=$(jq -r '.id // empty' "$endpoint_file")
  [ -n "$endpoint_name" ] && [ -n "$endpoint_id" ] || return 1

  az afd route show --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
    --profile-name "$ROUTE_FRONT_DOOR_PROFILE" --endpoint-name "$endpoint_name" \
    --route-name "route-${ROUTE_SIBLING_INSTANCE_ID}" \
    --subscription "$ROUTE_SUBSCRIPTION_ID" -o json >"$route_file" 2>/dev/null || return 1
  az afd origin-group show --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
    --profile-name "$ROUTE_FRONT_DOOR_PROFILE" \
    --origin-group-name "og-${ROUTE_SIBLING_INSTANCE_ID}" \
    --subscription "$ROUTE_SUBSCRIPTION_ID" -o json >"$origin_group_file" 2>/dev/null || return 1
  az afd origin show --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
    --profile-name "$ROUTE_FRONT_DOOR_PROFILE" \
    --origin-group-name "og-${ROUTE_SIBLING_INSTANCE_ID}" \
    --origin-name "origin-${ROUTE_SIBLING_INSTANCE_ID}" \
    --subscription "$ROUTE_SUBSCRIPTION_ID" -o json >"$origin_file" 2>/dev/null || return 1
  az afd security-policy list --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
    --profile-name "$ROUTE_FRONT_DOOR_PROFILE" --subscription "$ROUTE_SUBSCRIPTION_ID" \
    -o json >"$waf_file" 2>/dev/null || return 1

  jq -S --slurpfile endpoint "$endpoint_file" --slurpfile route "$route_file" \
    --slurpfile originGroup "$origin_group_file" --slurpfile origin "$origin_file" \
    --slurpfile waf "$waf_file" --arg endpointId "$endpoint_id" '
    def normalized: del(.id, .name, .type, .systemData, .etag, .location,
      .provisioningState, .resourceState, .properties.provisioningState);
    {
      endpoint: ($endpoint[0] | normalized),
      route: ($route[0] | normalized),
      originGroup: ($originGroup[0] | normalized),
      origin: ($origin[0] | normalized),
      wafAssociation: ($waf[0] | map(select(
        any(.parameters.associations[]?.domains[]?.id;
          ascii_downcase == ($endpointId | ascii_downcase))
      )) | map(normalized))
    }' >"$output_file"
}

"$CLI" status $status_args >"$TMP_DIR/before.json"
before_hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/before.json")
[ -n "$before_hostname" ] && [ "$before_hostname" != "null" ] || { echo "[origin-update-preservation] baseline route is required" >&2; exit 1; }
snapshot_sibling "$TMP_DIR/sibling-before.json" || { echo "[origin-update-preservation] could not snapshot sibling resource graph" >&2; exit 1; }

if "$CLI" register --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT" --origin-hostname invalid.example >"$TMP_DIR/rejected.json" 2>"$TMP_DIR/rejected.err"; then
  echo "[origin-update-preservation] invalid replacement unexpectedly succeeded" >&2
  exit 1
fi
"$CLI" status $status_args >"$TMP_DIR/after-rejected.json"
[ "$(jq -r '.route.endpointHostName' "$TMP_DIR/after-rejected.json")" = "$before_hostname" ] || { echo "[origin-update-preservation] rejected update changed active endpoint" >&2; exit 1; }
snapshot_sibling "$TMP_DIR/sibling-after-rejected.json" || { echo "[origin-update-preservation] could not snapshot sibling after rejected update" >&2; exit 1; }
cmp -s "$TMP_DIR/sibling-before.json" "$TMP_DIR/sibling-after-rejected.json" || { echo "[origin-update-preservation] rejected update changed sibling resource graph" >&2; exit 1; }

"$CLI" register --instance-id "$ROUTE_INSTANCE_ID" --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" --subscription-id "$ROUTE_SUBSCRIPTION_ID" --environment "$ROUTE_ENVIRONMENT" --origin-hostname "$ROUTE_REPLACEMENT_ORIGIN" >"$TMP_DIR/updated.json"
updated_hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/updated.json")
[ "$updated_hostname" = "$before_hostname" ] || { echo "[origin-update-preservation] origin update changed endpoint hostname" >&2; exit 1; }
snapshot_sibling "$TMP_DIR/sibling-after-update.json" || { echo "[origin-update-preservation] could not snapshot sibling after valid update" >&2; exit 1; }
cmp -s "$TMP_DIR/sibling-before.json" "$TMP_DIR/sibling-after-update.json" || { echo "[origin-update-preservation] valid update changed sibling resource graph" >&2; exit 1; }

echo "[origin-update-preservation] passed: rejected update preserved active route; valid update retained $before_hostname and sibling resources" >&2
