#!/bin/bash
# Read-only contract test for the infrastructure validation workflow.
# Bash 3.2 compatible.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/validate-infrastructure.yml"
FAILURES=0

log() {
  echo "[validate-infrastructure-workflow] $*" >&2
}

fail() {
  log "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

pass() {
  log "ok: $*"
}

require_text() {
  description="$1"
  pattern="$2"
  if grep -F -q -- "$pattern" "$WORKFLOW_FILE"; then
    pass "$description"
  else
    fail "$description (missing: $pattern)"
  fi
}

require_absent() {
  description="$1"
  pattern="$2"
  if ! grep -F -q -- "$pattern" "$WORKFLOW_FILE"; then
    pass "$description"
  else
    fail "$description (unexpected: $pattern)"
  fi
}

require_before() {
  description="$1"
  before_pattern="$2"
  after_pattern="$3"
  before_line="$(grep -F -n -- "$before_pattern" "$WORKFLOW_FILE" | head -n 1 | cut -d: -f1)"
  after_line="$(grep -F -n -- "$after_pattern" "$WORKFLOW_FILE" | head -n 1 | cut -d: -f1)"
  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$description"
  else
    fail "$description (expected '$before_pattern' before '$after_pattern')"
  fi
}

if [ ! -f "$WORKFLOW_FILE" ]; then
  fail "workflow not found: $WORKFLOW_FILE"
else
  require_absent "unsupported setup action is not used" 'azure/setup-bicep@'
  require_text "Bicep availability step is named" 'name: Ensure Bicep is available'
  require_text "existing Bicep installation is reused" 'az bicep version >/dev/null 2>&1 || az bicep install'
  require_before "Bicep is available before template builds" \
    'name: Ensure Bicep is available' 'name: Build all Bicep templates'
fi

if [ "$FAILURES" -gt 0 ]; then
  log "$FAILURES workflow contract check(s) failed"
  exit 1
fi

log "workflow Bicep setup contract passed"
