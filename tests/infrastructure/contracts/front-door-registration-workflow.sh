#!/bin/bash
# Read-only static contract tests for the automatic Front Door registration
# workflow. These checks deliberately inspect the workflow source rather than
# invoking Azure.
# Bash 3.2 compatible: do not use arrays, associative arrays, or Bash 4 syntax.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/ci-cd.yml"

FAILURES=0

log() {
  echo "[front-door-registration-workflow] $*" >&2
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

  log "workflow ordering and input-mapping contract passed"
  return 0
}

if [ ! -f "$WORKFLOW_FILE" ]; then
  fail "workflow not found: $WORKFLOW_FILE"
else
  pass "workflow found: $WORKFLOW_FILE"

  # Return the first source line containing a literal.  Keeping this helper
  # line-oriented avoids Bash 4 features and makes ordering failures useful.
  line_number() {
    pattern="$1"
    grep -F -n -- "$pattern" "$WORKFLOW_FILE" | head -n 1 | cut -d: -f1
  }

  require_text() {
    description="$1"
    pattern="$2"
    if grep -F -q -- "$pattern" "$WORKFLOW_FILE" "$ROOT_DIR"/scripts/pipeline/*/*.sh 2>/dev/null; then
      pass "$description"
    else
      fail "$description (missing from workflow or extracted pipeline scripts: $pattern)"
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

  require_not_between() {
    description="$1"
    start_pattern="$2"
    end_pattern="$3"
    rejected_pattern="$4"
    start_line="$(line_number "$start_pattern")"
    end_line="$(line_number "$end_pattern")"
    if [ -n "$start_line" ] && [ -n "$end_line" ] && [ "$start_line" -lt "$end_line" ] &&
      ! sed -n "${start_line},${end_line}p" "$WORKFLOW_FILE" | grep -F -q -- "$rejected_pattern"; then
      pass "$description"
    else
      fail "$description (unexpected between '$start_pattern' and '$end_pattern': $rejected_pattern)"
    fi
  }

  # Application publication must not begin until the Static Web App upload
  # has completed successfully.
  require_text "Static Web App upload action is present" 'action: "upload"'
  require_text "Static Web App upload identifies the production branch" \
    'production_branch: ${{ github.base_ref || github.ref_name }}'
  require_text "non-PR deployment URL is checked against the production hostname" \
    'elif [ "$DEPLOYED_URL" != "$EXPECTED_URL" ]; then'
  require_text "PR deployment URL is checked against its Azure preview hostname" \
    '"${DEFAULT_SUBDOMAIN}-${PR_NUMBER}."*.azurestaticapps.net)'
  require_text "actual Static Web App hostname is exposed to publication" \
    'staticWebAppOriginHostname: ${{ steps.validate_swa.outputs.deployedHostname }}'
  require_not_between "build job does not leak a named SWA deployment environment" \
    'build_and_deploy_job:' 'publish_front_door:' \
    'DEPLOYMENT_ENVIRONMENT:'
  require_after "route registration follows application upload" \
    'action: "upload"' 'name: Register Instance Front Door Route'
  require_after "CORS alignment follows route registration" \
    'name: Register Instance Front Door Route' 'name: Configure Front Door Table CORS'
  require_after "route verification follows CORS alignment" \
    'name: Configure Front Door Table CORS' 'name: Verify Published Front Door Route'

  # Publication receives explicit, environment-scoped platform and instance
  # inputs rather than relying on an implicit Azure CLI context.
  require_text "platform resource group is explicitly configured" \
    'PLATFORM_RESOURCE_GROUP_DEV: ${{ secrets.GAMEVAULT_PLATFORM_RESOURCE_GROUP_DEV }}'
  require_text "Front Door profile is explicitly configured" \
    'FRONT_DOOR_PROFILE_PROD: ${{ secrets.GAMEVAULT_FRONT_DOOR_PROFILE_PROD }}'
  require_text "deployment environment is passed to publication" \
    '--environment "$DEPLOYMENT_ENVIRONMENT"'
  require_text "instance resource group is passed to registration" \
    '--instance-resource-group "$AZURE_RESOURCE_GROUP"'
  require_text "Static Web App name is passed to registration" \
    '--static-web-app-name "$STATIC_WEB_APP"'
  require_text "actual deployed hostname is passed to registration" \
    '--origin-hostname "$STATIC_WEB_APP_ORIGIN_HOSTNAME"'
  require_text "platform resource group is passed to registration" \
    '--platform-resource-group "$PLATFORM_RESOURCE_GROUP"'
  require_text "Front Door profile is passed to registration" \
    '--front-door-profile "$FRONT_DOOR_PROFILE"'
  require_text "subscription is resolved explicitly for registration" \
    '--subscription-id "$(az account show --query id -o tsv)"'

  # Registration mutates shared Front Door profile state, so only the short
  # publication phase is serialized.  The key must be profile-scoped rather
  # than instance- or run-scoped, and queued publications must not be
  # cancelled.
  require_text "publication concurrency is scoped to the Front Door profile" \
    'group: front-door-publication-${{ needs.deploy_infrastructure.outputs.environment }}'
  require_text "publication concurrency does not cancel queued runs" \
    'cancel-in-progress: false'

  # Registration must emit a route result and expose its HTTPS endpoint to the
  # following CORS and verification stages.
  require_text "registration result is captured" \
    '> route-registration.json'
  require_text "registered endpoint is exported" \
    'echo "endpointUrl=$ENDPOINT_URL" >> "$GITHUB_OUTPUT"'
  require_text "CORS uses the registered endpoint" \
    '--origin "$ENDPOINT_URL"'
  require_text "registered endpoint is passed to the CORS script" \
    'ENDPOINT_URL: ${{ steps.register_route.outputs.endpointUrl }}'
  require_text "CORS targets the deployed storage account" \
    '--storage-account-name "$STORAGE_ACCOUNT"'

  # Verification must use the same explicit instance/platform scope as
  # registration and gate publication success on Succeeded.
  require_text "verification invokes the existing route CLI" \
    './scripts/instance-route.sh verify'
  require_text "platform resource group is passed to verification" \
    '--platform-resource-group "$PLATFORM_RESOURCE_GROUP"'
  require_text "Front Door profile is passed to verification" \
    '--front-door-profile "$FRONT_DOOR_PROFILE"'
  require_text "actual deployed hostname is passed to verification" \
    '--expected-origin-hostname "$STATIC_WEB_APP_ORIGIN_HOSTNAME"'
  require_text "verification accepts only Succeeded" \
    "jq -e '.status == \"Succeeded\"' route-verification.json"

  # The verified URL is part of the workflow's public result, not merely a
  # step-local value.
  require_text "published URL is exposed as a job output" \
    'publishedUrl:'
  require_text "published URL is written to the workflow summary" \
    'GITHUB_STEP_SUMMARY'

  # The publication manifest is the workflow-level failure contract.  It must
  # exist before any preflight can fail, and each lifecycle stage must update
  # it so partial failures remain explainable without relying on log output.
  require_text "publication result is initialized" \
    'name: Initialize Publication Result'
  require_after "publication result is initialized before preflight" \
    'name: Initialize Publication Result' 'name: Validate Publication Inputs'
  require_after "publication result is initialized before registration" \
    'name: Initialize Publication Result' 'name: Register Instance Front Door Route'
  require_text "preflight success updates the publication result" \
    'code:"PREFLIGHT_OK"'
  require_text "preflight failure updates the publication result" \
    'code:"PREFLIGHT_FAILED"'
  require_text "registration updates the publication result" \
    'code:("REGISTRATION_" + $status)'
  require_text "registration failure updates the publication result" \
    'code:"REGISTRATION_FAILED"'
  require_text "CORS success updates the publication result" \
    'code:"CORS_ALIGNMENT_SUCCEEDED"'
  require_text "CORS failure updates the publication result" \
    'code:"CORS_ALIGNMENT_FAILED"'
  require_text "verification updates the publication result" \
    '.stage = $stage | .verificationResultFile = $file'
  require_text "verification failure updates the publication result" \
    'code:"VERIFICATION_FAILED"'
  require_text "successful publication updates the publication result" \
    'code:"PUBLICATION_SUCCEEDED"'

  # Verification is deliberately stricter than registration: only a
  # schema-shaped Succeeded result may complete publication.  Degraded and
  # Failed statuses, malformed JSON, and empty output must all remain failures.
  require_text "verification accepts only Succeeded" \
    "jq -e '.status == \"Succeeded\"' route-verification.json"
  require_text "degraded verification is rejected by the success gate" \
    'if [ "$VERIFY_RC" -eq 0 ] && jq -e'
  require_text "failed verification is rejected" \
    'if [ "$VERIFY_STATUS" = "Failed" ]'
  require_text "malformed verification is treated as invalid" \
    '.status // "Invalid"'
  require_text "empty verification output is retained as a failure" \
    'code":"EMPTY_VERIFICATION"'

  # Diagnostic files must survive every failure path.  The artifact upload is
  # allowed to warn about files that were never produced, while preserving all
  # results available up to the failing stage.
  require_text "publication result is included in retained artifacts" \
    'publication-result.json'
  require_text "publication artifacts are retained on every outcome" \
    'if: always()'
  require_text "partial artifact absence is warning-only" \
    'if-no-files-found: warn'
  require_text "registration result is included in retained artifacts" \
    'route-registration.json'
  require_text "verification result is included in retained artifacts" \
    'route-verification.json'
  require_text "forwarding gateway result is included in retained artifacts" \
    'route-forwarding-gateway.json'
fi

finish
