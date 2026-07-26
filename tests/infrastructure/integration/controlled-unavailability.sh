#!/bin/bash
# ============================================================================
# controlled-unavailability.sh - User Story 1 integration test (T017)
# ============================================================================
# Verifies that when an instance's application origin is unhealthy /
# unreachable, its Front Door endpoint returns EITHER:
#   (a) Front Door's own native error response (e.g. 503), or
#   (b) the shared generic maintenance placeholder page,
# and NEVER another instance's marker/content (no cross-instance failover;
# see research.md "Controlled Unavailability" and spec.md assumptions).
#
# Usage:
#   controlled-unavailability.sh --url https://<endpoint>.z01.azurefd.net \
#     --foreign-marker "OTHER_INSTANCE_MARKER" \
#     [--maintenance-marker "This instance is temporarily unavailable"]
#
# Run this against an instance whose Static Web App origin has been made
# unreachable (e.g. temporarily stopped) as part of a failure-simulation
# step - see tests/infrastructure/integration/README.md.
#
# Bash 3.2 compatible. Requires: curl.
# ============================================================================

set -u
set -o pipefail

FAILURES=0
log() { echo "[controlled-unavailability] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

URL=""
FOREIGN_MARKER=""
MAINTENANCE_MARKER="This instance is temporarily unavailable"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --foreign-marker) FOREIGN_MARKER="${2:-}"; shift 2 ;;
    --maintenance-marker) MAINTENANCE_MARKER="${2:-}"; shift 2 ;;
    *) log "Unknown option: $1"; exit 2 ;;
  esac
done

if [ -z "$URL" ] || [ -z "$FOREIGN_MARKER" ]; then
  log "Usage: $0 --url <url> --foreign-marker <text> [--maintenance-marker <text>]"
  exit 2
fi

command -v curl >/dev/null 2>&1 || { log "curl not found"; exit 2; }

status=$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null)
body=$(curl -s "$URL" 2>/dev/null)

if echo "$body" | grep -qF "$FOREIGN_MARKER"; then
  fail "unhealthy instance returned ANOTHER instance's marker - this indicates unintended cross-instance failover, which is explicitly out of scope"
else
  pass "response does not contain another instance's marker"
fi

case "$status" in
  5*)
    pass "received a native Front Door / origin error status ($status), acceptable when the maintenance origin is not enabled"
    ;;
  2*)
    if echo "$body" | grep -qF "$MAINTENANCE_MARKER"; then
      pass "received the shared generic maintenance placeholder page (status $status)"
    else
      fail "received a 2xx response but it did not contain the expected generic maintenance marker: '$MAINTENANCE_MARKER'"
    fi
    ;;
  *)
    fail "unexpected status code from an unhealthy instance: $status (expected a 5xx Front Door/origin error or a 2xx maintenance page)"
    ;;
esac

if [ "$FAILURES" -gt 0 ]; then
  log "controlled unavailability check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "controlled unavailability check passed"
exit 0
