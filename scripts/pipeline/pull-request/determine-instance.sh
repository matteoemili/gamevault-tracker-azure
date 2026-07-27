#!/usr/bin/env bash
set -e

INSTANCE_ID="pr${PR_NUMBER}"
RESOURCE_GROUP="rg-gamevault-${INSTANCE_ID}"
echo "instanceId=$INSTANCE_ID" >> "$GITHUB_OUTPUT"
echo "resourceGroup=$RESOURCE_GROUP" >> "$GITHUB_OUTPUT"
