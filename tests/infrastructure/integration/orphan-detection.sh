#!/bin/bash
# T045: Finds endpoint tags that reference a deleted instance resource group
# or Static Web App. It never mutates Azure resources.

set -u
set -o pipefail

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[orphan-detection] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${ROUTE_PLATFORM_RESOURCE_GROUP:?required}"
: "${ROUTE_FRONT_DOOR_PROFILE:?required}"
: "${ROUTE_SUBSCRIPTION_ID:?required}"

endpoints=$(az afd endpoint list \
  --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
  --profile-name "$ROUTE_FRONT_DOOR_PROFILE" \
  --subscription "$ROUTE_SUBSCRIPTION_ID" -o json)
orphans='[]'
while IFS= read -r endpoint; do
  instance_rg=$(echo "$endpoint" | jq -r '.tags.instanceResourceGroup // empty')
  swa_name=$(echo "$endpoint" | jq -r '.tags.staticWebAppName // empty')
  [ -n "$instance_rg" ] && [ -n "$swa_name" ] || continue
  if ! az staticwebapp show --name "$swa_name" --resource-group "$instance_rg" --subscription "$ROUTE_SUBSCRIPTION_ID" >/dev/null 2>&1; then
    orphans=$(echo "$orphans" | jq --arg name "$(echo "$endpoint" | jq -r '.name')" '. + [$name]')
  fi
done <<EOF
$(echo "$endpoints" | jq -c '.[]')
EOF

echo "$orphans" | jq .
echo "[orphan-detection] reported $(echo "$orphans" | jq 'length') orphaned endpoints" >&2