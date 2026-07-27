#!/usr/bin/env bash
set -e

if [ -z "$RESOURCE_GROUP" ]; then
  echo "No resource group determined. Skipping."
  echo "found=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

if az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
  SWA_NAME=$(az staticwebapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")

  if [ -n "$SWA_NAME" ]; then
    echo "Found Static Web App: $SWA_NAME"
    TOKEN=$(az staticwebapp secrets list --name "$SWA_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.apiKey" -o tsv)
    echo "::add-mask::$TOKEN"
    echo "swa_token=$TOKEN" >> "$GITHUB_OUTPUT"
    echo "found=true" >> "$GITHUB_OUTPUT"
  else
    echo "No Static Web App found in resource group"
    echo "found=false" >> "$GITHUB_OUTPUT"
  fi
else
  echo "Resource group not found, skipping"
  echo "found=false" >> "$GITHUB_OUTPUT"
fi
