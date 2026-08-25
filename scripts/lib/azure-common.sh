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

# normalize_logical_instance_id <raw-id>: trims surrounding whitespace,
# lowercases, validates, and echoes the normalized logical-instance
# identifier. Normalization happens BEFORE validation and before any
# conflict detection or persistent write, so that identifiers differing only
# by case or padding can never become two distinct logical instances
# (see specs/003-shared-entry-scale/contracts/logical-instance-cli.md).
#
# Rules: 3-32 characters matching ^[a-z0-9][a-z0-9-]*[a-z0-9]$
#
# Exit codes:
#   0 - valid; normalized id on stdout
#   3 - empty input
#   4 - invalid length
#   5 - invalid characters or invalid leading/trailing hyphen
normalize_logical_instance_id() {
  local raw="${1:-}"
  local trimmed
  local normalized
  local length

  # Trim leading and trailing whitespace without relying on Bash 4 features.
  trimmed="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$trimmed" ]; then
    return 3
  fi

  normalized="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"

  length=${#normalized}
  if [ "$length" -lt 3 ] || [ "$length" -gt 32 ]; then
    return 4
  fi

  # LC_ALL=C is exported above, so these bracket expressions are byte-wise.
  case "$normalized" in
    [a-z0-9]*[a-z0-9]) ;;
    *) return 5 ;;
  esac
  case "$normalized" in
    *[!a-z0-9-]*) return 5 ;;
  esac

  printf '%s\n' "$normalized"
  return 0
}

# ----------------------------------------------------------------------------
# Shared resource inventory (constant-resource evidence)
# ----------------------------------------------------------------------------

# capture_shared_inventory <subscription-id> <shared-rg> <platform-rg> <front-door-profile>
# Emits a deterministic JSON document of shared resource counts and sorted
# resource IDs. This is the evidence used to prove that adding logical
# instances does not grow infrastructure (FR-018 / SC-001), so its output must
# be stable across invocations: every ID list is sorted and no timestamp,
# operation ID, or other volatile field is included.
capture_shared_inventory() {
  local subscription_id="$1"
  local shared_rg="$2"
  local platform_rg="$3"
  local profile_name="$4"

  require_cmd az
  require_cmd jq

  local static_web_apps
  local storage_accounts
  local endpoints
  local origin_groups
  local routes
  local origins
  local origin_group_name

  static_web_apps=$(az staticwebapp list \
    --resource-group "$shared_rg" \
    --subscription "$subscription_id" \
    --query "[].id" -o json 2>/dev/null || echo '[]')

  storage_accounts=$(az storage account list \
    --resource-group "$shared_rg" \
    --subscription "$subscription_id" \
    --query "[].id" -o json 2>/dev/null || echo '[]')

  endpoints=$(az afd endpoint list \
    --resource-group "$platform_rg" \
    --profile-name "$profile_name" \
    --subscription "$subscription_id" \
    --query "[].id" -o json 2>/dev/null || echo '[]')

  origin_groups=$(az afd origin-group list \
    --resource-group "$platform_rg" \
    --profile-name "$profile_name" \
    --subscription "$subscription_id" \
    --query "[].id" -o json 2>/dev/null || echo '[]')

  routes='[]'
  for endpoint_name in $(echo "$endpoints" | jq -r '.[] | split("/") | last'); do
    endpoint_routes=$(az afd route list \
      --resource-group "$platform_rg" \
      --profile-name "$profile_name" \
      --endpoint-name "$endpoint_name" \
      --subscription "$subscription_id" \
      --query "[].id" -o json 2>/dev/null || echo '[]')
    routes=$(jq -n --argjson a "$routes" --argjson b "$endpoint_routes" '$a + $b')
  done

  origins='[]'
  for origin_group_name in $(echo "$origin_groups" | jq -r '.[] | split("/") | last'); do
    group_origins=$(az afd origin list \
      --resource-group "$platform_rg" \
      --profile-name "$profile_name" \
      --origin-group-name "$origin_group_name" \
      --subscription "$subscription_id" \
      --query "[].id" -o json 2>/dev/null || echo '[]')
    origins=$(jq -n --argjson a "$origins" --argjson b "$group_origins" '$a + $b')
  done

  jq -n \
    --argjson staticWebApps "$static_web_apps" \
    --argjson storageAccounts "$storage_accounts" \
    --argjson endpoints "$endpoints" \
    --argjson originGroups "$origin_groups" \
    --argjson routes "$routes" \
    --argjson origins "$origins" \
    '{
      staticWebApps: ($staticWebApps | sort),
      storageAccounts: ($storageAccounts | sort),
      endpoints: ($endpoints | sort),
      originGroups: ($originGroups | sort),
      routes: ($routes | sort),
      origins: ($origins | sort),
      counts: {
        staticWebApps: ($staticWebApps | length),
        storageAccounts: ($storageAccounts | length),
        endpoints: ($endpoints | length),
        originGroups: ($originGroups | length),
        routes: ($routes | length),
        origins: ($origins | length)
      }
    }'
}

# compare_shared_inventory <before-file> <after-file>
# Returns 0 when the two inventory documents are exactly equal, 1 otherwise.
# On difference, a human-readable summary is written to stderr. Equality is
# strict: a single added endpoint, route, origin, or application is a failure,
# because the whole point of the shared model is that these counts never move
# when logical instances are added.
compare_shared_inventory() {
  local before_file="$1"
  local after_file="$2"

  require_cmd jq

  if [ ! -f "$before_file" ]; then
    log_error "inventory comparison failed: missing before snapshot: $before_file"
    return 1
  fi
  if [ ! -f "$after_file" ]; then
    log_error "inventory comparison failed: missing after snapshot: $after_file"
    return 1
  fi

  if jq -e -n \
    --slurpfile before "$before_file" \
    --slurpfile after "$after_file" \
    '$before[0] == $after[0]' >/dev/null 2>&1; then
    return 0
  fi

  log_error "shared resource inventory changed; constant-resource invariant violated"
  jq -n \
    --slurpfile before "$before_file" \
    --slurpfile after "$after_file" \
    '{before: $before[0].counts, after: $after[0].counts}' >&2 2>/dev/null || true
  return 1
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
