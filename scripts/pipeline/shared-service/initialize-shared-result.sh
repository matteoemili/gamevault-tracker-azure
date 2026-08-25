#!/bin/bash
# Initialize the shared-service publication result before any Azure mutation.
# Bash 3.2 compatible.

set -e

RESULT_FILE="${SHARED_PUBLICATION_RESULT_FILE:-shared-publication-result.json}"
RUN_ID="${GITHUB_RUN_ID:-local}"
ENVIRONMENT_NAME="${DEPLOYMENT_ENVIRONMENT:-${ENVIRONMENT:-}}"

jq -n \
  --arg runId "$RUN_ID" \
  --arg environment "$ENVIRONMENT_NAME" \
  '{
    schemaVersion: "1.0",
    runId: $runId,
    environment: $environment,
    stage: "Preflight",
    status: "Pending",
    publishedUrl: null,
    deploymentResultFile: null,
    verificationResultFile: null,
    diagnostics: []
  }' > "$RESULT_FILE"
