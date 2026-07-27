#!/usr/bin/env bash
set -e

echo "📦 Creating resource group: $AZURE_RESOURCE_GROUP"
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --tags \
    application="GameVault Tracker" \
    environment="$DEPLOYMENT_ENVIRONMENT" \
    managedBy="GitHub Actions" \
    instanceId="$INSTANCE_ID"
echo "✅ Resource group created"
