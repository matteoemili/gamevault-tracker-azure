#!/bin/bash
# Verify the shared route and fail unless the CLI reports Succeeded.
# Bash 3.2 compatible.

set -u
set -o pipefail

RESULT_FILE="${SHARED_PUBLICATION_RESULT_FILE:-shared-publication-result.json}"
ENVIRONMENT_NAME="${DEPLOYMENT_ENVIRONMENT:-${ENVIRONMENT:-}}"
BASE_NAME="${BASE_NAME:-gvt}"

set +e
./scripts/shared-service.sh verify \
  --environment "$ENVIRONMENT_NAME" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RESOURCE_GROUP" \
  --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$FRONT_DOOR_PROFILE" \
  --base-name "$BASE_NAME" \
  > shared-route-verification.json
VERIFY_RC=$?
set -e

if [ ! -s shared-route-verification.json ]; then
  printf '%s\n' '{"schemaVersion":"1.0","action":"verify","status":"Failed","operationId":"unknown","sharedService":null,"diagnostics":[{"code":"EMPTY_SHARED_VERIFICATION","message":"Shared route verification produced no result"}]}' > shared-route-verification.json
fi

jq '.stage = "Verify" | .verificationResultFile = "shared-route-verification.json"' \
  "$RESULT_FILE" > shared-publication-result.tmp
mv shared-publication-result.tmp "$RESULT_FILE"

if [ "$VERIFY_RC" -ne 0 ] || ! jq -e '.status == "Succeeded"' shared-route-verification.json >/dev/null 2>&1; then
  VERIFY_STATUS="$(jq -r '.status // "Invalid"' shared-route-verification.json 2>/dev/null || echo Invalid)"
  echo "::error::Shared route verification failed with status $VERIFY_STATUS"
  jq --arg verifyStatus "$VERIFY_STATUS" \
    '.status = "Failed" |
     .diagnostics = [{code:"SHARED_VERIFICATION_FAILED",message:("Verification returned " + $verifyStatus + " instead of Succeeded")}]' \
    "$RESULT_FILE" > shared-publication-result.tmp
  mv shared-publication-result.tmp "$RESULT_FILE"
  exit 1
fi
