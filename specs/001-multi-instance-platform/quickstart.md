# Quickstart: Incremental Platform Validation

This guide is the target operator workflow. Commands become available during implementation; each stage is a promotion gate and uses the contracts in [contracts/](contracts/).

## Prerequisites

- Azure CLI with Bicep, `jq`, and `curl`
- An Azure subscription where you can create a dedicated shared resource group
- Two existing GameVault instances with different visible test data
- An interactive Azure login for local execution

```bash
az login
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --query '{id:id, tenantId:tenantId, user:user.name}' --output json
```

Set non-secret local inputs:

```bash
export ENVIRONMENT=dev
export LOCATION=westeurope
export PLATFORM_RG=rg-gamevault-platform-dev
export PLATFORM_PROFILE=afd-gamevault-dev
export INSTANCE_A=dev00001
export INSTANCE_A_RG=rg-gamevault-dev00001
export INSTANCE_A_SWA=swa-gamevault-dev-dev00001
```

## 1. Offline Validation

```bash
az bicep build --file infra/platform/main.bicep --stdout >/dev/null
az bicep build --file infra/platform/modules/instance-route.bicep --stdout >/dev/null
./scripts/platform.sh validate --local-only --environment "$ENVIRONMENT"
```

Expected: all commands exit zero, create no Azure resources, and report no unresolved parameters or linter errors.

## 2. Azure Validation and Preview

```bash
./scripts/platform.sh validate \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$PLATFORM_RG" \
  --location "$LOCATION" | jq .

./scripts/platform.sh what-if \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$PLATFORM_RG" \
  --location "$LOCATION" | tee /tmp/gamevault-platform-what-if.json | jq .
```

Expected: validation passes; preview contains only shared platform resources and no instance resource-group changes.

## 3. Deploy the Shared Platform

```bash
./scripts/platform.sh deploy \
  --environment "$ENVIRONMENT" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$PLATFORM_RG" \
  --location "$LOCATION" \
  --confirm | tee /tmp/gamevault-platform.json | jq .
```

Run the same command again, then run `what-if` again.

Expected: stable resource IDs, no duplicate resources, WAF in detection mode, diagnostics enabled, endpoint capacity reported as 25, and an empty post-deployment what-if.

## 4. Register One Instance

```bash
./scripts/instance-route.sh register \
  --instance-id "$INSTANCE_A" \
  --instance-resource-group "$INSTANCE_A_RG" \
  --static-web-app-name "$INSTANCE_A_SWA" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --confirm | tee /tmp/gamevault-route-a.json | jq .

INSTANCE_A_URL=$(jq -r '.route.url' /tmp/gamevault-route-a.json)
curl --fail --silent --show-error --location "$INSTANCE_A_URL/" >/dev/null

./scripts/instance-route.sh verify \
  --instance-id "$INSTANCE_A" \
  --instance-resource-group "$INSTANCE_A_RG" \
  --static-web-app-name "$INSTANCE_A_SWA" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" | jq .
```

Expected: the output contains a stable Azure-provided `https://*.azurefd.net` URL, HTTPS succeeds, and all route association checks pass. Repeating registration returns `NoChange` with the same URL.

## 5. Prove Isolation

Register a second distinguishable instance using the same command with its own ID, group, and Static Web App. Then run the infrastructure integration tests:

```bash
tests/infrastructure/integration/routing-isolation.sh \
  --first-url "$INSTANCE_A_URL" \
  --second-url "$INSTANCE_B_URL"
```

Expected: each URL always returns its own fixture marker. Disabling or breaking instance A never returns instance B content; it returns a controlled unavailable response. Instance B remains healthy.

## 6. Harden and Observe

Apply the generated Front Door ID and endpoint hostname to each Static Web App forwarding-gateway configuration only after Stage 5 passes. Redeploy the app and rerun verification.

Expected: direct `azurestaticapps.net` requests are denied, Front Door requests succeed, access/WAF/health logs appear in the shared workspace, and a sustained synthetic origin failure raises an instance-specific alert within five minutes. Review WAF detections before promoting the policy to prevention mode.

## 7. Deregister Safely

```bash
./scripts/instance-route.sh unregister \
  --instance-id "$INSTANCE_A" \
  --instance-resource-group "$INSTANCE_A_RG" \
  --static-web-app-name "$INSTANCE_A_SWA" \
  --platform-resource-group "$PLATFORM_RG" \
  --front-door-profile "$PLATFORM_PROFILE" \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --confirm | jq .
```

Expected: only instance A's endpoint, route, origin group, and origin are removed. Instance B and the shared platform remain unchanged. Repeating unregister returns `NoChange`.

## 8. Promote to CI/CD

After all stages pass locally, the pipeline calls these exact commands in order:

```text
offline validate -> Azure validate -> what-if artifact -> approval -> deploy/register -> verify
```

Use GitHub OpenID Connect federation, environment approvals for shared-platform mutation, and a concurrency key containing the environment and instance ID. Do not duplicate the lifecycle logic in workflow YAML.