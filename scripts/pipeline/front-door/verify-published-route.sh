#!/usr/bin/env bash
set -e

set +e
ATTEMPT=1
MAX_ATTEMPTS=20
VERIFY_DEADLINE=$((SECONDS + 600))
VERIFIED=false
while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ] && [ "$SECONDS" -lt "$VERIFY_DEADLINE" ]; do
  TMP_VERIFICATION="route-verification.json.tmp"
  ./scripts/instance-route.sh verify \
    --instance-id "$INSTANCE_ID" \
    --instance-resource-group "$AZURE_RESOURCE_GROUP" \
    --static-web-app-name "$STATIC_WEB_APP" \
    --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
    --front-door-profile "$FRONT_DOOR_PROFILE" \
    --subscription-id "$SUBSCRIPTION_ID" \
    --expected-origin-hostname "$STATIC_WEB_APP_ORIGIN_HOSTNAME" \
    > "$TMP_VERIFICATION"
  VERIFY_RC=$?
  if [ -s "$TMP_VERIFICATION" ]; then
    mv "$TMP_VERIFICATION" route-verification.json
  else
    printf '%s\n' '{"status":"Failed","diagnostics":[{"code":"EMPTY_VERIFICATION","message":"Verification produced no result"}]}' > route-verification.json
  fi
  jq --arg stage "Verify" --arg file "route-verification.json" \
    '.stage = $stage | .verificationResultFile = $file' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  if [ "$VERIFY_RC" -eq 0 ] && jq -e '.status == "Succeeded"' route-verification.json >/dev/null 2>&1; then
    VERIFIED=true
    break
  fi
  VERIFY_STATUS="$(jq -r '.status // "Invalid"' route-verification.json 2>/dev/null || printf '%s' "Invalid")"
  jq -r --arg attempt "$ATTEMPT" \
    '.diagnostics[]? | "::warning::Front Door verification attempt \($attempt): \(.code): \(.message)"' \
    route-verification.json 2>/dev/null || \
    echo "::warning::Front Door verification attempt $ATTEMPT returned an invalid result"
  if [ "$VERIFY_STATUS" = "Failed" ] || [ "$ATTEMPT" -eq "$MAX_ATTEMPTS" ] || [ "$SECONDS" -ge "$VERIFY_DEADLINE" ]; then
    break
  fi
  case "$ATTEMPT" in
    1) sleep 5 ;;
    2) sleep 10 ;;
    3) sleep 20 ;;
    4) sleep 30 ;;
    *) sleep 60 ;;
  esac
  ATTEMPT=$((ATTEMPT + 1))
done
if [ "$VERIFIED" != "true" ]; then
  VERIFY_STATUS="$(jq -r '.status // "Invalid"' route-verification.json 2>/dev/null || printf '%s' "Invalid")"
  FINAL_DIAGNOSTICS="$(jq -r '[.diagnostics[]? | (.code + ": " + .message)] | join("; ")' route-verification.json 2>/dev/null || true)"
  echo "::error::Front Door verification failed after $ATTEMPT attempt(s) with status $VERIFY_STATUS: ${FINAL_DIAGNOSTICS:-No valid diagnostics were returned}"
  jq --arg attempts "$ATTEMPT" --arg verifyStatus "$VERIFY_STATUS" \
    '.status = "Failed" | .diagnostics = [{code:"VERIFICATION_FAILED",message:("Verification returned " + $verifyStatus + " and did not return Succeeded within the bounded retry window (attempt " + $attempts + ")")}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  exit 1
fi
