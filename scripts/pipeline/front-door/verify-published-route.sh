#!/usr/bin/env bash
set -e

set +e
./scripts/instance-route.sh verify \
  --instance-id "$INSTANCE_ID" \
  --instance-resource-group "$AZURE_RESOURCE_GROUP" \
  --static-web-app-name "$STATIC_WEB_APP" \
  --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$FRONT_DOOR_PROFILE" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --expected-origin-hostname "$STATIC_WEB_APP_ORIGIN_HOSTNAME" \
  > route-verification.json
VERIFY_RC=$?
set -e

if [ ! -s route-verification.json ]; then
  printf '%s\n' '{"status":"Failed","diagnostics":[{"code":"EMPTY_VERIFICATION","message":"Verification produced no result"}]}' > route-verification.json
fi
jq --arg stage "Verify" --arg file "route-verification.json" \
  '.stage = $stage | .verificationResultFile = $file' \
  publication-result.json > publication-result.tmp
mv publication-result.tmp publication-result.json

if [ "$VERIFY_RC" -ne 0 ] || ! jq -e '.status == "Succeeded"' route-verification.json >/dev/null 2>&1; then
  VERIFY_STATUS="$(jq -r '.status // "Invalid"' route-verification.json 2>/dev/null || printf '%s' "Invalid")"
  FINAL_DIAGNOSTICS="$(jq -r '[.diagnostics[]? | (.code + ": " + .message)] | join("; ")' route-verification.json 2>/dev/null || true)"
  echo "::error::Front Door property validation failed with status $VERIFY_STATUS: ${FINAL_DIAGNOSTICS:-No valid diagnostics were returned}"
  jq --arg verifyStatus "$VERIFY_STATUS" \
    '.status = "Failed" | .diagnostics = [{code:"VERIFICATION_FAILED",message:("Verification returned " + $verifyStatus + " instead of Succeeded")}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  exit 1
fi
