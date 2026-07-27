#!/usr/bin/env bash
set -e

if az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
  echo "Deleting resource group $RESOURCE_GROUP..."
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
else
  echo "Resource group $RESOURCE_GROUP already deleted."
fi
