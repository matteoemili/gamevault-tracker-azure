#!/usr/bin/env bash
set -e

# Required environment: STORAGE_ACCOUNT, AZURE_RESOURCE_GROUP, DEPLOYED_HOSTNAME.
# Aligns Table Storage CORS with the hostname the application is actually served
# from. Pull request previews use a generated hostname that the instance
# deployment cannot know in advance, so it is added here instead.
if [ -z "${DEPLOYED_HOSTNAME:-}" ]; then
  echo "::error::Deployed hostname is required to align Table Storage CORS."
  exit 1
fi

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

./scripts/cors-add-origin.sh \
  --storage-account-name "$STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --origin "https://${DEPLOYED_HOSTNAME}"

echo "✅ Table Storage CORS allows https://${DEPLOYED_HOSTNAME}"
