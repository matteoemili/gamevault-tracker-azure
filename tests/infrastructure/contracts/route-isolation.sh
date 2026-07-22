#!/bin/bash
# ============================================================================
# route-isolation.sh - Static isolation assertions for User Story 1 (T014)
# ============================================================================
# Verifies, WITHOUT deploying anything, that infra/platform/modules/instance-route.bicep
# is structurally wired so that:
#   1. The route's originGroup.id reference targets the SAME origin group
#      variable used to parent this module's own origins (never a foreign
#      or hardcoded origin group).
#   2. Exactly one unconditional application origin exists in the group.
#   3. Any additional origin (the shared maintenance origin) is strictly
#      conditional - it can never silently become a second permanent app
#      origin.
#   4. No resource name embeds a hardcoded/foreign instance identifier -
#      every per-instance name is derived from variables/parameters, never
#      a literal like "og-a1" baked into the template.
#
# See data-model.md "Instance Route" isolation invariant.
# Bash 3.2 compatible. Requires: az, jq.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MODULE_FILE="$PROJECT_ROOT/infra/platform/modules/instance-route.bicep"

FAILURES=0
log() { echo "[route-isolation] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

command -v az >/dev/null 2>&1 || { log "az CLI not found"; exit 2; }
command -v jq >/dev/null 2>&1 || { log "jq not found"; exit 2; }
[ -f "$MODULE_FILE" ] || { log "module not found: $MODULE_FILE"; exit 2; }

ARM_JSON="$(mktemp)"
trap 'rm -f "$ARM_JSON"' EXIT

if ! az bicep build --file "$MODULE_FILE" --stdout >"$ARM_JSON" 2>/dev/null; then
  fail "unable to compile $MODULE_FILE with az bicep build"
  exit 1
fi

# --- Assertion 1: route's originGroup.id references the module's own
#     originGroupName variable ---
route_origin_group_ref=$(jq -r '
  .resources[]
  | select(.type == "Microsoft.Cdn/profiles/afdEndpoints/routes")
  | .properties.originGroup.id
' "$ARM_JSON")

if echo "$route_origin_group_ref" | grep -q "variables('originGroupName')"; then
  pass "route.properties.originGroup.id references variables('originGroupName')"
else
  fail "route.properties.originGroup.id does not reference the module's own originGroupName variable: $route_origin_group_ref"
fi

# --- Assertion 2: exactly one UNCONDITIONAL origin in the group ---
unconditional_origin_count=$(jq '
  [.resources[]
   | select(.type == "Microsoft.Cdn/profiles/originGroups/origins")
   | select(.condition == null)
  ] | length
' "$ARM_JSON")

if [ "$unconditional_origin_count" -eq 1 ]; then
  pass "exactly one unconditional application origin present"
else
  fail "expected exactly 1 unconditional origin, found $unconditional_origin_count"
fi

# --- Assertion 3: every additional origin (beyond the one unconditional
#     app origin) is strictly conditional ---
total_origin_count=$(jq '
  [.resources[] | select(.type == "Microsoft.Cdn/profiles/originGroups/origins")] | length
' "$ARM_JSON")
conditional_origin_count=$(jq '
  [.resources[]
   | select(.type == "Microsoft.Cdn/profiles/originGroups/origins")
   | select(.condition != null)
  ] | length
' "$ARM_JSON")

if [ "$((unconditional_origin_count + conditional_origin_count))" -eq "$total_origin_count" ]; then
  pass "all non-primary origins ($conditional_origin_count) are conditional (fallback-only)"
else
  fail "found origins that are neither the single unconditional app origin nor conditional fallbacks"
fi

# --- Assertion 4: every origin/originGroup/route resource name is derived
#     from variables/parameters, not a hardcoded literal instance id ---
hardcoded_names=$(jq -r '
  .resources[]
  | select(.type == "Microsoft.Cdn/profiles/originGroups"
        or .type == "Microsoft.Cdn/profiles/originGroups/origins"
        or .type == "Microsoft.Cdn/profiles/afdEndpoints/routes"
        or .type == "Microsoft.Cdn/profiles/afdEndpoints")
  | .name
  | select((. | test("^\\[")) | not)
' "$ARM_JSON")

if [ -z "$hardcoded_names" ]; then
  pass "no hardcoded (non-expression) resource names found"
else
  fail "found hardcoded resource name(s), expected ARM expressions: $hardcoded_names"
fi

# ----------------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  log "route isolation check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "route isolation check passed"
exit 0
