#!/bin/bash
# Publish the stable shared public URL to job outputs and the workflow summary.
# Bash 3.2 compatible.

set -e

RESULT_FILE="${SHARED_PUBLICATION_RESULT_FILE:-shared-publication-result.json}"

PUBLIC_URL="$(jq -r '.sharedService.publicUrl // empty' shared-route-verification.json 2>/dev/null || true)"
if [ -z "$PUBLIC_URL" ]; then
  PUBLIC_URL="$(jq -r '.sharedService.publicUrl // empty' shared-deployment.json 2>/dev/null || true)"
fi

if [ -z "$PUBLIC_URL" ]; then
  jq '.stage = "Complete" | .status = "Failed" |
    .diagnostics = [{code:"MISSING_SHARED_PUBLIC_URL",message:"Shared service did not return a stable public URL"}]' \
    "$RESULT_FILE" > shared-publication-result.tmp
  mv shared-publication-result.tmp "$RESULT_FILE"
  echo "::error::Could not extract shared public URL"
  exit 1
fi

jq --arg url "$PUBLIC_URL" \
  '.stage = "Complete" | .status = "Succeeded" | .publishedUrl = $url |
   .diagnostics = [{code:"SHARED_PUBLICATION_SUCCEEDED",message:"Shared service route verified successfully"}]' \
  "$RESULT_FILE" > shared-publication-result.tmp
mv shared-publication-result.tmp "$RESULT_FILE"

{
  echo "sharedPublicUrl=$PUBLIC_URL"
  echo "publishedUrl=$PUBLIC_URL"
} >> "${GITHUB_OUTPUT:-/dev/null}"

{
  echo "### Shared service publication"
  echo ""
  echo "Stable shared public URL: $PUBLIC_URL"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
