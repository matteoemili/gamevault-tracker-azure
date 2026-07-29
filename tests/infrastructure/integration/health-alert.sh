#!/bin/bash
# T042: Checks that the origin-health alert includes an origin-group dimension.
# Run after a controlled origin failure has been sustained for five minutes.

set -u
set -o pipefail

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[health-alert] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${PLATFORM_RESOURCE_GROUP:?required}"
: "${PLATFORM_SUBSCRIPTION_ID:?required}"
: "${ROUTE_INSTANCE_ID:?required}"

alert=$(az monitor metrics alert show \
  --name 'gvt-origin-health-shared' \
  --resource-group "$PLATFORM_RESOURCE_GROUP" \
  --subscription "$PLATFORM_SUBSCRIPTION_ID" -o json)

window=$(echo "$alert" | jq -r '.windowSize // empty')
dimensions=$(echo "$alert" | jq -r '[.criteria.allOf[]?.dimensions[]?.name] | join(",")')
[ "$window" = "PT15M" ] || { echo "[health-alert] expected a fifteen-minute window, found ${window:-<none>}" >&2; exit 1; }
case ",$dimensions," in *,OriginGroup,*|*,originGroup,*) ;; *) echo "[health-alert] alert has no origin-group-identifying dimension" >&2; exit 1 ;; esac
echo "[health-alert] passed: ${ROUTE_INSTANCE_ID} is identified through the origin-group dimension" >&2