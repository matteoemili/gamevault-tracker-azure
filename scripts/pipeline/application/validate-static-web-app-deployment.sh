#!/usr/bin/env bash
set -e

EXPECTED_URL="https://${STATIC_WEB_APP_DEFAULT_HOSTNAME}"
DEPLOYED_URL="${DEPLOYED_URL%/}"
DEPLOYED_HOSTNAME="${DEPLOYED_URL#https://}"
if [ "$EVENT_NAME" = "pull_request" ]; then
  DEFAULT_SUBDOMAIN="${STATIC_WEB_APP_DEFAULT_HOSTNAME%%.*}"
  case "$DEPLOYED_HOSTNAME" in
    "${DEFAULT_SUBDOMAIN}-${PR_NUMBER}."*.azurestaticapps.net) ;;
    *)
      echo "::error::Static Web Apps deployed PR $PR_NUMBER to unexpected URL '${DEPLOYED_URL:-<empty>}'."
      exit 1
      ;;
  esac
elif [ "$DEPLOYED_URL" != "$EXPECTED_URL" ]; then
  echo "::error::Static Web Apps deployed to '${DEPLOYED_URL:-<empty>}' instead of the production URL '$EXPECTED_URL'."
  exit 1
fi
echo "deployedHostname=$DEPLOYED_HOSTNAME" >> "$GITHUB_OUTPUT"
echo "Static Web App deployment confirmed: $DEPLOYED_URL"
