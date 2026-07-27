#!/usr/bin/env bash
set -e

set +e
./scripts/instance-route.sh register \
  --instance-id "$INSTANCE_ID" \
  --instance-resource-group "$AZURE_RESOURCE_GROUP" \
  --static-web-app-name "$STATIC_WEB_APP" \
  --platform-resource-group "$PLATFORM_RESOURCE_GROUP" \
  --front-door-profile "$FRONT_DOOR_PROFILE" \
  --subscription-id "$(az account show --query id -o tsv)" \
  --environment "$DEPLOYMENT_ENVIRONMENT" \
  --origin-hostname "$STATIC_WEB_APP_ORIGIN_HOSTNAME" \
  --forwarding-config-file route-forwarding-gateway.json \
  > route-registration.json
REGISTER_RC=$?
set -e

if [ ! -s route-registration.json ] || ! jq -e \
  'type == "object" and (.status | type == "string") and
   (has("instance") and has("route") and has("diagnostics"))' \
  route-registration.json >/dev/null 2>&1; then
  printf '%s\n' '{"schemaVersion":"1.0","action":"register","status":"Failed","operationId":"unknown","instance":null,"route":null,"diagnostics":[{"code":"REGISTRATION_NO_RESULT","message":"Registration command failed without a valid result envelope"}]}' > route-registration.json
fi
ENDPOINT_URL="$(jq -r '.route.url // empty' route-registration.json 2>/dev/null || true)"
REGISTRATION_STATUS="$(jq -r '.status // empty' route-registration.json 2>/dev/null || true)"
if [ "$REGISTER_RC" -ne 0 ] || ! jq -e \
  --arg url "$ENDPOINT_URL" \
  '.status as $status |
   ($status == "Succeeded" or $status == "NoChange" or $status == "Degraded") and
   ($url | test("^https://[^[:space:]]+$")) and
   (.route.url == $url)' route-registration.json >/dev/null 2>&1; then
  jq --arg stage "Register" --arg file "route-registration.json" \
    --arg message "Registration failed or did not return an allowed HTTPS route URL" \
    '.stage = $stage | .status = "Failed" | .registrationResultFile = $file |
     .diagnostics = [{code:"REGISTRATION_FAILED",message:$message}]' \
    publication-result.json > publication-result.tmp
  mv publication-result.tmp publication-result.json
  exit 1
fi
jq --arg stage "Register" --arg file "route-registration.json" --arg url "$ENDPOINT_URL" \
  --arg status "$REGISTRATION_STATUS" \
  '.stage = $stage | .publishedUrl = $url | .registrationResultFile = $file |
   .diagnostics = [{code:("REGISTRATION_" + $status),message:("Route registration returned " + $status)}]' \
  publication-result.json > publication-result.tmp
mv publication-result.tmp publication-result.json
echo "endpointUrl=$ENDPOINT_URL" >> "$GITHUB_OUTPUT"
