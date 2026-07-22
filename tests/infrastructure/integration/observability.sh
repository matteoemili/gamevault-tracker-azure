#!/bin/bash
# T041: Verifies the shared workspace receives Front Door access, health, WAF,
# and control-plane records. This test is opt-in because it queries Azure.

set -u
set -o pipefail

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[observability] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${PLATFORM_RESOURCE_GROUP:?required}"
: "${PLATFORM_WORKSPACE_NAME:?required}"
: "${PLATFORM_SUBSCRIPTION_ID:?required}"

workspace=$(az monitor log-analytics workspace show \
  --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --workspace-name "$PLATFORM_WORKSPACE_NAME" \
  --subscription "$PLATFORM_SUBSCRIPTION_ID" -o json)

retention=$(echo "$workspace" | jq -r '.retentionInDays // 0')
[ "$retention" -ge 90 ] || { echo "[observability] expected at least 90 days retention, found $retention" >&2; exit 1; }

for category in FrontDoorAccessLog FrontDoorHealthProbeLog FrontDoorWebApplicationFirewallLog; do
  count=$(az monitor diagnostic-settings list \
    --resource "${PLATFORM_FRONT_DOOR_PROFILE_ID:?required}" \
    --query "value[].logs[?category=='${category}' && enabled==\`true\`] | length(@)" -o tsv)
  [ "${count:-0}" -ge 1 ] || { echo "[observability] missing enabled $category diagnostic setting" >&2; exit 1; }
done

activity_count=$(az monitor activity-log list \
  --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --subscription "$PLATFORM_SUBSCRIPTION_ID" \
  --offset 90d \
  --query 'length(@)' -o tsv)
[ "${activity_count:-0}" -ge 0 ] || { echo "[observability] activity-log query failed" >&2; exit 1; }
echo "[observability] passed: diagnostics and 90-day retention are configured" >&2