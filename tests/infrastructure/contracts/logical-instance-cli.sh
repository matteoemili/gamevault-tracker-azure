#!/bin/bash
# Offline contract tests for scripts/logical-instance.sh. No Azure credentials
# are required: successful data-plane calls are exercised with a local fake az.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CLI="$ROOT_DIR/scripts/logical-instance.sh"
SCHEMA="$ROOT_DIR/tests/infrastructure/contracts/logical-instance-output.schema.json"
VALIDATOR="$ROOT_DIR/tests/infrastructure/contracts/output-schema.sh"
SCRATCH_DIR="$ROOT_DIR/.scratch/logical-instance-cli.$$"
FAKE_BIN="$SCRATCH_DIR/bin"
mkdir -p "$FAKE_BIN" || exit 1
trap 'rm -rf "$SCRATCH_DIR"' EXIT

FAILURES=0
log() { echo "[logical-instance-cli] $*" >&2; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { log "ok: $*"; }

assert_single_json_document() {
  jq -e -s 'length == 1' "$1" >/dev/null 2>&1
}

assert_schema() {
  label="$1"
  file="$2"
  if assert_single_json_document "$file" && "$VALIDATOR" "$SCHEMA" "$file" >/dev/null 2>&1; then
    pass "$label: schema-valid single JSON document"
  else
    fail "$label: invalid stdout: $(cat "$file" 2>/dev/null)"
  fi
}

run_cli() {
  PATH="$FAKE_BIN:$PATH" "$CLI" "$@" >"$SCRATCH_DIR/out.json" 2>"$SCRATCH_DIR/err.log"
}

cat > "$FAKE_BIN/az" <<'FAKEAZ'
#!/bin/bash
set -u
if [ "$1" = "account" ] && [ "$2" = "show" ]; then
  if [ "${3:-}" = "--query" ]; then echo "fake-principal"; else echo '{"user":{"name":"fake-principal"}}'; fi
  exit 0
fi
if [ "$1" = "account" ] && [ "$2" = "set" ]; then exit 0; fi
if [ "$1" = "storage" ] && [ "$2" = "entity" ]; then
  cmd="$3"
  case "$cmd" in
    insert)
      row="demo-user"; display="Demo User"; env="dev"; now="2026-08-25T16:00:00Z"
      prev=""
      for arg in "$@"; do
        if [ "$prev" = "RowKey" ]; then row="$arg"; fi
        case "$arg" in
          RowKey=*) row="${arg#RowKey=}" ;;
          displayName=*) display="${arg#displayName=}" ;;
          environment=*) env="${arg#environment=}" ;;
          createdAt=*) now="${arg#createdAt=}" ;;
        esac
        prev="$arg"
      done
      printf '{"PartitionKey":"instance","RowKey":"%s","displayName":"%s","dataNamespace":"%s","environment":"%s","state":"Reserved","createdAt":"%s","createdBy":"fake-principal","updatedAt":"%s","metadataVersion":1}\n' "$row" "$display" "$row" "$env" "$now" "$now"
      ;;
    show)
      row="demo-user"; prev=""
      for arg in "$@"; do
        if [ "$prev" = "--row-key" ]; then row="$arg"; fi
        prev="$arg"
      done
      if [ "$row" = "missing-id" ]; then echo "not found" >&2; exit 3; fi
      printf '{"PartitionKey":"instance","RowKey":"%s","displayName":"Demo User","dataNamespace":"%s","environment":"dev","state":"Reserved","createdAt":"2026-08-25T16:00:00Z","createdBy":"fake-principal","updatedAt":"2026-08-25T16:00:00Z","retiredAt":null,"metadataVersion":1}\n' "$row" "$row"
      ;;
    query)
      marker_pk=""; marker_rk=""
      for arg in "$@"; do
        case "$arg" in
          nextpartitionkey=*) marker_pk="${arg#nextpartitionkey=}" ;;
          nextrowkey=*) marker_rk="${arg#nextrowkey=}" ;;
        esac
      done
      if [ -n "$marker_pk" ] || [ -n "$marker_rk" ]; then
        cat <<'JSON'
{"items":[{"PartitionKey":"instance","RowKey":"beta","displayName":"Beta","dataNamespace":"beta","environment":"dev","state":"Reserved","createdAt":"2026-08-25T16:00:00Z","createdBy":"fake-principal","updatedAt":"2026-08-25T16:00:00Z","metadataVersion":1}]}
JSON
      else
        cat <<'JSON'
{"items":[{"PartitionKey":"instance","RowKey":"zeta","displayName":"Zeta","dataNamespace":"zeta","environment":"dev","state":"Reserved","createdAt":"2026-08-25T16:00:00Z","createdBy":"fake-principal","updatedAt":"2026-08-25T16:00:00Z","metadataVersion":1},{"PartitionKey":"instance","RowKey":"alpha","displayName":"Alpha","dataNamespace":"alpha","environment":"dev","state":"Reserved","createdAt":"2026-08-25T16:00:00Z","createdBy":"fake-principal","updatedAt":"2026-08-25T16:00:00Z","metadataVersion":1}],"nextMarker":{"nextpartitionkey":"instance","nextrowkey":"zeta"}}
JSON
      fi
      ;;
    merge)
      echo '{}'
      ;;
    *) echo "unsupported fake storage entity command: $cmd" >&2; exit 2 ;;
  esac
  exit 0
fi
echo "unsupported fake az command: $*" >&2
exit 2
FAKEAZ
chmod +x "$FAKE_BIN/az"

# Usage and required-option failures still emit schema-valid envelopes once an
# action is known.
if run_cli create --subscription-id sub --storage-account-name st --logical-instance-id demo-user --display-name "Demo User"; then
  fail "missing environment: expected nonzero"
else
  assert_schema "missing environment" "$SCRATCH_DIR/out.json"
fi

if run_cli create --environment dev --subscription-id sub --storage-account-name st --logical-instance-id ab --display-name "Bad"; then
  fail "short id: expected nonzero"
else
  assert_schema "short id" "$SCRATCH_DIR/out.json"
  jq -e '.diagnostics[0].code == "INVALID_LOGICAL_INSTANCE_ID"' "$SCRATCH_DIR/out.json" >/dev/null || fail "short id code"
fi

if run_cli create --environment dev --subscription-id sub --storage-account-name st --logical-instance-id 'bad_id' --display-name "Bad"; then
  fail "bad chars: expected nonzero"
else
  assert_schema "bad chars" "$SCRATCH_DIR/out.json"
fi

if run_cli retire --environment dev --subscription-id sub --storage-account-name st --logical-instance-id demo-user; then
  fail "retire without confirm: expected nonzero"
else
  assert_schema "retire without confirm" "$SCRATCH_DIR/out.json"
  jq -e '.diagnostics[0].code == "CONFIRMATION_REQUIRED"' "$SCRATCH_DIR/out.json" >/dev/null || fail "retire confirmation code"
fi

# Recognised action surface and successful envelopes through fake az.
for action in create show list retire; do
  case "$action" in
    create) args="create --environment dev --subscription-id sub --storage-account-name st --logical-instance-id ' Demo-User ' --display-name 'Demo User'" ;;
    show) args="show --environment dev --subscription-id sub --storage-account-name st --logical-instance-id Demo-User" ;;
    list) args="list --environment dev --subscription-id sub --storage-account-name st" ;;
    retire) args="retire --environment dev --subscription-id sub --storage-account-name st --logical-instance-id demo-user --confirm" ;;
  esac
  eval "run_cli $args"
  rc=$?
  if [ "$rc" -ne 0 ]; then fail "$action success path exited $rc: $(cat "$SCRATCH_DIR/err.log")"; continue; fi
  assert_schema "$action success" "$SCRATCH_DIR/out.json"
  jq -e --arg action "$action" '.action == $action' "$SCRATCH_DIR/out.json" >/dev/null || fail "$action action field"
done

run_cli create --environment dev --subscription-id sub --storage-account-name st --logical-instance-id ' Demo-User ' --display-name 'Demo User'
jq -e '.logicalInstance.id == "demo-user" and .logicalInstance.dataNamespace == "demo-user"' "$SCRATCH_DIR/out.json" >/dev/null \
  && pass "create normalizes identifiers before writing" \
  || fail "create did not normalize identifier: $(cat "$SCRATCH_DIR/out.json")"

run_cli list --environment dev --subscription-id sub --storage-account-name st
jq -e '.logicalInstance | map(.id) == ["alpha", "beta", "zeta"]' "$SCRATCH_DIR/out.json" >/dev/null \
  && pass "list follows lowercase continuation marker and sorts output" \
  || fail "list did not include both pages in sorted order: $(cat "$SCRATCH_DIR/out.json")"

# Static constant-resource invariant: the logical-instance CLI must not name
# or invoke infrastructure allocation paths.
for forbidden in 'az deployment' 'az group create' 'az staticwebapp create' 'az afd endpoint' 'instance-route.sh register'; do
  if grep -F "$forbidden" "$CLI" >/dev/null 2>&1; then
    fail "CLI source references forbidden infrastructure operation: $forbidden"
  else
    pass "forbidden infrastructure operation absent: $forbidden"
  fi
done

if grep -Eiq 'AccountKey=|sig=|client_secret|Authorization: Bearer|deploymentToken' "$SCRATCH_DIR/out.json"; then
  fail "stdout contains secret-bearing material"
else
  pass "stdout contains no secret-bearing material"
fi

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES contract test(s) failed"
  exit 1
fi
log "all contract tests passed"
