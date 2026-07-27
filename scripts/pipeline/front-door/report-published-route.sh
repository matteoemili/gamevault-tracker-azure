#!/usr/bin/env bash
set -e

ENDPOINT_URL=$(jq -r '.route.url // empty' route-registration.json 2>/dev/null || true)
if [ -z "$ENDPOINT_URL" ]; then
  jq '.stage = "Complete" | .status = "Failed" |
    .diagnostics = [{code:"MISSING_ENDPOINT_URL",message:"Failed to extract published endpoint URL from route registration result"}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  echo "❌ Error: Could not extract endpoint URL from route registration result"
  exit 1
fi
jq --arg url "$ENDPOINT_URL" \
  '.stage = "Complete" | .status = "Succeeded" | .publishedUrl = $url |
   .diagnostics = [{code:"PUBLICATION_SUCCEEDED",message:"Front Door route verified successfully"}]' \
  publication-result.json > publication-result.tmp
mv publication-result.tmp publication-result.json
echo "publishedUrl=$ENDPOINT_URL" >> "$GITHUB_OUTPUT"
echo "Published Front Door URL: $ENDPOINT_URL" >> "$GITHUB_STEP_SUMMARY"
