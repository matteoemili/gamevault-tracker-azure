#!/bin/bash
# Read-only static contract tests for the simplified deployment workflow that
# publishes the Static Web App hostname directly, with no Front Door stage.
# These checks deliberately inspect workflow source rather than invoking Azure.
# Bash 3.2 compatible: do not use arrays, associative arrays, or Bash 4 syntax.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
DIRECT_WORKFLOW="$ROOT_DIR/.github/workflows/ci-cd-direct.yml"
FRONT_DOOR_WORKFLOW="$ROOT_DIR/.github/workflows/ci-cd.yml"
CORS_SCRIPT="$ROOT_DIR/scripts/pipeline/direct/align-deployed-origin-cors.sh"
REPORT_SCRIPT="$ROOT_DIR/scripts/pipeline/direct/report-direct-deployment.sh"

FAILURES=0

log() {
  echo "[direct-deployment-workflow] $*" >&2
}

fail() {
  log "FAIL: $*"
  FAILURES=$((FAILURES + 1))
}

pass() {
  log "ok: $*"
}

finish() {
  if [ "$FAILURES" -gt 0 ]; then
    log "$FAILURES workflow contract check(s) failed"
    return 1
  fi

  log "direct publication contract passed"
  return 0
}

require_file() {
  description="$1"
  file="$2"
  if [ -f "$file" ]; then
    pass "$description"
  else
    fail "$description (missing file: $file)"
  fi
}

require_file_text() {
  description="$1"
  file="$2"
  pattern="$3"
  if grep -F -q -- "$pattern" "$file" 2>/dev/null; then
    pass "$description"
  else
    fail "$description (missing from $(basename "$file"): $pattern)"
  fi
}

require_file_absent() {
  description="$1"
  file="$2"
  pattern="$3"
  if ! grep -F -q -- "$pattern" "$file" 2>/dev/null; then
    pass "$description"
  else
    fail "$description (unexpected in $(basename "$file"): $pattern)"
  fi
}

require_count() {
  description="$1"
  file="$2"
  pattern="$3"
  expected="$4"
  actual="$(grep -F -c -- "$pattern" "$file" 2>/dev/null || echo 0)"
  if [ "$actual" -eq "$expected" ]; then
    pass "$description"
  else
    fail "$description (expected $expected occurrence(s) of '$pattern', found $actual)"
  fi
}

require_order() {
  description="$1"
  file="$2"
  before_pattern="$3"
  after_pattern="$4"
  before_line="$(grep -F -n -- "$before_pattern" "$file" | head -n 1 | cut -d: -f1)"
  after_line="$(grep -F -n -- "$after_pattern" "$file" | head -n 1 | cut -d: -f1)"
  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$description"
  else
    fail "$description (expected '$after_pattern' after '$before_pattern')"
  fi
}

require_between() {
  description="$1"
  file="$2"
  start_pattern="$3"
  end_pattern="$4"
  expected_pattern="$5"
  start_line="$(grep -F -n -- "$start_pattern" "$file" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -F -n -- "$end_pattern" "$file" | head -n 1 | cut -d: -f1)"
  if [ -n "$start_line" ] && [ -n "$end_line" ] && [ "$start_line" -lt "$end_line" ] &&
    sed -n "${start_line},${end_line}p" "$file" | grep -F -q -- "$expected_pattern"; then
    pass "$description"
  else
    fail "$description (expected '$expected_pattern' between '$start_pattern' and '$end_pattern')"
  fi
}

require_file "simplified workflow exists" "$DIRECT_WORKFLOW"
require_file "direct CORS alignment script exists" "$CORS_SCRIPT"
require_file "direct publication report script exists" "$REPORT_SCRIPT"

if [ -f "$DIRECT_WORKFLOW" ] && [ -f "$FRONT_DOOR_WORKFLOW" ]; then
  # The whole point of the simplified pipeline: no shared edge profile is read,
  # mutated, or verified anywhere in it.
  require_file_absent "simplified workflow does not register Front Door routes" \
    "$DIRECT_WORKFLOW" 'instance-route.sh'
  require_file_absent "simplified workflow does not use Front Door scripts" \
    "$DIRECT_WORKFLOW" 'scripts/pipeline/front-door/'
  require_file_absent "simplified workflow does not resolve a Front Door profile" \
    "$DIRECT_WORKFLOW" 'FRONT_DOOR_PROFILE'
  require_file_absent "simplified workflow does not need the platform resource group" \
    "$DIRECT_WORKFLOW" 'PLATFORM_RESOURCE_GROUP'
  require_file_absent "simplified publication does not depend on an edge hostname" \
    "$REPORT_SCRIPT" 'azurefd.net'

  # Exactly one pipeline may deploy an instance, so the two workflows must be
  # gated on opposite values of the same repository variable.
  require_count "every simplified job is gated off when Front Door publication is enabled" \
    "$DIRECT_WORKFLOW" "vars.FRONT_DOOR_PUBLICATION_ENABLED != 'true'" 3
  require_count "every Front Door job is gated on explicit opt-in" \
    "$FRONT_DOOR_WORKFLOW" "vars.FRONT_DOOR_PUBLICATION_ENABLED == 'true'" 4

  # Instance resources are shared between the two pipelines, so their
  # infrastructure concurrency key must match to prevent concurrent mutation.
  require_file_text "simplified workflow serializes against the Front Door pipeline" \
    "$DIRECT_WORKFLOW" 'group: instance-infrastructure-${{ github.event.inputs.instance_id || github.event.pull_request.number || github.ref_name }}'

  # Reuse of the existing instance deployment path, not a second implementation.
  require_file_text "simplified workflow reuses instance determination" \
    "$DIRECT_WORKFLOW" './scripts/pipeline/infrastructure/determine-instance.sh'
  require_file_text "simplified workflow reuses infrastructure deployment" \
    "$DIRECT_WORKFLOW" './scripts/pipeline/infrastructure/deploy-infrastructure.sh'
  require_file_text "simplified workflow reuses deployment validation" \
    "$DIRECT_WORKFLOW" './scripts/pipeline/application/validate-static-web-app-deployment.sh'

  # Publication ordering: nothing is published before the upload is validated.
  require_order "application upload precedes deployment validation" \
    "$DIRECT_WORKFLOW" 'action: "upload"' 'name: Validate Static Web App Deployment'
  require_order "CORS alignment follows deployment validation" \
    "$DIRECT_WORKFLOW" 'name: Validate Static Web App Deployment' 'name: Align Deployed Origin CORS'
  require_order "publication reporting follows CORS alignment" \
    "$DIRECT_WORKFLOW" 'name: Align Deployed Origin CORS' 'name: Report Published Static Web App'

  # The actual deployed hostname, not the assumed production hostname, is the
  # published address and the CORS origin.
  require_file_text "CORS alignment uses the validated hostname" \
    "$DIRECT_WORKFLOW" 'DEPLOYED_HOSTNAME: ${{ steps.validate_swa.outputs.deployedHostname }}'
  require_file_text "CORS alignment targets the deployed storage account" \
    "$CORS_SCRIPT" '--storage-account-name "$STORAGE_ACCOUNT"'
  require_file_text "CORS alignment adds the deployed origin" \
    "$CORS_SCRIPT" '--origin "https://${DEPLOYED_HOSTNAME}"'
  require_file_text "missing hostname fails CORS alignment" \
    "$CORS_SCRIPT" 'if [ -z "${DEPLOYED_HOSTNAME:-}" ]; then'
  require_file_text "missing hostname fails publication reporting" \
    "$REPORT_SCRIPT" 'if [ -z "${DEPLOYED_HOSTNAME:-}" ]; then'

  # The published URL is a workflow-level result, as in the Front Door pipeline.
  require_file_text "published URL is exposed as a job output" \
    "$DIRECT_WORKFLOW" 'publishedUrl: ${{ steps.publish_result.outputs.publishedUrl }}'
  require_file_text "published URL is exported from the report script" \
    "$REPORT_SCRIPT" 'echo "publishedUrl=$PUBLISHED_URL" >> "$GITHUB_OUTPUT"'
  require_file_text "published URL is written to the workflow summary" \
    "$REPORT_SCRIPT" 'GITHUB_STEP_SUMMARY'
  require_file_text "publication result is retained" \
    "$DIRECT_WORKFLOW" 'path: direct-publication-result.json'
  require_file_text "publication artifacts are retained on every outcome" \
    "$DIRECT_WORKFLOW" 'if: always()'

  # Both pull request cleanup jobs run repository scripts, so both need a
  # checked-out workspace before the first script step.
  require_between "simplified cleanup job checks out before running scripts" \
    "$DIRECT_WORKFLOW" 'name: Close Pull Request Job (Direct)' 'name: Determine PR Instance' \
    'uses: actions/checkout@v4'
  require_between "Front Door cleanup job checks out before running scripts" \
    "$FRONT_DOOR_WORKFLOW" 'name: Close Pull Request Job' 'name: Determine PR Instance' \
    'uses: actions/checkout@v4'
fi

finish
