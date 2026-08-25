#!/bin/bash
# Opt-in Azure integration proof for User Story 2 constant-resource scale.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/logical-instance.sh"
GENERATOR="$ROOT_DIR/tests/infrastructure/fixtures/generate-logical-instances.sh"
SHARED_CLI="$ROOT_DIR/scripts/shared-service.sh"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[constant-resource-scale] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${SHARED_ENVIRONMENT:?required}"
: "${SHARED_SUBSCRIPTION_ID:?required}"
: "${SHARED_RESOURCE_GROUP:?required}"
: "${SHARED_PLATFORM_RESOURCE_GROUP:?required}"
: "${SHARED_FRONT_DOOR_PROFILE:?required}"
: "${SHARED_STORAGE_ACCOUNT_NAME:?required}"

# shellcheck source=../../../scripts/lib/azure-common.sh
. "$ROOT_DIR/scripts/lib/azure-common.sh"

SCRATCH_DIR="$ROOT_DIR/.scratch/constant-resource-scale.$$"
mkdir -p "$SCRATCH_DIR" || exit 1
trap 'rm -rf "$SCRATCH_DIR"' EXIT

log() { echo "[constant-resource-scale] $*" >&2; }
die() { log "$*"; exit 1; }

TABLE_NAME="${SHARED_LOGICAL_INSTANCES_TABLE:-logicalinstances}"
BATCH_SIZE="${LOGICAL_INSTANCE_BATCH_SIZE:-100}"
TOTAL="${LOGICAL_INSTANCE_SCALE_COUNT:-10000}"

log "capturing shared inventory before logical reservations"
"$SHARED_CLI" inventory \
  --environment "$SHARED_ENVIRONMENT" \
  --subscription-id "$SHARED_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RESOURCE_GROUP" \
  --platform-resource-group "$SHARED_PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$SHARED_FRONT_DOOR_PROFILE" \
  >"$SCRATCH_DIR/shared-service-before.json" || die "shared-service inventory failed before run"
capture_shared_inventory "$SHARED_SUBSCRIPTION_ID" "$SHARED_RESOURCE_GROUP" "$SHARED_PLATFORM_RESOURCE_GROUP" "$SHARED_FRONT_DOOR_PROFILE" >"$SCRATCH_DIR/inventory-before.json"

"$GENERATOR" "$TOTAL" >"$SCRATCH_DIR/generated.jsonl"
count=0
batch=1
while IFS= read -r line; do
  id=$(printf '%s\n' "$line" | jq -r '.logicalInstanceId')
  display=$(printf '%s\n' "$line" | jq -r '.displayName')
  "$CLI" create \
    --environment "$SHARED_ENVIRONMENT" \
    --subscription-id "$SHARED_SUBSCRIPTION_ID" \
    --storage-account-name "$SHARED_STORAGE_ACCOUNT_NAME" \
    --table-name "$TABLE_NAME" \
    --logical-instance-id "$id" \
    --display-name "$display" \
    >"$SCRATCH_DIR/create-result.json" || die "create failed for $id: $(jq -c '.diagnostics' "$SCRATCH_DIR/create-result.json" 2>/dev/null)"
  status=$(jq -r '.status' "$SCRATCH_DIR/create-result.json")
  case "$status" in Succeeded|NoChange) ;; *) die "unexpected create status '$status' for $id" ;; esac
  count=$((count + 1))
  if [ $((count % BATCH_SIZE)) -eq 0 ]; then
    log "applied batch $batch ($count/$TOTAL reservations)"
    batch=$((batch + 1))
  fi
done <"$SCRATCH_DIR/generated.jsonl"
[ "$count" -eq "$TOTAL" ] || die "expected $TOTAL generated records, applied $count"

log "checking duplicate and case-variant idempotency/conflict handling"
"$CLI" create --environment "$SHARED_ENVIRONMENT" --subscription-id "$SHARED_SUBSCRIPTION_ID" \
  --storage-account-name "$SHARED_STORAGE_ACCOUNT_NAME" --table-name "$TABLE_NAME" \
  --logical-instance-id "LI-00001" --display-name "Logical Instance 00001" \
  >"$SCRATCH_DIR/duplicate.json" || die "case-variant duplicate should be idempotent"
jq -e '.status == "NoChange"' "$SCRATCH_DIR/duplicate.json" >/dev/null || die "case-variant duplicate did not return NoChange"

if "$CLI" create --environment "$SHARED_ENVIRONMENT" --subscription-id "$SHARED_SUBSCRIPTION_ID" \
  --storage-account-name "$SHARED_STORAGE_ACCOUNT_NAME" --table-name "$TABLE_NAME" \
  --logical-instance-id "li-00001" --display-name "Conflicting Display" \
  >"$SCRATCH_DIR/conflict.json"; then
  die "conflicting duplicate unexpectedly succeeded"
fi
jq -e '.status == "Failed" and .diagnostics[0].code == "INSTANCE_CONFLICT"' "$SCRATCH_DIR/conflict.json" >/dev/null \
  || die "conflicting duplicate did not return INSTANCE_CONFLICT"

log "capturing shared inventory after logical reservations"
"$SHARED_CLI" inventory \
  --environment "$SHARED_ENVIRONMENT" \
  --subscription-id "$SHARED_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RESOURCE_GROUP" \
  --platform-resource-group "$SHARED_PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$SHARED_FRONT_DOOR_PROFILE" \
  >"$SCRATCH_DIR/shared-service-after.json" || die "shared-service inventory failed after run"
capture_shared_inventory "$SHARED_SUBSCRIPTION_ID" "$SHARED_RESOURCE_GROUP" "$SHARED_PLATFORM_RESOURCE_GROUP" "$SHARED_FRONT_DOOR_PROFILE" >"$SCRATCH_DIR/inventory-after.json"
compare_shared_inventory "$SCRATCH_DIR/inventory-before.json" "$SCRATCH_DIR/inventory-after.json" \
  || die "shared inventory changed after logical-instance scale test"

log "constant-resource scale proof passed for $TOTAL logical reservations"
