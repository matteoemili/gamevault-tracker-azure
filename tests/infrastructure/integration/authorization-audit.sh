#!/bin/bash
# T043: The caller must be an intentionally underprivileged Azure identity.
# It verifies a denied mutation and the corresponding activity-log record.

set -u
set -o pipefail

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[authorization-audit] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${PLATFORM_RESOURCE_GROUP:?required}"
: "${PLATFORM_SUBSCRIPTION_ID:?required}"
: "${PLATFORM_FRONT_DOOR_PROFILE:?required}"
: "${ROUTE_INSTANCE_ID:?required}"

endpoint="unauthorized-${ROUTE_INSTANCE_ID}"
if az afd endpoint create \
  --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --profile-name "$PLATFORM_FRONT_DOOR_PROFILE" \
  --endpoint-name "$endpoint" \
  --subscription "$PLATFORM_SUBSCRIPTION_ID" >/dev/null 2>&1; then
  echo "[authorization-audit] mutation unexpectedly succeeded; remove test endpoint immediately" >&2
  exit 1
fi

denied=$(az monitor activity-log list \
  --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --subscription "$PLATFORM_SUBSCRIPTION_ID" \
  --offset 15m \
  --query "[?contains(operationName.value, 'afdEndpoints/write') && status.value=='Failed'] | length(@)" -o tsv)
[ "${denied:-0}" -ge 1 ] || { echo "[authorization-audit] denied endpoint mutation was not found in the activity log" >&2; exit 1; }
echo "[authorization-audit] passed: denied mutation is auditable" >&2