#!/bin/bash
# ============================================================================
# azure-common.sh - Shared helpers for scripts/platform.sh and
# scripts/instance-route.sh
# ============================================================================
# Bash 3.2 compatible (macOS default /bin/bash): no associative arrays,
# no ${var,,}/${var^^}, no mapfile/readarray. Source this file, don't run it.
#
# Conventions enforced by these helpers (see plan.md "Deployment Safety" and
# contracts/*.md):
#   - Human-readable progress goes to stderr via log_* functions.
#   - Exactly one JSON document is written to stdout via emit_success_json /
#     emit_failure_json.
#   - Secrets are redacted from any text before it is logged.
#   - Failures cause a nonzero exit code.
# ============================================================================

# Guard against re-sourcing.
if [ -n "${AZURE_COMMON_SH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
AZURE_COMMON_SH_LOADED=1

# Force the C locale for the remainder of this process. This is required
# for correctness: under locales such as en_GB.UTF-8, POSIX bracket
# expressions like [a-z0-9] in `case`/glob patterns can match uppercase
# letters too (locale-dependent collation), which would silently weaken
# instance-ID and other pattern validation. See repo memory notes.
export LC_ALL=C

# ----------------------------------------------------------------------------
# Logging (stderr only)
# ----------------------------------------------------------------------------

log_info() {
  echo "[INFO] $*" >&2
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_success() {
  echo "[OK] $*" >&2
}

# die <message>: log an error and exit nonzero. Does NOT emit a JSON
# document - callers that need a JSON failure envelope on stdout should use
# emit_failure_json instead of (or before) calling die.
die() {
  log_error "$*"
  exit 1
}

# ----------------------------------------------------------------------------
# Prerequisite checks
# ----------------------------------------------------------------------------

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_azure_login() {
  require_cmd az
  if ! az account show >/dev/null 2>&1; then
    die "not logged in to Azure; run 'az login' first"
  fi
}

# require_subscription <subscription-id>: sets the active subscription for
# subsequent az calls in this process. No-op on failure other than dying.
require_subscription() {
  local subscription_id="$1"
  [ -n "$subscription_id" ] || die "subscription id is required"
  az account set --subscription "$subscription_id" >/dev/null 2>&1 \
    || die "unable to select subscription: $subscription_id"
}

# ----------------------------------------------------------------------------
# Secret redaction
# ----------------------------------------------------------------------------

# mask_secrets: reads stdin, writes redacted text to stdout. Masks common
# secret-bearing patterns (SAS tokens, account keys, client secrets,
# connection strings, bearer tokens) defensively before any log line or
# diagnostic message is emitted or persisted.
mask_secrets() {
  sed -E \
    -e 's/(AccountKey=)[^;&"'"'"' ]+/\1***REDACTED***/g' \
    -e 's/(sig=)[^&"'"'"' ]+/\1***REDACTED***/g' \
    -e 's/(client_secret=)[^&"'"'"' ]+/\1***REDACTED***/gi' \
    -e 's/(password=)[^&"'"'"' ]+/\1***REDACTED***/gi' \
    -e 's/(Authorization: ?Bearer )[A-Za-z0-9._~+/=-]+/\1***REDACTED***/gi' \
    -e 's/("[a-zA-Z]*[Ss]ecret"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/g' \
    -e 's/("[a-zA-Z]*[Tt]oken"[[:space:]]*:[[:space:]]*")[^"]+/\1***REDACTED***/g'
}

# ----------------------------------------------------------------------------
# Identifiers
# ----------------------------------------------------------------------------

# iso_now: current UTC timestamp formatted for operation IDs, e.g.
# 20260721T120000Z
iso_now() {
  date -u +%Y%m%dT%H%M%SZ
}

# operation_id <prefix> <scope-id>: builds a deterministic-ish operation ID,
# e.g. operation_id platform prod -> platform-prod-20260721T120000Z
operation_id() {
  local prefix="$1"
  local scope_id="$2"
  echo "${prefix}-${scope_id}-$(iso_now)"
}

# ----------------------------------------------------------------------------
# JSON envelope helpers
# ----------------------------------------------------------------------------

# emit_success_json <action> <status> <operation_id> <data_json_or_null> [diagnostics_json]
# Writes exactly one JSON document to stdout using the shared envelope shape
# {schemaVersion, action, status, operationId, <dataKey>, diagnostics}.
# dataKey is passed by the caller via emit_json_envelope; this function is a
# thin wrapper kept for readability at call sites.
emit_json_envelope() {
  local data_key="$1"
  local env_action="$2"
  local env_status="$3"
  local op_id="$4"
  local data_json="$5"
  local diagnostics_json="${6:-[]}"

  require_cmd jq
  jq -n \
    --arg action "$env_action" \
    --arg status "$env_status" \
    --arg operationId "$op_id" \
    --argjson data "$data_json" \
    --argjson diagnostics "$diagnostics_json" \
    --arg dataKey "$data_key" \
    '{
      schemaVersion: "1.0",
      action: $action,
      status: $status,
      operationId: $operationId
    } + { ($dataKey): $data } + { diagnostics: $diagnostics }'
}

# diagnostic <code> <message>: builds a single-element diagnostics JSON array.
diagnostic_array() {
  local code="$1"
  local message="$2"
  require_cmd jq
  jq -n --arg code "$code" --arg message "$message" '[{code: $code, message: $message}]'
}

# fail_fast <data_key> <action> <op_id> <code> <message>: emits a Failed
# envelope with null data and a single diagnostic, then exits 1. This is the
# standard way scripts should report usage errors and unrecoverable failures.
fail_fast() {
  local data_key="$1"
  local fail_action="$2"
  local op_id="$3"
  local code="$4"
  local message="$5"

  emit_json_envelope "$data_key" "$fail_action" "Failed" "$op_id" "null" "$(diagnostic_array "$code" "$message")"
  log_error "$message" || true
  exit 1
}

# ----------------------------------------------------------------------------
# Argument parsing helper
# ----------------------------------------------------------------------------

# require_value <flag> <value>: dies with a usage error if value is empty.
require_value() {
  local flag="$1"
  local value="${2:-}"
  if [ -z "$value" ]; then
    die "missing value for required option: $flag"
  fi
}
