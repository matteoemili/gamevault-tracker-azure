#!/usr/bin/env bash
set -e

echo "🚀 Deploying infrastructure..."
echo "Instance ID: $INSTANCE_ID"
echo "Environment: $DEPLOYMENT_ENVIRONMENT"
echo "Resource Group: $AZURE_RESOURCE_GROUP"
echo "Params File: $BICEP_PARAMS_FILE"

DEPLOYMENT_OUTPUT=$(az deployment group create \
  --name "gamevault-${GITHUB_RUN_NUMBER}" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters "$BICEP_PARAMS_FILE" \
  --parameters "instanceId=$INSTANCE_ID" \
  --query 'properties.outputs' \
  --output json)

echo "📊 Deployment outputs:"
echo "$DEPLOYMENT_OUTPUT" | jq '.'

echo "instanceId=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.instanceId.value')" >> "$GITHUB_OUTPUT"
echo "storageAccountName=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.storageAccountName.value')" >> "$GITHUB_OUTPUT"
echo "staticWebAppName=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.staticWebAppName.value')" >> "$GITHUB_OUTPUT"
echo "staticWebAppDefaultHostname=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.staticWebAppDefaultHostname.value')" >> "$GITHUB_OUTPUT"
echo "staticWebAppUrl=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.staticWebAppUrl.value')" >> "$GITHUB_OUTPUT"
echo "gamesTableName=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.gamesTableName.value')" >> "$GITHUB_OUTPUT"
echo "categoriesTableName=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.categoriesTableName.value')" >> "$GITHUB_OUTPUT"

echo "✅ Infrastructure deployed successfully"
