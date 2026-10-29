#!/usr/bin/env bash
set -e

# Required environment: INSTANCE_ID, DEPLOYED_HOSTNAME, STATIC_WEB_APP,
# STORAGE_ACCOUNT, GITHUB_RUN_ID, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
# The Static Web App hostname is the published address in this pipeline, so no
# shared edge profile is read or mutated.
if [ -z "${DEPLOYED_HOSTNAME:-}" ]; then
  echo "::error::Deployed hostname is required to report the published URL."
  exit 1
fi

PUBLISHED_URL="https://${DEPLOYED_HOSTNAME}"

jq -n \
  --arg runId "$GITHUB_RUN_ID" \
  --arg instanceId "$INSTANCE_ID" \
  --arg publishedUrl "$PUBLISHED_URL" \
  --arg staticWebApp "${STATIC_WEB_APP:-}" \
  --arg storageAccount "${STORAGE_ACCOUNT:-}" \
  '{
    schemaVersion: "1.0",
    runId: $runId,
    instanceId: $instanceId,
    stage: "Complete",
    status: "Succeeded",
    publishedUrl: $publishedUrl,
    staticWebAppName: $staticWebApp,
    storageAccountName: $storageAccount,
    diagnostics: [{code:"DIRECT_PUBLICATION_SUCCEEDED",message:"Static Web App published without edge routing"}]
  }' > direct-publication-result.json

echo "publishedUrl=$PUBLISHED_URL" >> "$GITHUB_OUTPUT"
echo "Published Static Web App URL: $PUBLISHED_URL" >> "$GITHUB_STEP_SUMMARY"
echo "✅ Published $PUBLISHED_URL"
