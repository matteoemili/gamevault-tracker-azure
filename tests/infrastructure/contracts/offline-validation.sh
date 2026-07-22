#!/bin/bash
# ============================================================================
# offline-validation.sh - Stage 1 offline validation (no Azure mutation)
# ============================================================================
# Runs, with no Azure credentials required and no resource mutation:
#   1. `az bicep build` against every platform Bicep template.
#   2. `bash -n` syntax checks on every project shell script.
#   3. ShellCheck (if installed) as a soft, non-fatal warning pass.
#   4. The output-schema.sh self-test suite.
#
# See specs/001-multi-instance-platform/quickstart.md "Stage 1".
# Bash 3.2 compatible.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

FAILURES=0

log() { echo "[offline-validation] $*" >&2; }

fail() {
  log "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# 1. Bicep build (top-level templates; az bicep build resolves module refs)
# ----------------------------------------------------------------------------
if require_cmd az; then
  log "Building platform Bicep templates..."
  for template in \
    "$PROJECT_ROOT/infra/platform/main.bicep" \
    "$PROJECT_ROOT/infra/platform/instance-route.bicep"
  do
    if [ -f "$template" ]; then
      if az bicep build --file "$template" --stdout >/dev/null 2>"$PROJECT_ROOT/.offline-validation-bicep.err"; then
        log "  ok: $template"
      else
        fail "bicep build failed for $template: $(cat "$PROJECT_ROOT/.offline-validation-bicep.err")"
      fi
      rm -f "$PROJECT_ROOT/.offline-validation-bicep.err"
    else
      fail "expected Bicep template not found: $template"
    fi
  done
else
  fail "az CLI not found; cannot run bicep build"
fi

# ----------------------------------------------------------------------------
# 2. Shell syntax checks
# ----------------------------------------------------------------------------
log "Checking shell script syntax..."
shell_scripts=$(find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tests/infrastructure" -type f -name '*.sh' 2>/dev/null)
if [ -z "$shell_scripts" ]; then
  fail "no shell scripts found under scripts/ or tests/infrastructure/"
else
  echo "$shell_scripts" | while IFS= read -r script; do
    if bash -n "$script" 2>"$PROJECT_ROOT/.offline-validation-shell.err"; then
      : # ok
    else
      echo "SYNTAX_ERROR:$script:$(cat "$PROJECT_ROOT/.offline-validation-shell.err")"
    fi
    rm -f "$PROJECT_ROOT/.offline-validation-shell.err"
  done > "$PROJECT_ROOT/.offline-validation-shell-results.tmp"

  if [ -s "$PROJECT_ROOT/.offline-validation-shell-results.tmp" ]; then
    while IFS= read -r line; do
      fail "shell syntax error: $line"
    done < "$PROJECT_ROOT/.offline-validation-shell-results.tmp"
  else
    log "  all shell scripts passed syntax check"
  fi
  rm -f "$PROJECT_ROOT/.offline-validation-shell-results.tmp"
fi

# ----------------------------------------------------------------------------
# 3. ShellCheck (optional, non-fatal)
# ----------------------------------------------------------------------------
if require_cmd shellcheck; then
  log "Running ShellCheck (warnings only, non-fatal)..."
  echo "$shell_scripts" | while IFS= read -r script; do
    shellcheck -S warning "$script" || true
  done
else
  log "ShellCheck not installed; skipping (optional tool)"
fi

# ----------------------------------------------------------------------------
# 4. JSON schema validator self-test
# ----------------------------------------------------------------------------
SCHEMA_SELF_TEST="$PROJECT_ROOT/tests/infrastructure/contracts/output-schema.sh"
if [ -x "$SCHEMA_SELF_TEST" ]; then
  log "Running output-schema.sh self-test..."
  if "$SCHEMA_SELF_TEST" --self-test; then
    log "  schema self-test passed"
  else
    fail "output-schema.sh self-test reported failures"
  fi
else
  fail "output-schema.sh not found or not executable: $SCHEMA_SELF_TEST"
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
if [ "$FAILURES" -gt 0 ]; then
  log "offline validation FAILED with $FAILURES failing check(s)"
  exit 1
fi

log "offline validation passed"
exit 0
