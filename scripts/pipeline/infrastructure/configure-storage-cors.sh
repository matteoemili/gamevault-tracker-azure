#!/usr/bin/env bash
set -e

echo "🌐 Configuring CORS for Table Service..."
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Allowed Origin: $WEB_APP_URL"

az storage cors add \
  --account-name "$STORAGE_ACCOUNT" \
  --services t \
  --methods GET POST PUT DELETE OPTIONS PATCH \
  --origins "$WEB_APP_URL" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600

echo "✅ CORS configured successfully"
