# Quickstart: Shared Entry Scale Validation

This guide defines the target operator validation sequence. Commands become available during implementation. Use a disposable development environment for live tests.

## Prerequisites

- Node.js 20+
- Azure CLI with Bicep, `jq`, and `curl`
- An Azure subscription with rights to deploy the shared service and platform
- Operator and deployment principals whose object IDs can receive `Storage Table Data Contributor` on the shared storage account
- Optional: two existing legacy GameVault instances for coexistence validation

```bash
az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

export ENVIRONMENT=dev
export LOCATION=westeurope
export SHARED_RG=rg-gamevault-shared-dev
export PLATFORM_RG=rg-gamevault-platform-dev
export PLATFORM_PROFILE=gvt-afd-dev
```

## 1. Offline Validation

```bash
npm install
npm run build
az bicep build --file infra/shared/main.bicep --stdout >/dev/null
az bicep build --file infra/platform/main.bicep --stdout >/dev/null
bash tests/infrastructure/contracts/offline-validation.sh
```

Expected: all builds and contracts pass without Azure mutation. The workflow contract rejects per-instance resource creation and route registration on the shared path.

## 2. Validate and Preview

```bash
./scripts/shared-service.sh validate \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RG" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" \
  --location "$LOCATION" | jq .

./scripts/shared-service.sh what-if \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RG" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" \
  --location "$LOCATION" | tee /tmp/shared-what-if.json | jq .
```

Expected: preview contains one shared Standard application/storage deployment, Table data-role assignments, and one dedicated shared profile/route. It contains no legacy deletion and no per-instance resource.

## 3. Deploy the Shared Service

```bash
./scripts/shared-service.sh deploy \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RG" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" \
  --location "$LOCATION" \
  --confirm | tee /tmp/shared-deployment.json | jq .

SHARED_URL=$(jq -r '.sharedService.publicUrl' /tmp/shared-deployment.json)
curl --fail --silent --show-error --location "$SHARED_URL/" >/dev/null
```

Run the same deploy command again, then run `what-if` again.

On the first deployment, the command reports `BootstrapPending` after the unrestricted upload and route verification. Generate the forwarding-gateway configuration, rebuild, upload again, and rerun verification as directed by the command output. Later deployments include the known restriction in their single application upload.

Expected: the same public URL and resource IDs are returned; post-deployment what-if is empty; no duplicate profile, endpoint, route, origin group, origin, SWA, or storage account exists.

## 4. Verify Shared Routing and Protection

```bash
./scripts/shared-service.sh verify \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group "$SHARED_RG" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" | jq .

tests/infrastructure/integration/shared-controlled-unavailability.sh
tests/infrastructure/integration/shared-auth-cache-bypass.sh
```

Expected: HTTPS redirect, WAF association, shared origin host/header, controlled unavailability, and `/.auth/*` no-cache/no-path-rewrite behavior all pass. Redirect-host behavior is not asserted until the later identity/custom-domain feature. After the bootstrap second upload applies forwarding restrictions, direct-origin access is denied while `$SHARED_URL` remains healthy.

## 5. Manage Logical Instances

Resolve shared storage outputs:

```bash
SHARED_STORAGE_ACCOUNT=$(
  az deployment group show \
    --resource-group "$SHARED_RG" \
    --name "gamevault-shared-$ENVIRONMENT" \
    --query properties.outputs.storageAccountName.value \
    --output tsv
)
```

Create and inspect one logical instance:

```bash
./scripts/logical-instance.sh create \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --storage-account-name "$SHARED_STORAGE_ACCOUNT" \
  --logical-instance-id Demo-User \
  --display-name "Demo User" | tee /tmp/logical-instance.json | jq .

./scripts/logical-instance.sh show \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --storage-account-name "$SHARED_STORAGE_ACCOUNT" \
  --logical-instance-id demo-user | jq .
```

Expected: the ID and namespace are `demo-user`. Repeating create returns `NoChange`; no Azure resource inventory changes.

## 6. Prove 10,000-Instance Constant Scale

Use only the disposable development registry:

```bash
tests/infrastructure/fixtures/generate-logical-instances.sh 10000 \
  > /tmp/logical-instances-10000.jsonl

export RUN_AZURE_INTEGRATION=1
export SHARED_RESOURCE_GROUP="$SHARED_RG"
export SHARED_STORAGE_ACCOUNT="$SHARED_STORAGE_ACCOUNT"
export PLATFORM_RESOURCE_GROUP="$PLATFORM_RG"
export PLATFORM_FRONT_DOOR_PROFILE="$PLATFORM_PROFILE"

./scripts/logical-instance.sh bulk-create \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --storage-account-name "$SHARED_STORAGE_ACCOUNT" \
  --input-jsonl /tmp/logical-instances-10000.jsonl \
  --confirm | tee /tmp/logical-instances-import.json | jq .

tests/infrastructure/integration/constant-resource-scale.sh
```

Expected: batched import completes within the CI time budget, 10,000 unique reservations exist across deterministic metadata partitions, duplicate/conflict tests pass, and before/after IDs and counts for SWAs, resource groups, Front Door profiles, endpoints, routes, groups, and origins are identical.

## 7. Prove Legacy Coexistence

With two disposable or approved legacy instances configured:

```bash
export LEGACY_A_URL=https://first-example.azurefd.net
export LEGACY_B_URL=https://second-example.azurefd.net
tests/infrastructure/integration/legacy-coexistence.sh
```

Expected: deploying, verifying, and rolling back the shared service changes no legacy resource ID or public response. The test never unregisters or deletes a legacy instance.

## 8. Validate the Delivery Workflow

Open a pull request and confirm it builds and runs offline contracts without creating a resource group, SWA, storage account, endpoint, or route. Merge or manually dispatch a development deployment and confirm:

```text
offline validation -> Azure validate -> what-if -> shared infra -> app upload
-> shared route -> CORS -> verify -> forwarding restriction -> artifacts
```

Expected: the workflow summary reports one stable shared URL. Repeating the workflow twenty times produces no duplicate shared resources.

## 9. Rollback

Rollback application code through the same shared deployment path. Do not delete the shared route before restoring a verified prior SWA deployment. Do not run legacy unregister or cleanup commands as part of shared rollback.

If the new shared path must be paused, leave legacy resources untouched and disable only the new shared workflow trigger until diagnosis is complete.
