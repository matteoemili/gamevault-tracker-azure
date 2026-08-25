#!/bin/bash
# ============================================================================
# logical-instance.sh - Logical instance lifecycle CLI
# ============================================================================
# Bash 3.2 compatible. Emits exactly one JSON document on stdout for every
# handled lifecycle action; human progress and diagnostics go to stderr.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=scripts/lib/azure-common.sh
. "$SCRIPT_DIR/lib/azure-common.sh"

DATA_KEY="logicalInstance"
DEFAULT_TABLE_NAME="logicalinstances"

usage() {
  cat >&2 <<'USAGE'
Usage: logical-instance.sh <create|show|list|retire> [options]
  --environment <dev|staging|prod>
  --subscription-id <uuid>
  --storage-account-name <name>
  --table-name <name>              (default: logicalinstances)
  --logical-instance-id <id>       (create/show/retire)
  --display-name <name>            (create)
  --state <Reserved|Retired>       (list only)
  --confirm                        (retire only)
  --non-interactive                (informational)

Logical instances are Table Storage records only; lifecycle actions do not
provision shared application or routing resources.
USAGE
}

action_label() {
  case "$1" in
    create) echo "create" ;;
    show) echo "show" ;;
    list) echo "list" ;;
    retire) echo "retire" ;;
    *) echo "create" ;;
  esac
}

utc_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

fail() {
  fail_fast "$DATA_KEY" "$(action_label "$ACTION")" "$OP_ID" "$1" "$2"
}

json_escape() {
  jq -R -s '.[0:length-1]'
}

entity_to_record() {
  jq -c --arg environment "$ENVIRONMENT" '
    {
      id: (.RowKey // .rowKey // ""),
      displayName: (.displayName // ""),
      dataNamespace: (.dataNamespace // (.RowKey // .rowKey // "")),
      environment: (.environment // $environment),
      state: (.state // "Reserved"),
      createdAt: (.createdAt // ""),
      createdBy: (.createdBy // ""),
      updatedAt: (.updatedAt // .createdAt // ""),
      retiredAt: (if has("retiredAt") then .retiredAt else null end),
      metadataVersion: ((.metadataVersion // 1) | tonumber)
    }'
}

read_entity() {
  entity_id="$1"
  az storage entity show \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --table-name "$TABLE_NAME" \
    --partition-key instance \
    --row-key "$entity_id" \
    --auth-mode login \
    -o json 2>"$SCRATCH_DIR/az-show.err"
}

current_principal() {
  principal=$(az account show --query user.name -o tsv 2>/dev/null || true)
  if [ -z "$principal" ] || [ "$principal" = "None" ]; then
    principal="azure-cli-identity"
  fi
  printf '%s\n' "$principal"
}

require_az_ready() {
  command -v az >/dev/null 2>&1 || fail "AZURE_CLI_NOT_FOUND" "required command not found: az"
  if ! az account show >/dev/null 2>&1; then
    fail "AZURE_LOGIN_REQUIRED" "not logged in to Azure; run 'az login' first"
  fi
  if ! az account set --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
    fail "SUBSCRIPTION_SELECT_FAILED" "unable to select subscription: $SUBSCRIPTION_ID"
  fi
}

emit_record() {
  status="$1"
  record_json="$2"
  diagnostics_json="${3:-[]}"
  emit_json_envelope "$DATA_KEY" "$(action_label "$ACTION")" "$status" "$OP_ID" "$record_json" "$diagnostics_json"
}

validate_common() {
  [ -n "$ENVIRONMENT" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --environment"
  case "$ENVIRONMENT" in
    dev|staging|prod) ;;
    *) fail "INVALID_ENVIRONMENT" "environment must be one of: dev, staging, prod" ;;
  esac
  [ -n "$SUBSCRIPTION_ID" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --subscription-id"
  [ -n "$STORAGE_ACCOUNT_NAME" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --storage-account-name"
  [ -n "$TABLE_NAME" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --table-name"
}

normalize_id_or_fail() {
  raw_id="$1"
  NORMALIZED_ID=$(normalize_logical_instance_id "$raw_id")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$rc" in
      3) fail "INVALID_LOGICAL_INSTANCE_ID" "logical instance id is required" ;;
      4) fail "INVALID_LOGICAL_INSTANCE_ID" "logical instance id must be 3-32 characters" ;;
      *) fail "INVALID_LOGICAL_INSTANCE_ID" "logical instance id must match ^[a-z0-9][a-z0-9-]*[a-z0-9]$ after lower-case normalization" ;;
    esac
  fi
}

create_entity_json() {
  created_at="$1"
  created_by="$2"
  jq -n \
    --arg id "$NORMALIZED_ID" \
    --arg displayName "$DISPLAY_NAME" \
    --arg environment "$ENVIRONMENT" \
    --arg createdAt "$created_at" \
    --arg createdBy "$created_by" \
    '{
      id: $id,
      displayName: $displayName,
      dataNamespace: $id,
      environment: $environment,
      state: "Reserved",
      createdAt: $createdAt,
      createdBy: $createdBy,
      updatedAt: $createdAt,
      retiredAt: null,
      metadataVersion: 1
    }'
}

is_equivalent_create() {
  existing_json="$1"
  echo "$existing_json" | jq -e \
    --arg displayName "$DISPLAY_NAME" \
    --arg environment "$ENVIRONMENT" \
    --arg id "$NORMALIZED_ID" \
    '(.displayName == $displayName) and
     (.dataNamespace == $id) and
     (.environment == $environment) and
     (.state == "Reserved") and
     ((.metadataVersion | tonumber) == 1)' >/dev/null 2>&1
}

cmd_create() {
  [ -n "$LOGICAL_INSTANCE_ID" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --logical-instance-id"
  [ -n "$DISPLAY_NAME" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --display-name"
  name_len=${#DISPLAY_NAME}
  if [ "$name_len" -lt 1 ] || [ "$name_len" -gt 100 ]; then
    fail "INVALID_DISPLAY_NAME" "display name must be 1-100 characters"
  fi
  normalize_id_or_fail "$LOGICAL_INSTANCE_ID"
  OP_ID="$(operation_id logical-instance "$NORMALIZED_ID")"
  require_az_ready

  now="$(utc_timestamp)"
  creator="$(current_principal)"
  expected_record="$(create_entity_json "$now" "$creator")"

  log_info "Reserving logical instance '$NORMALIZED_ID' in table '$TABLE_NAME'"
  if az storage entity insert \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --table-name "$TABLE_NAME" \
    --auth-mode login \
    --if-exists fail \
    --entity \
      PartitionKey=instance \
      RowKey="$NORMALIZED_ID" \
      displayName="$DISPLAY_NAME" \
      dataNamespace="$NORMALIZED_ID" \
      environment="$ENVIRONMENT" \
      state=Reserved \
      createdAt="$now" \
      createdBy="$creator" \
      updatedAt="$now" \
      metadataVersion=1 \
    >"$SCRATCH_DIR/create.out" 2>"$SCRATCH_DIR/create.err"; then
    emit_record "Succeeded" "$expected_record"
    return 0
  fi

  if ! existing_entity="$(read_entity "$NORMALIZED_ID")"; then
    err="$(mask_secrets < "$SCRATCH_DIR/create.err")"
    fail "TABLE_INSERT_FAILED" "failed to reserve logical instance: $err"
  fi

  existing_record="$(echo "$existing_entity" | entity_to_record)"
  existing_state="$(echo "$existing_record" | jq -r '.state')"
  if [ "$existing_state" = "Retired" ]; then
    emit_record "Failed" "$existing_record" "$(diagnostic_array INSTANCE_RETIRED "logical instance '$NORMALIZED_ID' is retired and remains reserved")"
    exit 1
  fi
  if is_equivalent_create "$existing_record"; then
    emit_record "NoChange" "$existing_record"
    return 0
  fi
  emit_record "Failed" "$existing_record" "$(diagnostic_array INSTANCE_CONFLICT "logical instance '$NORMALIZED_ID' already exists with incompatible immutable values")"
  exit 1
}

cmd_show() {
  [ -n "$LOGICAL_INSTANCE_ID" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --logical-instance-id"
  normalize_id_or_fail "$LOGICAL_INSTANCE_ID"
  OP_ID="$(operation_id logical-instance "$NORMALIZED_ID")"
  require_az_ready

  if ! entity="$(read_entity "$NORMALIZED_ID")"; then
    emit_record "Failed" "null" "$(diagnostic_array INSTANCE_NOT_FOUND "logical instance '$NORMALIZED_ID' was not found")"
    exit 1
  fi
  record="$(echo "$entity" | entity_to_record)"
  emit_record "Succeeded" "$record"
}

query_page() {
  filter="$1"
  shift
  az storage entity query \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --table-name "$TABLE_NAME" \
    --auth-mode login \
    --filter "$filter" \
    "$@" \
    -o json 2>"$SCRATCH_DIR/list.err"
}

cmd_list() {
  if [ -n "$STATE_FILTER" ]; then
    case "$STATE_FILTER" in
      Reserved|Retired) ;;
      *) fail "INVALID_STATE" "state must be one of: Reserved, Retired" ;;
    esac
  fi
  require_az_ready

  filter="PartitionKey eq 'instance'"
  if [ -n "$STATE_FILTER" ]; then
    filter="$filter and state eq '$STATE_FILTER'"
  fi

  all_items='[]'
  marker_args_set=0
  next_pk=""
  next_rk=""
  page_count=0
  max_pages=10000
  while :; do
    if [ "$marker_args_set" -eq 1 ]; then
      page="$(query_page "$filter" --marker "nextpartitionkey=$next_pk" "nextrowkey=$next_rk")" || fail "TABLE_QUERY_FAILED" "failed to list logical instances: $(mask_secrets < "$SCRATCH_DIR/list.err")"
    else
      page="$(query_page "$filter")" || fail "TABLE_QUERY_FAILED" "failed to list logical instances: $(mask_secrets < "$SCRATCH_DIR/list.err")"
    fi
    page_count=$((page_count + 1))
    items="$(echo "$page" | jq -c '.items // .value // []')"
    all_items="$(jq -n -c --argjson a "$all_items" --argjson b "$items" '$a + $b')"
    marker_present="$(echo "$page" | jq -r 'if ((.nextMarker? | type) == "object") or ((.next_marker? | type) == "object") then "1" else "0" end')"
    parsed_pk="$(echo "$page" | jq -r '[
      .nextMarker.nextpartitionkey?,
      .nextMarker.nextPartitionKey?,
      .nextMarker.NextPartitionKey?,
      .next_marker.nextpartitionkey?,
      .next_marker.nextPartitionKey?,
      .next_marker.NextPartitionKey?,
      .nextpartitionkey?,
      .nextPartitionKey?,
      .NextPartitionKey?
    ] | map(select(type == "string" and length > 0)) | .[0] // empty')"
    parsed_rk="$(echo "$page" | jq -r '[
      .nextMarker.nextrowkey?,
      .nextMarker.nextRowKey?,
      .nextMarker.NextRowKey?,
      .next_marker.nextrowkey?,
      .next_marker.nextRowKey?,
      .next_marker.NextRowKey?,
      .nextrowkey?,
      .nextRowKey?,
      .NextRowKey?
    ] | map(select(type == "string" and length > 0)) | .[0] // empty')"
    if [ -z "$parsed_pk" ] && [ -z "$parsed_rk" ]; then
      if [ "$marker_present" -eq 1 ]; then
        fail "TABLE_PAGINATION_FAILED" "Azure Table query returned a continuation marker, but no usable nextpartitionkey/nextrowkey values could be parsed"
      fi
      break
    fi
    if [ -z "$parsed_pk" ] || [ -z "$parsed_rk" ]; then
      fail "TABLE_PAGINATION_FAILED" "Azure Table query returned an incomplete continuation marker; expected both nextpartitionkey and nextrowkey"
    fi
    if [ "$marker_args_set" -eq 1 ] && [ "$parsed_pk" = "$next_pk" ] && [ "$parsed_rk" = "$next_rk" ]; then
      fail "TABLE_PAGINATION_FAILED" "Azure Table query continuation marker did not advance"
    fi
    if [ "$page_count" -ge "$max_pages" ]; then
      fail "TABLE_PAGINATION_FAILED" "Azure Table query exceeded maximum pagination depth ($max_pages pages)"
    fi
    next_pk="$parsed_pk"
    next_rk="$parsed_rk"
    marker_args_set=1
  done

  records="$(echo "$all_items" | jq -c --arg environment "$ENVIRONMENT" '[.[] | {
    id: (.RowKey // .rowKey // ""),
    displayName: (.displayName // ""),
    dataNamespace: (.dataNamespace // (.RowKey // .rowKey // "")),
    environment: (.environment // $environment),
    state: (.state // "Reserved"),
    createdAt: (.createdAt // ""),
    createdBy: (.createdBy // ""),
    updatedAt: (.updatedAt // .createdAt // ""),
    retiredAt: (if has("retiredAt") then .retiredAt else null end),
    metadataVersion: ((.metadataVersion // 1) | tonumber)
  }] | sort_by(.id)')"
  emit_record "Succeeded" "$records"
}

cmd_retire() {
  [ "$CONFIRM" -eq 1 ] || fail "CONFIRMATION_REQUIRED" "retire requires --confirm"
  [ -n "$LOGICAL_INSTANCE_ID" ] || fail "MISSING_REQUIRED_OPTION" "missing value for required option: --logical-instance-id"
  normalize_id_or_fail "$LOGICAL_INSTANCE_ID"
  OP_ID="$(operation_id logical-instance "$NORMALIZED_ID")"
  require_az_ready

  if ! entity="$(read_entity "$NORMALIZED_ID")"; then
    emit_record "Failed" "null" "$(diagnostic_array INSTANCE_NOT_FOUND "logical instance '$NORMALIZED_ID' was not found")"
    exit 1
  fi
  record="$(echo "$entity" | entity_to_record)"
  state="$(echo "$record" | jq -r '.state')"
  if [ "$state" = "Retired" ]; then
    emit_record "NoChange" "$record"
    return 0
  fi

  now="$(utc_timestamp)"
  log_info "Retiring logical instance '$NORMALIZED_ID'"
  if ! az storage entity merge \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --table-name "$TABLE_NAME" \
    --auth-mode login \
    --if-match '*' \
    --entity \
      PartitionKey=instance \
      RowKey="$NORMALIZED_ID" \
      state=Retired \
      updatedAt="$now" \
      retiredAt="$now" \
    >"$SCRATCH_DIR/retire.out" 2>"$SCRATCH_DIR/retire.err"; then
    fail "TABLE_UPDATE_FAILED" "failed to retire logical instance: $(mask_secrets < "$SCRATCH_DIR/retire.err")"
  fi

  if entity="$(read_entity "$NORMALIZED_ID")"; then
    record="$(echo "$entity" | entity_to_record)"
  else
    record="$(echo "$record" | jq -c --arg now "$now" '.state="Retired" | .updatedAt=$now | .retiredAt=$now')"
  fi
  emit_record "Succeeded" "$record"
}

ACTION="${1:-}"
if [ -z "$ACTION" ]; then
  usage
  exit 2
fi
shift || true

case "$ACTION" in
  create|show|list|retire) ;;
  *)
    OP_ID="$(operation_id logical-instance unknown)"
    usage
    fail_fast "$DATA_KEY" "create" "$OP_ID" "UNKNOWN_ACTION" "Unknown action: $ACTION"
    ;;
esac

ENVIRONMENT=""
SUBSCRIPTION_ID=""
STORAGE_ACCOUNT_NAME=""
TABLE_NAME="$DEFAULT_TABLE_NAME"
LOGICAL_INSTANCE_ID=""
DISPLAY_NAME=""
STATE_FILTER=""
CONFIRM=0
NON_INTERACTIVE=0
NORMALIZED_ID=""
OP_ID="$(operation_id logical-instance unknown)"
SCRATCH_DIR="$PROJECT_ROOT/.scratch/logical-instance.$$"
mkdir -p "$SCRATCH_DIR" || { echo "[ERROR] unable to create scratch directory" >&2; exit 1; }
trap 'rm -rf "$SCRATCH_DIR"' EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="${2:-}"; shift 2 ;;
    --storage-account-name) STORAGE_ACCOUNT_NAME="${2:-}"; shift 2 ;;
    --table-name) TABLE_NAME="${2:-}"; shift 2 ;;
    --logical-instance-id) LOGICAL_INSTANCE_ID="${2:-}"; shift 2 ;;
    --display-name) DISPLAY_NAME="${2:-}"; shift 2 ;;
    --state) STATE_FILTER="${2:-}"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    *) usage; fail "UNKNOWN_OPTION" "Unknown option: $1" ;;
  esac
done

: "$NON_INTERACTIVE"

OP_ID="$(operation_id logical-instance "${ENVIRONMENT:-unknown}")"
validate_common

case "$ACTION" in
  create) cmd_create ;;
  show) cmd_show ;;
  list) cmd_list ;;
  retire) cmd_retire ;;
esac
