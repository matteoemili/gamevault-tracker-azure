#!/usr/bin/env bash
set -e

TOKEN=$(az staticwebapp secrets list --name "$STATIC_WEB_APP" --resource-group "$AZURE_RESOURCE_GROUP" --query "properties.apiKey" -o tsv)
echo "::add-mask::$TOKEN"
echo "swa_token=$TOKEN" >> "$GITHUB_OUTPUT"
