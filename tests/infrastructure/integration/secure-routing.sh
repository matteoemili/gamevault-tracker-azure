#!/bin/bash
# ============================================================================
# secure-routing.sh - User Story 1 integration test (T015)
# ============================================================================
# Verifies, against a LIVE deployed Front Door endpoint for one instance:
#   1. Plain HTTP is redirected to HTTPS.
#   2. The HTTPS endpoint presents a trusted TLS certificate for its
#      Azure-managed hostname (no owned domain, no manual cert install).
#   3. The response is served by the correct origin (basic reachability +
#      content-type sanity check; exact origin-host-header correctness is
#      an Azure-side property validated by route-isolation.sh + the Bicep
#      module itself, not independently observable from the client).
#   4. The SPA's asset references are root-relative (so the same build can
#      be served correctly regardless of which Azure-generated hostname
#      fronts it - no owned domain assumed).
#
# Usage:
#   secure-routing.sh --url https://<endpoint>.z01.azurefd.net
#
# Requires a deployed instance (see tests/infrastructure/integration/README.md
# for the two-instance User Story 1 validation walkthrough).
# Bash 3.2 compatible. Requires: curl.
# ============================================================================

set -u
set -o pipefail

FAILURES=0
log() { echo "[secure-routing] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

URL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    *) log "Unknown option: $1"; exit 2 ;;
  esac
done

if [ -z "$URL" ]; then
  log "Usage: $0 --url https://<endpoint>.z01.azurefd.net"
  exit 2
fi

command -v curl >/dev/null 2>&1 || { log "curl not found"; exit 2; }

HOSTNAME="${URL#https://}"
HOSTNAME="${HOSTNAME#http://}"
HOSTNAME="${HOSTNAME%%/*}"
HTTP_URL="http://${HOSTNAME}/"

# --- 1. HTTP -> HTTPS redirect ---
redirect_status=$(curl -s -o /dev/null -w '%{http_code}' -L --max-redirs 0 "$HTTP_URL" 2>/dev/null)
location_header=$(curl -s -D - -o /dev/null --max-redirs 0 "$HTTP_URL" 2>/dev/null | grep -i '^location:' | tr -d '\r')

case "$redirect_status" in
  301|302|307|308)
    if echo "$location_header" | grep -qi "https://"; then
      pass "HTTP redirects to HTTPS ($redirect_status -> $location_header)"
    else
      fail "HTTP responded with a redirect ($redirect_status) but Location header is not HTTPS: $location_header"
    fi
    ;;
  *)
    fail "expected an HTTP redirect (301/302/307/308) from $HTTP_URL, got status $redirect_status"
    ;;
esac

# --- 2. TLS trust (no -k / --insecure) ---
https_status=$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null)
if [ -n "$https_status" ] && [ "$https_status" != "000" ]; then
  pass "HTTPS endpoint presents a trusted certificate (status $https_status, no --insecure needed)"
else
  fail "HTTPS request to $URL failed (curl could not establish a trusted TLS connection or reach the host)"
fi

# --- 3. Basic reachability / content-type sanity ---
content_type=$(curl -s -o /dev/null -D - "$URL" 2>/dev/null | grep -i '^content-type:' | tr -d '\r')
if echo "$content_type" | grep -qi 'text/html'; then
  pass "response content-type looks like an SPA index document: $content_type"
else
  fail "expected an HTML content-type from $URL, got: ${content_type:-<none>}"
fi

# --- 4. Root-relative asset references ---
body=$(curl -s "$URL" 2>/dev/null)
if echo "$body" | grep -Eq '(src|href)="(https?://|//)'; then
  fail "found absolute (non-root-relative) asset references; SPA assets must be root-relative so any Azure-generated hostname can serve them"
else
  pass "no absolute asset references found; assets appear root-relative"
fi

if [ "$FAILURES" -gt 0 ]; then
  log "secure routing check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "secure routing check passed"
exit 0
