#!/bin/bash
# ============================================================================
# shared-auth-cache-bypass.sh - User Story 3 integration test (T034)
# ============================================================================
# Verifies that reserved Static Web Apps authentication paths are not served
# from Front Door cache and that redirects do not leave the shared Front Door
# host. The redirect-host assertion is intentionally strict: without a custom
# domain the platform must fail loudly rather than silently accepting auth
# redirects that leave the shared entry point.
#
# Usage:
#   RUN_AZURE_INTEGRATION=1 SHARED_PUBLIC_URL=https://<shared>.azurefd.net \
#     tests/infrastructure/integration/shared-auth-cache-bypass.sh
#
# Bash 3.2 compatible. Requires: curl.
# ============================================================================

set -u
set -o pipefail

if [ "${RUN_AZURE_INTEGRATION:-}" != "1" ]; then
  echo "[shared-auth-cache-bypass] skip: set RUN_AZURE_INTEGRATION=1 to run live Azure integration checks" >&2
  exit 0
fi

FAILURES=0
log() { echo "[shared-auth-cache-bypass] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

URL="${SHARED_PUBLIC_URL:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    *) log "Unknown option: $1"; exit 2 ;;
  esac
done

[ -n "$URL" ] || { log "Usage: $0 --url https://<shared-endpoint> (or set SHARED_PUBLIC_URL)"; exit 2; }
command -v curl >/dev/null 2>&1 || { log "curl not found"; exit 2; }

HOST="${URL#https://}"
HOST="${HOST#http://}"
HOST="${HOST%%/*}"
BASE="https://${HOST}"

check_redirect_stays_shared() {
  path="$1"
  headers=$(curl -s -D - -o /dev/null --max-redirs 0 "${BASE}${path}" 2>/dev/null)
  status=$(printf '%s\n' "$headers" | awk 'tolower($0) ~ /^http\// { code=$2 } END { print code }')
  location=$(printf '%s\n' "$headers" | awk 'tolower($0) ~ /^location:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit }')

  case "$status" in
    301|302|303|307|308)
      case "$location" in
        http://"$HOST"/*|https://"$HOST"/*|/"*")
          pass "$path redirect remains on shared host ($status -> $location)"
          ;;
        "")
          fail "$path returned redirect status $status without a Location header"
          ;;
        *)
          fail "$path redirect leaves shared Front Door host '$HOST': $location"
          ;;
      esac
      ;;
    *)
      pass "$path did not redirect away from the shared host (status ${status:-unknown})"
      ;;
  esac
}

check_not_cached() {
  path="$1"
  headers=$(curl -s -D - -o /dev/null -H 'Cache-Control: no-cache' "${BASE}${path}" 2>/dev/null)
  x_cache=$(printf '%s\n' "$headers" | awk 'tolower($0) ~ /^x-cache:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit }')
  age=$(printf '%s\n' "$headers" | awk 'tolower($0) ~ /^age:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit }')
  cache_control=$(printf '%s\n' "$headers" | awk 'tolower($0) ~ /^cache-control:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit }')

  if printf '%s\n' "$x_cache" | grep -Eiq '(^|[,[:space:]])(hit|tcp_hit|remote_hit)([,[:space:]]|$)'; then
    fail "$path was served from Front Door cache (x-cache: $x_cache)"
    return
  fi
  if [ -n "$age" ] && [ "$age" != "0" ]; then
    fail "$path exposed a nonzero Age header, indicating a cached response (Age: $age)"
    return
  fi
  if printf '%s\n' "$cache_control" | grep -Eiq 'no-store|no-cache|private|max-age=0'; then
    pass "$path carries non-cacheable response headers"
  else
    pass "$path was not reported as a cache hit by Front Door"
  fi
}

check_not_cached "/.auth/me"
check_redirect_stays_shared "/.auth/me"
check_redirect_stays_shared "/.auth/login/aad"
check_redirect_stays_shared "/.auth/logout"

if [ "$FAILURES" -gt 0 ]; then
  log "shared auth cache-bypass check FAILED with $FAILURES failure(s)"
  exit 1
fi
log "shared auth cache-bypass check passed"
exit 0
