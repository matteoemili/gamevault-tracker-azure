#!/usr/bin/env bash
set -e

echo "🔧 Configuring Static Web App application settings..."
az staticwebapp appsettings set \
  --name "$STATIC_WEB_APP" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --setting-names \
    VITE_AZURE_STORAGE_ACCOUNT_NAME="$VITE_AZURE_STORAGE_ACCOUNT_NAME" \
    VITE_AZURE_STORAGE_SAS_TOKEN="$VITE_AZURE_STORAGE_SAS_TOKEN" \
    VITE_AZURE_GAMES_TABLE_NAME="$VITE_AZURE_GAMES_TABLE_NAME" \
    VITE_AZURE_CATEGORIES_TABLE_NAME="$VITE_AZURE_CATEGORIES_TABLE_NAME"
echo "✅ Application settings configured"
