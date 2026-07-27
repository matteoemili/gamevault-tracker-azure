#!/usr/bin/env bash
set -e

set +e
./scripts/cors-add-origin.sh \
  --storage-account-name "$STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --origin "$ENDPOINT_URL" >/dev/null
CORS_RC=$?
set -e
if [ "$CORS_RC" -ne 0 ]; then
  jq '.stage = "Cors" | .status = "Failed" |
    .diagnostics = [{code:"CORS_ALIGNMENT_FAILED",message:"Published origin could not be aligned with Table Storage CORS"}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  exit "$CORS_RC"
fi
jq '.stage = "Cors" | .diagnostics = [{code:"CORS_ALIGNMENT_SUCCEEDED",message:"Published origin aligned with Table Storage CORS"}]' \
  publication-result.json > publication-result.tmp
mv publication-result.tmp publication-result.json
