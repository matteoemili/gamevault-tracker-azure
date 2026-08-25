#!/bin/bash
# ============================================================================
# shared-controlled-unavailability.sh - User Story 3 integration test (T035)
# ============================================================================
# Run against a live shared endpoint while the shared application origin is
# intentionally unhealthy. The endpoint must return the generic maintenance
# response and must never fall back to content from a legacy instance origin.
#
# Usage:
#   RUN_AZURE_INTEGRATION=1 SHARED_PUBLIC_URL=https://<shared>.azurefd.net \
#     tests/infrastructure/integration/shared-controlled-unavailability.sh \
#       --legacy-marker "legacy-only text"
#
# Bash 3.2 compatible. Requires: curl.
# ============================================================================

set -u
set -o pipefail

if [ "${RUN_AZURE_INTEGRATION:-}" != "1" ]; then
  echo "[shared-controlled-unavailability] skip: set RUN_AZURE_INTEGRATION=1 to run live Azure integration checks" >&2
  exit 0
fi

FAILURES=0
log() { echo "[shared-controlled-unavailability] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

URL="${SHARED_PUBLIC_URL:-}"
LEGACY_MARKER="${LEGACY_MARKER:-}"
MAINTENANCE_MARKER="${MAINTENANCE_MARKER:-This instance is temporarily unavailable}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --legacy-marker|--foreign-marker) LEGACY_MARKER="${2:-}"; shift 2 ;;
    --maintenance-marker) MAINTENANCE_MARKER="${2:-}"; shift 2 ;;
    *) log "Unknown option: $1"; exit 2 ;;
  esac
done

[ -n "$URL" ] || { log "Usage: $0 --url https://<shared-endpoint> (or set SHARED_PUBLIC_URL)"; exit 2; }
command -v curl >/dev/null 2>&1 || { log "curl not found"; exit 2; }

BODY_FILE=".shared-controlled-unavailability-body.$$"
HEADERS_FILE=".shared-controlled-unavailability-headers.$$"
trap 'rm -f "$BODY_FILE" "$HEADERS_FILE"' EXIT

status=$(curl -s -D "$HEADERS_FILE" -o "$BODY_FILE" -w '%{http_code}' "$URL" 2>/dev/null)
body=$(cat "$BODY_FILE" 2>/dev/null)

if [ -n "$LEGACY_MARKER" ]; then
  if printf '%s\n' "$body" | grep -qF "$LEGACY_MARKER"; then
    fail "unhealthy shared origin returned legacy instance content"
  else
    pass "response does not contain the configured legacy marker"
  fi
else
  pass "no legacy marker configured; skipping content-marker comparison"
fi

case "$status" in
  2*)
    if printf '%s\n' "$body" | grep -qF "$MAINTENANCE_MARKER"; then
      pass "received the controlled maintenance response (status $status)"
    else
      fail "received 2xx but not the expected maintenance marker: '$MAINTENANCE_MARKER'"
    fi
    ;;
  *)
    fail "expected controlled maintenance response while shared origin is unhealthy, got HTTP $status"
    ;;
esac

if [ "$FAILURES" -gt 0 ]; then
  log "shared controlled-unavailability check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "shared controlled-unavailability check passed"
exit 0
