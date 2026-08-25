#!/bin/bash
# Read-only static contract tests for the shared-service workflow cutover.
# These checks inspect workflow and adapter source only; they never invoke Azure.
# Bash 3.2 compatible: no arrays, associative arrays, or Bash 4 syntax.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/ci-cd.yml"
ADAPTER_DIR="$ROOT_DIR/scripts/pipeline/shared-service"
FAILURES=0

log() {
  echo "[shared-service-workflow] $*" >&2
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
    log "$FAILURES shared workflow contract check(s) failed"
    return 1
  fi
  log "shared workflow contract passed"
  return 0
}

line_number() {
  pattern="$1"
  grep -F -n -- "$pattern" "$WORKFLOW_FILE" | head -n 1 | cut -d: -f1
}

require_workflow_text() {
  description="$1"
  pattern="$2"
  if grep -F -q -- "$pattern" "$WORKFLOW_FILE"; then
    pass "$description"
  else
    fail "$description (missing from workflow: $pattern)"
  fi
}

require_shared_path_text() {
  description="$1"
  pattern="$2"
  if grep -F -q -- "$pattern" "$WORKFLOW_FILE" "$ADAPTER_DIR"/*.sh 2>/dev/null; then
    pass "$description"
  else
    fail "$description (missing from shared workflow/adapters: $pattern)"
  fi
}

require_absent() {
  description="$1"
  pattern="$2"
  if ! grep -F -q -- "$pattern" "$WORKFLOW_FILE" "$ADAPTER_DIR"/*.sh 2>/dev/null; then
    pass "$description"
  else
    fail "$description (forbidden in shared workflow/adapters: $pattern)"
  fi
}

require_after() {
  description="$1"
  before_pattern="$2"
  after_pattern="$3"
  before_line="$(line_number "$before_pattern")"
  after_line="$(line_number "$after_pattern")"
  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$description"
  else
    fail "$description (expected '$after_pattern' after '$before_pattern')"
  fi
}

require_job_absent() {
  description="$1"
  pattern="$2"
  if ! grep -F -q -- "$pattern" "$WORKFLOW_FILE"; then
    pass "$description"
  else
    fail "$description (unexpected workflow job/step: $pattern)"
  fi
}

if [ ! -f "$WORKFLOW_FILE" ]; then
  fail "workflow not found: $WORKFLOW_FILE"
elif [ ! -d "$ADAPTER_DIR" ]; then
  fail "shared adapter directory not found: $ADAPTER_DIR"
else
  pass "workflow found: $WORKFLOW_FILE"
  pass "shared adapters found: $ADAPTER_DIR"

  # Trigger behavior: push and manual dispatch deploy one selected environment;
  # pull requests validate only and have no close/delete path.
  require_workflow_text "push to main is configured" "push:"
  require_workflow_text "manual dispatch is configured" "workflow_dispatch:"
  require_workflow_text "manual dispatch exposes environment selection" "environment:"
  require_workflow_text "pull requests run validation only" "pull_request:"
  require_workflow_text "pull request validation job is present" "pr_validation:"
  require_job_absent "pull request closed trigger is absent" "closed"
  require_job_absent "per-PR close job is removed" "close_pull_request_job:"
  require_job_absent "per-PR resource deletion is removed" "Delete PR Resource Group"

  # Required persistent ordering. Names are intentionally stable so failures
  # identify the broken stage without parsing full YAML.
  require_after "offline contracts run before Azure login" \
    "name: Run Offline Contracts" "name: Azure Login"
  require_after "result is initialized before Azure mutation" \
    "name: Initialize Shared Publication Result" "name: Azure Login"
  require_after "configuration is resolved before deployment" \
    "name: Resolve Shared Service Configuration" "name: Validate, What-If, and Deploy Shared Service"
  require_after "shared deploy precedes application upload" \
    "name: Validate, What-If, and Deploy Shared Service" "name: Build And Deploy Shared Application"
  require_after "SWA hostname validation follows upload" \
    "name: Build And Deploy Shared Application" "name: Validate Shared Static Web App Deployment"
  require_after "route verification follows upload validation" \
    "name: Validate Shared Static Web App Deployment" "name: Verify Shared Service"
  require_after "publication reporting follows route verification" \
    "name: Verify Shared Service" "name: Report Shared Service"
  require_after "artifact retention follows reporting" \
    "name: Report Shared Service" "name: Retain Shared Service Artifacts"

  # Concurrency and artifacts.
  require_workflow_text "shared deployment job has environment scope" "name: \${{ github.event_name == 'workflow_dispatch' && inputs.environment || 'prod' }}"
  require_workflow_text "shared concurrency is environment-scoped" "group: shared-service-\${{ github.event_name == 'workflow_dispatch' && inputs.environment || 'prod' }}"
  require_workflow_text "shared concurrency does not cancel queued runs" "cancel-in-progress: false"
  require_workflow_text "shared artifact retention is unconditional" "if: always()"
  require_workflow_text "shared artifact name includes environment and run id" "shared-service-\${{ env.DEPLOYMENT_ENVIRONMENT }}-\${{ github.run_id }}"
  require_workflow_text "partial artifact absence is warning-only" "if-no-files-found: warn"
  require_workflow_text "publication result is retained" "shared-publication-result.json"
  require_workflow_text "validation result is retained" "shared-validation.json"
  require_workflow_text "what-if result is retained" "shared-what-if.json"
  require_workflow_text "deployment result is retained" "shared-deployment.json"
  require_workflow_text "route verification result is retained" "shared-route-verification.json"
  require_workflow_text "pre-mutation inventory is retained" "shared-inventory-before.json"
  require_workflow_text "post-mutation inventory is retained" "shared-inventory-after.json"

  # Forbidden New-Path Behavior from the workflow contract.
  require_absent "persistent path does not accept an instance input" "instance_id:"
  require_absent "persistent path does not derive an instance ID" "Determine Instance ID"
  require_absent "persistent path does not use instance outputs" "instanceId:"
  require_absent "persistent path does not generate PR resource groups" "pull_request.number"
  require_absent "persistent path does not use run-scoped resource suffixes" "github.run_number"
  require_absent "persistent path does not invoke legacy infra template" "infra/main.bicep"
  require_absent "persistent path does not invoke instance route CLI" "instance-route.sh"
  require_absent "persistent path does not register instance routes" "register"
  require_absent "persistent path does not unregister instance routes" "unregister"
  require_absent "persistent path does not run instance route verification" "instance-route.sh verify"
  require_absent "persistent path does not create per-run SWA names" "staticWebAppName: \${{ steps.deploy.outputs.staticWebAppName }}"
  require_absent "shared endpoint is not attached by the front-door adapters" "scripts/pipeline/front-door"
  require_absent "pull-request path does not create a resource group" "Create Resource Group"
  require_absent "pull-request path does not deploy infrastructure" "Deploy Infrastructure"
  require_absent "pull-request path does not close SWA preview environments" "action: \"close\""
  require_absent "pull-request path does not delete resource groups" "delete-resource-group.sh"

  # Shared adapters must call the shared CLI and expose one stable public URL.
  require_shared_path_text "shared deploy adapter invokes shared-service deploy" "./scripts/shared-service.sh \"\$action\""
  require_shared_path_text "shared deploy adapter captures deployment JSON" "shared-deployment.json"
  require_shared_path_text "shared verify adapter invokes shared-service verify" "./scripts/shared-service.sh verify"
  require_shared_path_text "shared verify accepts only Succeeded" ".status == \"Succeeded\""
  require_shared_path_text "stable public URL is exported" "sharedPublicUrl="
  require_shared_path_text "stable public URL is written to the summary" "GITHUB_STEP_SUMMARY"
fi

finish
