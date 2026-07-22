# User Story 1 Integration Validation - Reach the Correct Instance

This document is the executable reference for validating User Story 1
("Reach the Correct Instance") independently of the not-yet-implemented
`scripts/instance-route.sh register` automation (User Story 2, T033-T035).
Every command below uses either `scripts/platform.sh` or a **direct Bicep
deployment** of `infra/platform/instance-route.bicep` against an already
deployed shared platform.

See also:
- [specs/001-multi-instance-platform/quickstart.md](../../../specs/001-multi-instance-platform/quickstart.md)
- [specs/001-multi-instance-platform/contracts/instance-route-cli.md](../../../specs/001-multi-instance-platform/contracts/instance-route-cli.md)
- [specs/001-multi-instance-platform/data-model.md](../../../specs/001-multi-instance-platform/data-model.md)

## Prerequisites

- Azure CLI logged in (`az login`) with access to the target subscription.
- Two existing application instances already deployed with `infra/main.bicep`
  (each producing a Static Web App), in resource groups referred to below as
  `$INSTANCE_RG_A` / `$INSTANCE_RG_B` with Static Web App names
  `$SWA_NAME_A` / `$SWA_NAME_B`.
- The shared platform already deployed once via `scripts/platform.sh deploy`
  (see quickstart.md Stage 3). Its resource group and Front Door profile
  name are referred to below as `$PLATFORM_RG` / `$FRONT_DOOR_PROFILE`.

```bash
export SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
export PLATFORM_RG="rg-gamevault-platform-dev"
export FRONT_DOOR_PROFILE="gvt-afd-dev"
export INSTANCE_RG_A="rg-gamevault-a1"
export SWA_NAME_A="swa-gamevault-dev-a1"
export INSTANCE_RG_B="rg-gamevault-b2"
export SWA_NAME_B="swa-gamevault-dev-b2"
```

## Step 1: Offline validation

```bash
bash tests/infrastructure/contracts/offline-validation.sh
bash tests/infrastructure/contracts/route-isolation.sh
bash tests/infrastructure/fixtures/generate-capacity-parameters.sh --count 25
```

All three must exit `0` before deploying anything.

## Step 2: Deploy the shared platform (if not already deployed)

```bash
./scripts/platform.sh validate --environment dev --local-only
./scripts/platform.sh deploy \
  --environment dev \
  --subscription-id "$SUBSCRIPTION_ID" \
  --resource-group "$PLATFORM_RG" \
  --location westeurope \
  --confirm | tee /tmp/gvt-platform.json | jq .
```

Capture the maintenance origin hostname for later steps:

```bash
export MAINTENANCE_HOST=$(jq -r '.platform.maintenanceOriginHostName' /tmp/gvt-platform.json 2>/dev/null || true)
```

(If `deploy` reports `NoChange`, that is expected and correct on repeat runs.)

## Step 3: Register instance A directly via Bicep (no CLI automation yet)

```bash
az deployment group create \
  --resource-group "$PLATFORM_RG" \
  --subscription "$SUBSCRIPTION_ID" \
  --name "instance-route-a1-$(date -u +%Y%m%dT%H%M%SZ)" \
  --template-file infra/platform/instance-route.bicep \
  --parameters instanceId=a1 environment=dev \
               frontDoorProfileName="$FRONT_DOOR_PROFILE" \
               instanceResourceGroupName="$INSTANCE_RG_A" \
               staticWebAppName="$SWA_NAME_A" \
  | tee /tmp/gvt-route-a1.json | jq .

export URL_A=$(jq -r '.properties.outputs.url.value' /tmp/gvt-route-a1.json)
```

## Step 4: Register instance B the same way

```bash
az deployment group create \
  --resource-group "$PLATFORM_RG" \
  --subscription "$SUBSCRIPTION_ID" \
  --name "instance-route-b2-$(date -u +%Y%m%dT%H%M%SZ)" \
  --template-file infra/platform/instance-route.bicep \
  --parameters instanceId=b2 environment=dev \
               frontDoorProfileName="$FRONT_DOOR_PROFILE" \
               instanceResourceGroupName="$INSTANCE_RG_B" \
               staticWebAppName="$SWA_NAME_B" \
  | tee /tmp/gvt-route-b2.json | jq .

export URL_B=$(jq -r '.properties.outputs.url.value' /tmp/gvt-route-b2.json)
```

## Step 5: Prove secure routing for each instance (T015)

```bash
bash tests/infrastructure/integration/secure-routing.sh --url "$URL_A"
bash tests/infrastructure/integration/secure-routing.sh --url "$URL_B"
```

## Step 6: Prove isolation between the two instances (T016)

Each instance's deployed content must contain a distinguishing marker
(e.g. render the instance ID or resource group name somewhere in the page
for test purposes). Substitute your actual markers below.

```bash
bash tests/infrastructure/integration/routing-isolation.sh \
  --url-a "$URL_A" --marker-a "instance:a1" \
  --url-b "$URL_B" --marker-b "instance:b2" \
  --repeat 5
```

## Step 7: Simulate failure and verify controlled unavailability (T017)

Temporarily stop or break instance A's Static Web App / origin (for example,
by deleting or renaming its custom domain binding, or by pointing the route
at a deliberately wrong hostname in a throwaway test deployment). Then:

```bash
bash tests/infrastructure/integration/controlled-unavailability.sh \
  --url "$URL_A" --foreign-marker "instance:b2"
```

This must show either Front Door's native error response or the shared
maintenance page - **never** instance B's marker.

To exercise the optional maintenance-origin fallback path instead of the
native Front Door error, redeploy instance A's route with
`enableMaintenanceFallback=true` and `maintenanceOriginHostName="$MAINTENANCE_HOST"`,
then upload `infra/platform/assets/maintenance/index.html` to the shared
maintenance storage account's `maintenance` container before simulating the
failure again.

## Step 8: Capacity check (T018, offline only)

```bash
bash tests/infrastructure/fixtures/generate-capacity-parameters.sh \
  --base-name gvt --environment dev --count 25 --out /tmp/gvt-capacity-fixture.json
```

Confirms the deterministic naming scheme produces 25 unique endpoint,
origin-group, origin, and route names before ever attempting a 25-instance
deployment.

## Acceptance Summary for User Story 1

User Story 1 is independently deployable and passes when:

- [ ] `tests/infrastructure/contracts/route-isolation.sh` passes (static).
- [ ] `tests/infrastructure/fixtures/generate-capacity-parameters.sh --count 25` passes (static).
- [ ] Both instances deploy via direct `infra/platform/instance-route.bicep`
      invocation with distinct, deterministic resource names.
- [ ] `tests/infrastructure/integration/secure-routing.sh` passes for both instances.
- [ ] `tests/infrastructure/integration/routing-isolation.sh` passes for both instances.
- [ ] `tests/infrastructure/integration/controlled-unavailability.sh` passes after
      simulating a failure on one instance, without ever exposing the other
      instance's content.

No lifecycle automation (`scripts/instance-route.sh register/unregister`) is
required to satisfy User Story 1 - that automation is delivered by User
Story 2 (T033-T035).
