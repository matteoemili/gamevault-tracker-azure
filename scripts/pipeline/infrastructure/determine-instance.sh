#!/usr/bin/env bash
set -e

# Required environment: EVENT_NAME, INPUT_ENVIRONMENT, INPUT_INSTANCE_ID,
# PR_NUMBER, GITHUB_OUTPUT, GITHUB_ENV.
if [ "$EVENT_NAME" == "workflow_dispatch" ]; then
  ENVIRONMENT="$INPUT_ENVIRONMENT"
  INPUT_ID="$INPUT_INSTANCE_ID"
elif [ "$EVENT_NAME" == "pull_request" ]; then
  # PR instances currently use prod infrastructure with their own stable ID
  # until separate non-production platforms are enabled.
  ENVIRONMENT="prod"
  INPUT_ID="pr${PR_NUMBER}"
else
  ENVIRONMENT="prod"
  INPUT_ID=""
fi

echo "Environment: $ENVIRONMENT"

if [ -n "$INPUT_ID" ]; then
  INSTANCE_ID="$INPUT_ID"
  echo "♻️  Redeploying to existing instance: $INSTANCE_ID"
else
  INSTANCE_ID=$(openssl rand -hex 4)
  echo "🆕 Generated new instance ID: $INSTANCE_ID"
fi

RESOURCE_GROUP="rg-gamevault-${INSTANCE_ID}"

echo "instanceId=$INSTANCE_ID" >> "$GITHUB_OUTPUT"
echo "resourceGroup=$RESOURCE_GROUP" >> "$GITHUB_OUTPUT"
echo "environment=$ENVIRONMENT" >> "$GITHUB_OUTPUT"

echo "AZURE_RESOURCE_GROUP=$RESOURCE_GROUP" >> "$GITHUB_ENV"
echo "DEPLOYMENT_ENVIRONMENT=$ENVIRONMENT" >> "$GITHUB_ENV"
echo "INSTANCE_ID=$INSTANCE_ID" >> "$GITHUB_ENV"

if [ "$ENVIRONMENT" == "dev" ] || [ "$ENVIRONMENT" == "pr" ]; then
  echo "BICEP_PARAMS_FILE=infra/main.dev.bicepparam" >> "$GITHUB_ENV"
elif [ "$ENVIRONMENT" == "staging" ]; then
  echo "BICEP_PARAMS_FILE=infra/main.staging.bicepparam" >> "$GITHUB_ENV"
else
  echo "BICEP_PARAMS_FILE=infra/main.bicepparam" >> "$GITHUB_ENV"
fi
