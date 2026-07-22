#!/bin/bash
# ============================================================================
# generate-capacity-parameters.sh - User Story 1 fixture + test (T018)
# ============================================================================
# Generates a 25-instance fixture (the Premium Front Door endpoint capacity
# limit - see research.md "Global Entry Service") using the SAME
# deterministic naming scheme as infra/platform/modules/instance-route.bicep,
# then asserts every instance produces a unique endpoint, origin-group,
# origin, and route name. This proves the naming scheme is collision-free
# at full capacity WITHOUT deploying any Azure resources.
#
# Usage:
#   generate-capacity-parameters.sh [--base-name gvt] [--environment dev] [--count 25] [--out <file>]
#
# Writes the generated fixture (JSON array) to stdout, or to --out if given.
# Exits nonzero if any name collision is detected.
#
# Bash 3.2 compatible. Requires: jq.
# ============================================================================

set -u
set -o pipefail

BASE_NAME="gvt"
ENVIRONMENT="dev"
COUNT=25
OUT_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-name) BASE_NAME="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --count) COUNT="${2:-25}"; shift 2 ;;
    --out) OUT_FILE="${2:-}"; shift 2 ;;
    *) echo "[generate-capacity-parameters] Unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "[generate-capacity-parameters] jq not found" >&2; exit 2; }

log() { echo "[generate-capacity-parameters] $*" >&2; }

# generate_instance_id <index>: deterministic ^[a-z0-9]{1,8}$ instance id,
# e.g. index 1 -> "i01", index 25 -> "i25".
generate_instance_id() {
  index="$1"
  printf 'i%02d' "$index"
}

TMP_FIXTURE="$(mktemp)"
trap 'rm -f "$TMP_FIXTURE"' EXIT

echo "[" > "$TMP_FIXTURE"
i=1
while [ "$i" -le "$COUNT" ]; do
  instance_id="$(generate_instance_id "$i")"
  endpoint_name="${BASE_NAME}-${ENVIRONMENT}-${instance_id}"
  origin_group_name="og-${instance_id}"
  origin_name="origin-${instance_id}"
  route_name="route-${instance_id}"

  entry=$(jq -n \
    --arg instanceId "$instance_id" \
    --arg endpointName "$endpoint_name" \
    --arg originGroupName "$origin_group_name" \
    --arg originName "$origin_name" \
    --arg routeName "$route_name" \
    '{instanceId: $instanceId, endpointName: $endpointName, originGroupName: $originGroupName, originName: $originName, routeName: $routeName}')

  if [ "$i" -gt 1 ]; then echo "," >> "$TMP_FIXTURE"; fi
  echo "$entry" >> "$TMP_FIXTURE"
  i=$((i + 1))
done
echo "]" >> "$TMP_FIXTURE"

FIXTURE_JSON="$(jq -c '.' "$TMP_FIXTURE")" || { log "generated fixture is not valid JSON"; exit 1; }

# ----------------------------------------------------------------------------
# Uniqueness assertions
# ----------------------------------------------------------------------------
FAILURES=0
assert_unique() {
  field="$1"
  total=$(echo "$FIXTURE_JSON" | jq "length")
  distinct=$(echo "$FIXTURE_JSON" | jq "[.[].${field}] | unique | length")
  if [ "$total" -eq "$distinct" ]; then
    log "ok: all $total '$field' values are unique"
  else
    log "FAIL: '$field' has only $distinct distinct value(s) out of $total instances"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_unique "instanceId"
assert_unique "endpointName"
assert_unique "originGroupName"
assert_unique "originName"
assert_unique "routeName"

if [ "$COUNT" -ne 25 ]; then
  log "note: generated $COUNT instances (expected capacity check uses 25; pass --count 25 explicitly for the full capacity assertion)"
fi

if [ -n "$OUT_FILE" ]; then
  echo "$FIXTURE_JSON" | jq '.' > "$OUT_FILE"
  log "fixture written to $OUT_FILE"
else
  echo "$FIXTURE_JSON" | jq '.'
fi

if [ "$FAILURES" -gt 0 ]; then
  log "capacity fixture uniqueness check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "capacity fixture uniqueness check passed ($COUNT instances)"
exit 0
