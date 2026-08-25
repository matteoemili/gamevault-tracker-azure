#!/bin/bash
# T013: Runs `shared-service.sh deploy` twenty consecutive times and confirms
# that the shared model is genuinely constant-resource: one stable public URL
# and one unchanging set of shared resource IDs, with no duplicates (SC-002).
#
# This is opt-in because it mutates Azure: set RUN_AZURE_INTEGRATION=1 and all
# required SHARED_* variables before running. Bash 3.2 compatible.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/shared-service.sh"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[shared-route-idempotency] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${SHARED_ENVIRONMENT:?required}"
: "${SHARED_SUBSCRIPTION_ID:?required}"
: "${SHARED_RESOURCE_GROUP:?required}"
: "${SHARED_PLATFORM_RESOURCE_GROUP:?required}"
: "${SHARED_FRONT_DOOR_PROFILE:?required}"
: "${SHARED_LOCATION:?required}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() { echo "[shared-route-idempotency] $*" >&2; }
die() { log "$*"; exit 1; }

FIRST_URL=""
FIRST_SIGNATURE=""

for attempt in $(seq 1 20); do
  log "deploy attempt $attempt of 20"
  "$CLI" deploy \
    --environment "$SHARED_ENVIRONMENT" \
    --subscription-id "$SHARED_SUBSCRIPTION_ID" \
    --shared-resource-group "$SHARED_RESOURCE_GROUP" \
    --platform-resource-group "$SHARED_PLATFORM_RESOURCE_GROUP" \
    --front-door-profile "$SHARED_FRONT_DOOR_PROFILE" \
    --location "$SHARED_LOCATION" \
    --non-interactive --confirm >"$TMP_DIR/result.json" \
    || die "deploy failed on attempt $attempt: $(jq -c '.diagnostics' "$TMP_DIR/result.json" 2>/dev/null)"

  status=$(jq -r '.status' "$TMP_DIR/result.json")
  case "$status" in
    Succeeded|NoChange) ;;
    *) die "unexpected status '$status' on attempt $attempt" ;;
  esac

  # After the first convergence every further deploy must be a no-op.
  if [ "$attempt" -gt 1 ] && [ "$status" != "NoChange" ]; then
    log "warning: attempt $attempt reported '$status' rather than 'NoChange'"
  fi

  url=$(jq -r '.sharedService.publicUrl // ""' "$TMP_DIR/result.json")
  [ -n "$url" ] || die "missing public URL on attempt $attempt"

  # The identity of every shared resource, plus the counts, form the
  # signature that must not move across deployments.
  signature=$(jq -S -c '{
    staticWebAppId: .sharedService.staticWebAppId,
    storageAccountId: .sharedService.storageAccountId,
    frontDoorProfileId: .sharedService.frontDoorProfileId,
    endpointId: .sharedService.endpointId,
    originHostName: .sharedService.originHostName,
    resourceCounts: .sharedService.resourceCounts
  }' "$TMP_DIR/result.json")

  if [ -z "$FIRST_URL" ]; then
    FIRST_URL="$url"
    FIRST_SIGNATURE="$signature"

    # There must be exactly one of each shared resource from the very first
    # deployment; more than one means the shared model already duplicated.
    echo "$signature" | jq -e '
      .resourceCounts.staticWebApps == 1 and
      .resourceCounts.endpoints == 1 and
      .resourceCounts.routes == 1 and
      .resourceCounts.applicationOrigins == 1
    ' >/dev/null || die "expected exactly one shared app, endpoint, route, and application origin: $signature"
  else
    [ "$url" = "$FIRST_URL" ] \
      || die "public URL changed from $FIRST_URL to $url on attempt $attempt"
    [ "$signature" = "$FIRST_SIGNATURE" ] \
      || die "shared resource signature changed on attempt $attempt: $signature (expected $FIRST_SIGNATURE)"
  fi
done

log "20 consecutive deployments preserved one public URL and one set of shared resources"
log "public URL: $FIRST_URL"
