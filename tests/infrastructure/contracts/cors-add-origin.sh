#!/bin/bash
# Contract test for scripts/cors-add-origin.sh. Azure CLI is mocked; no Azure
# mutation is performed.
# Bash 3.2 compatible. Requires: jq.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/cors-add-origin.sh"
TMP_DIR="$(mktemp -d)"
MOCK_BIN="$TMP_DIR/bin"
AZ_CALLS="$TMP_DIR/az-calls.log"
mkdir -p "$MOCK_BIN"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILURES=0
log() { echo "[cors-add-origin] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

command -v jq >/dev/null 2>&1 || { log "jq not found"; exit 2; }
[ -x "$CLI" ] || { log "script not executable: $CLI"; exit 2; }

cat >"$MOCK_BIN/az" <<'EOF'
#!/bin/bash
set -u
set -o pipefail

command_name="${1:-}"
shift || true
case "$command_name" in
  account)
    case "${1:-}" in
      show|set) exit 0 ;;
    esac
    ;;
  storage)
    case "${1:-}" in
      account)
        case "${2:-}" in
          keys)
            echo "mock-account-key"
            exit 0
            ;;
        esac
        ;;
      cors)
        case "${2:-}" in
          list)
            printf '%s\n' "${MOCK_CORS_RESPONSE:-[]}"
            exit 0
            ;;
          add)
            printf '%s\n' "$*" >>"$MOCK_AZ_CALLS"
            exit 0
            ;;
        esac
        ;;
    esac
    ;;
esac
echo "unexpected mocked az invocation: $command_name $*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/az"

run_case() {
  label="$1"
  response="$2"
  origin="$3"
  expected_adds="$4"
  : >"$AZ_CALLS"

  if MOCK_CORS_RESPONSE="$response" MOCK_AZ_CALLS="$AZ_CALLS" PATH="$MOCK_BIN:$PATH" \
    "$CLI" --storage-account-name mockstorage --resource-group mock-rg \
    --subscription-id mock-sub --origin "$origin" \
    >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    status=0
  else
    status=$?
  fi

  if [ "$status" -ne 0 ]; then
    fail "$label: helper exited $status: $(cat "$TMP_DIR/stderr")"
    return
  fi

  actual_adds=$(wc -l <"$AZ_CALLS" | tr -d ' ')
  if [ "$actual_adds" -eq "$expected_adds" ]; then
    pass "$label: expected $expected_adds CORS mutation(s)"
  else
    fail "$label: expected $expected_adds CORS mutation(s), found $actual_adds"
  fi
}

# Azure CLI has emitted both camel-case and legacy Pascal-case property names.
run_case "legacy existing origin" \
  '[{"AllowedOrigins":["https://app.example.com"]}]' \
  "https://app.example.com" 0
run_case "modern existing origin" \
  '[{"allowedOrigins":["https://app.example.com"]}]' \
  "https://app.example.com" 0
run_case "legacy missing origin" \
  '[{"AllowedOrigins":["https://other.example.com"]}]' \
  "https://app.example.com" 1
run_case "modern missing origin" \
  '[{"allowedOrigins":["https://other.example.com"]}]' \
  "https://app.example.com" 1

# The helper must not issue two mutations when the same origin is requested
# more than once in a single invocation.
run_duplicate_case() {
  label="$1"
  response="$2"
  origin="$3"
  expected_adds="$4"
  : >"$AZ_CALLS"

  if MOCK_CORS_RESPONSE="$response" MOCK_AZ_CALLS="$AZ_CALLS" PATH="$MOCK_BIN:$PATH" \
    "$CLI" --storage-account-name mockstorage --resource-group mock-rg \
    --subscription-id mock-sub --origin "$origin" --origin "$origin" \
    >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
    status=0
  else
    status=$?
  fi

  if [ "$status" -ne 0 ]; then
    fail "$label: helper exited $status: $(cat "$TMP_DIR/stderr")"
    return
  fi

  actual_adds=$(wc -l <"$AZ_CALLS" | tr -d ' ')
  if [ "$actual_adds" -eq "$expected_adds" ]; then
    pass "$label: expected $expected_adds CORS mutation(s)"
  else
    fail "$label: expected $expected_adds CORS mutation(s), found $actual_adds"
  fi
}

run_duplicate_case "duplicate requested origin" \
  '[{"allowedOrigins":["https://other.example.com"]}]' \
  "https://app.example.com" 1
run_case "modern wildcard origin" \
  '[{"allowedOrigins":["*"]}]' \
  "https://app.example.com" 0

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES contract test(s) failed"
  exit 1
fi
log "all contract tests passed"
