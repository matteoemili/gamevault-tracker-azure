#!/usr/bin/env bash
set -e

jq -n \
  --arg runId "$GITHUB_RUN_ID" \
  --arg instanceId "$INSTANCE_ID" \
  '{
    schemaVersion: "1.0",
    runId: $runId,
    instanceId: $instanceId,
    stage: "Preflight",
    status: "Pending",
    publishedUrl: null,
    registrationResultFile: null,
    verificationResultFile: null,
    diagnostics: []
  }' > publication-result.json
