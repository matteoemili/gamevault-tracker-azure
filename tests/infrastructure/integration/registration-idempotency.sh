#!/bin/bash
# T014: Runs registration 20 times with workflow-equivalent inputs and confirms
# one stable published hostname and endpoint.
# This is opt-in because it calls Azure: set RUN_AZURE_INTEGRATION=1 and all
# required ROUTE_* variables before running. Bash 3.2 compatible.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/instance-route.sh"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[registration-idempotency] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${ROUTE_INSTANCE_ID:?required}"
: "${ROUTE_INSTANCE_RESOURCE_GROUP:?required}"
: "${ROUTE_STATIC_WEB_APP_NAME:?required}"
: "${ROUTE_PLATFORM_RESOURCE_GROUP:?required}"
: "${ROUTE_FRONT_DOOR_PROFILE:?required}"
: "${ROUTE_SUBSCRIPTION_ID:?required}"
: "${ROUTE_ENVIRONMENT:?required}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
FIRST_HOSTNAME=""
FIRST_PUBLISHED_URL=""
FORWARDING_CONFIG_FILE="$TMP_DIR/route-forwarding-gateway.json"

for attempt in $(seq 1 20); do
  "$CLI" register \
    --instance-id "$ROUTE_INSTANCE_ID" \
    --instance-resource-group "$ROUTE_INSTANCE_RESOURCE_GROUP" \
    --static-web-app-name "$ROUTE_STATIC_WEB_APP_NAME" \
    --platform-resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
    --front-door-profile "$ROUTE_FRONT_DOOR_PROFILE" \
    --subscription-id "$ROUTE_SUBSCRIPTION_ID" \
    --environment "$ROUTE_ENVIRONMENT" \
    --forwarding-config-file "$FORWARDING_CONFIG_FILE" >"$TMP_DIR/result.json"

  hostname=$(jq -r '.route.endpointHostName' "$TMP_DIR/result.json")
  [ -n "$hostname" ] && [ "$hostname" != "null" ] || { echo "[registration-idempotency] missing endpoint hostname on attempt $attempt" >&2; exit 1; }
  if [ -z "$FIRST_HOSTNAME" ]; then
    FIRST_HOSTNAME="$hostname"
  elif [ "$hostname" != "$FIRST_HOSTNAME" ]; then
    echo "[registration-idempotency] hostname changed from $FIRST_HOSTNAME to $hostname on attempt $attempt" >&2
    exit 1
  fi

  published_url=$(jq -r '.route.url' "$TMP_DIR/result.json")
  [ -n "$published_url" ] && [ "$published_url" != "null" ] || { echo "[registration-idempotency] missing published URL on attempt $attempt" >&2; exit 1; }
  if [ -z "$FIRST_PUBLISHED_URL" ]; then
    FIRST_PUBLISHED_URL="$published_url"
  elif [ "$published_url" != "$FIRST_PUBLISHED_URL" ]; then
    echo "[registration-idempotency] published URL changed from $FIRST_PUBLISHED_URL to $published_url on attempt $attempt" >&2
    exit 1
  fi
done

endpoint_count=$(az cdn afd endpoint list \
  --resource-group "$ROUTE_PLATFORM_RESOURCE_GROUP" \
  --profile-name "$ROUTE_FRONT_DOOR_PROFILE" \
  --subscription "$ROUTE_SUBSCRIPTION_ID" \
  --query "[?tags.instanceId=='${ROUTE_INSTANCE_ID}'] | length(@)" -o tsv)
[ "$endpoint_count" = "1" ] || { echo "[registration-idempotency] expected exactly one endpoint, found $endpoint_count" >&2; exit 1; }
echo "[registration-idempotency] passed: 20 runs retained one endpoint at https://$FIRST_HOSTNAME" >&2
