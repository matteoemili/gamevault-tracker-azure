#!/usr/bin/env bash
set -e

echo "🔑 Retrieving storage account key..."
ACCOUNT_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query '[0].value' \
  --output tsv)

if [ -z "$ACCOUNT_KEY" ]; then
  echo "❌ Failed to retrieve storage account key"
  exit 1
fi

echo "✅ Storage account key retrieved"

EXPIRY=$(date -u -v+1y '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '+1 year' '+%Y-%m-%dT%H:%M:%SZ')

echo "🔐 Generating SAS token (valid until $EXPIRY)..."
SAS_TOKEN=$(az storage account generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$ACCOUNT_KEY" \
  --services t \
  --resource-types sco \
  --permissions raud \
  --expiry "$EXPIRY" \
  --https-only \
  --output tsv)

if [ -z "$SAS_TOKEN" ]; then
  echo "❌ Failed to generate SAS token"
  exit 1
fi

echo "✅ SAS token generated successfully (length: ${#SAS_TOKEN} characters)"
echo "sas_token=$SAS_TOKEN" >> "$GITHUB_OUTPUT"
