#!/bin/bash
# ============================================================================
# routing-isolation.sh - User Story 1 integration test (T016)
# ============================================================================
# Verifies, against TWO LIVE deployed instances, that each Front Door
# endpoint reaches only its own instance:
#   1. Each endpoint's response contains that instance's expected marker.
#   2. Neither endpoint's response ever contains the OTHER instance's
#      marker (isolation).
#   3. Repeating each request several times never flips which marker is
#      returned (no cross-instance leakage from caching, session affinity,
#      or origin-group misconfiguration).
#
# Usage:
#   routing-isolation.sh \
#     --url-a https://<endpoint-a>.z01.azurefd.net --marker-a "INSTANCE_A_MARKER" \
#     --url-b https://<endpoint-b>.z01.azurefd.net --marker-b "INSTANCE_B_MARKER" \
#     [--repeat 5]
#
# The marker strings should be unique, distinguishing content deployed to
# each instance's Static Web App (e.g. a build-time instance identifier
# rendered somewhere in the page). See
# tests/infrastructure/integration/README.md for the full two-instance
# walkthrough.
#
# Bash 3.2 compatible. Requires: curl.
# ============================================================================

set -u
set -o pipefail

FAILURES=0
log() { echo "[routing-isolation] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

URL_A=""
URL_B=""
MARKER_A=""
MARKER_B=""
REPEAT=5

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url-a) URL_A="${2:-}"; shift 2 ;;
    --url-b) URL_B="${2:-}"; shift 2 ;;
    --marker-a) MARKER_A="${2:-}"; shift 2 ;;
    --marker-b) MARKER_B="${2:-}"; shift 2 ;;
    --repeat) REPEAT="${2:-5}"; shift 2 ;;
    *) log "Unknown option: $1"; exit 2 ;;
  esac
done

if [ -z "$URL_A" ] || [ -z "$URL_B" ] || [ -z "$MARKER_A" ] || [ -z "$MARKER_B" ]; then
  log "Usage: $0 --url-a <url> --marker-a <text> --url-b <url> --marker-b <text> [--repeat N]"
  exit 2
fi

command -v curl >/dev/null 2>&1 || { log "curl not found"; exit 2; }

check_instance() {
  label="$1"; url="$2"; own_marker="$3"; foreign_marker="$4"

  i=1
  while [ "$i" -le "$REPEAT" ]; do
    body=$(curl -s "$url" 2>/dev/null)

    if echo "$body" | grep -qF "$own_marker"; then
      : # ok, contains its own marker
    else
      fail "$label request #$i to $url did not contain its own marker '$own_marker'"
    fi

    if echo "$body" | grep -qF "$foreign_marker"; then
      fail "$label request #$i to $url unexpectedly contained the OTHER instance's marker '$foreign_marker' - cross-instance leakage"
    fi

    i=$((i + 1))
  done
  pass "$label: $REPEAT repeated request(s) consistently isolated"
}

check_instance "instance A" "$URL_A" "$MARKER_A" "$MARKER_B"
check_instance "instance B" "$URL_B" "$MARKER_B" "$MARKER_A"

if [ "$FAILURES" -gt 0 ]; then
  log "routing isolation check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "routing isolation check passed"
exit 0
