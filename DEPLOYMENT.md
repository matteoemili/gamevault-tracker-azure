# Production Deployment Guide - Azure Static Web Apps

## 🎯 Multi-Instance Deployment Support

**This application now supports multiple isolated instances**, each with its own:
- ✅ Dedicated resource group
- ✅ Unique instance identifier
- ✅ Isolated Azure resources (Storage Account, Static Web App)
- ✅ Independent data storage
- ✅ Ability to redeploy to existing instances

## ✅ Automated CI/CD Deployment

**This application uses a fully automated CI/CD pipeline.** Environment variables are automatically injected during the build process:

- ✅ SAS tokens are **generated automatically** from infrastructure deployment
- ✅ Storage account names are **passed dynamically** from Bicep outputs
- ✅ CORS settings are **automatically configured** for the deployed Static Web App URL
- ✅ **No manual GitHub secrets management required**
- ✅ Instance IDs are **generated or reused** automatically

### How It Works

1. **Instance Management**: Generates unique instance ID or uses provided ID for redeployment
2. **Resource Group Creation**: Creates isolated resource group per instance
3. **Infrastructure Job**: Deploys Azure resources (storage account, static web app, tables)
4. **Build Job**: Generates fresh SAS token and builds the application with injected variables
5. **CORS Configuration**: Automatically adds the Static Web App URL to storage CORS rules

Vite environment variables are **baked into the JavaScript bundle at BUILD time**, not runtime.

## 🚀 Deployment Options

### Option 1: Automatic Push-Based Deployment (Default)

Simply push your code to the `main` branch to deploy a new instance:

```bash
git add .
git commit -m "Your changes"
git push origin main
```

**Result**: 
- A new instance ID is automatically generated (8 random alphanumeric characters)
- New resource group created: `rg-gamevault-{instanceId}`
- All resources deployed with unique names

### Option 2: Manual Workflow Dispatch (New Instance)

Create a new instance on demand via GitHub Actions UI:

1. Go to **Actions** tab in GitHub
2. Select **Azure Static Web Apps CI/CD** workflow
3. Click **Run workflow**
4. Select environment (prod/dev/staging)
5. Leave **Instance ID** empty for new instance
6. Click **Run workflow**

**Result**: New instance created with random ID

### Option 3: Manual Workflow Dispatch (Redeploy Existing)

Redeploy to an existing instance:

1. Go to **Actions** tab in GitHub
2. Select **Azure Static Web Apps CI/CD** workflow
3. Click **Run workflow**
4. Select environment
5. **Enter the Instance ID** from previous deployment (e.g., `abc12345`)
6. Click **Run workflow**

**Result**: Updates existing instance with new code

## 📋 Instance Management

### Finding Your Instance ID

After deployment completes, check the workflow logs for:

```
🎉 Deployment Complete!
================================================

📋 Instance Details:
  Instance ID:     abc12345
  Resource Group:  rg-gamevault-abc12345
  Environment:     prod

🌐 Resources:
  Static Web App:  swa-gamevault-prod-abc12345
  Storage Account: stgamevaultabc12345
  Web App URL:     https://swa-gamevault-prod-abc12345.azurestaticapps.net

♻️  To redeploy to this instance:
  Use Instance ID: abc12345
```

### Viewing Instances in Azure Portal

All instances are tagged with their instance ID:

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to **Resource Groups**
3. Look for groups starting with `rg-gamevault-`
4. Check the `instanceId` tag on each resource group

### Listing Instances via CLI

```bash
# List all GameVault resource groups
az group list \
  --query "[?starts_with(name, 'rg-gamevault-')].{Name:name, InstanceId:tags.instanceId, Environment:tags.environment}" \
  --output table

# Get details for a specific instance
INSTANCE_ID="abc12345"
az group show \
  --name "rg-gamevault-$INSTANCE_ID" \
  --output table
```

## 🔄 Managing Multiple Instances

### Use Cases

1. **Multiple Environments**: Deploy separate dev, staging, and production instances
2. **Feature Branches**: Create isolated instances for testing new features
3. **Team Members**: Each developer can have their own instance
4. **A/B Testing**: Run multiple versions simultaneously
5. **Customer Demos**: Create dedicated demo instances

### Example Workflow

```bash
# Deploy development instance
# Via GitHub UI: Run workflow with environment=dev, empty instance ID
# Result: Creates rg-gamevault-dev1234

# Deploy production instance  
# Via push to main or manual workflow with environment=prod
# Result: Creates rg-gamevault-prod5678

# Update development instance
# Via GitHub UI: Run workflow with environment=dev, instance_id=dev1234
# Result: Updates existing rg-gamevault-dev1234

# Deploy feature testing instance
# Via GitHub UI: Run workflow with environment=dev, empty instance ID
# Result: Creates rg-gamevault-feat9abc
```

## 🧹 Cleanup and Resource Management

### Deleting an Instance

To completely remove an instance and all its resources:

```bash
# Via Azure Portal
# 1. Go to Resource Groups
# 2. Select the instance resource group (e.g., rg-gamevault-abc12345)
# 3. Click "Delete resource group"
# 4. Type the resource group name to confirm
# 5. Click Delete

# Via Azure CLI
INSTANCE_ID="abc12345"
az group delete \
  --name "rg-gamevault-$INSTANCE_ID" \
  --yes \
  --no-wait
```

### Cost Estimation per Instance

Each instance uses:
- **Storage Account**: ~$0.01-0.10/month (Standard LRS, minimal data)
- **Static Web App**: Free tier (no cost)
- **Table Storage**: ~$0.05/10,000 transactions

**Total estimated cost per instance**: < $1/month for typical usage

## 🔐 Security Consideration

### ⚠️ DO NOT USE ACCOUNT KEYS IN PRODUCTION

**Account keys provide FULL access to your storage account** and should NEVER be in client-side code. Always use SAS tokens with:
- ✅ Limited permissions (only Table Read/Write/Delete)
- ✅ Expiration date (rotate regularly)
- ✅ Revocable without changing account keys

## 📝 Infrastructure Details

### Resource Naming Convention

For instance ID `abc12345`:

| Resource Type | Name Format | Example |
|--------------|-------------|---------|
| Resource Group | `rg-gamevault-{instanceId}` | `rg-gamevault-abc12345` |
| Storage Account | `stgamevault{instanceId}` | `stgamevaultabc12345` |
| Static Web App | `swa-gamevault-{env}-{instanceId}` | `swa-gamevault-prod-abc12345` |
| Games Table | `games` | `games` |
| Categories Table | `categories` | `categories` |

### Tags Applied to Resources

```json
{
  "application": "GameVault Tracker",
  "environment": "prod|dev|staging",
  "managedBy": "Bicep",
  "instanceId": "abc12345"
}
```

## 🛠️ Advanced Configuration

### Custom Instance ID

You can specify a custom instance ID (useful for memorable names):

1. In GitHub Actions UI, enter a custom instance ID (8 characters max, lowercase alphanumeric)
2. Example: `demo`, `test01`, `prod`

**Note**: Use the same ID to redeploy to that instance

### Environment-Specific Parameters

Edit parameter files for different configurations:

```bash
# Production: infra/main.bicepparam
param environment = 'prod'
param staticWebAppSku = 'Free'

# Development: infra/main.dev.bicepparam
param environment = 'dev'
param staticWebAppSku = 'Free'

# Staging: infra/main.staging.bicepparam (create if needed)
param environment = 'staging'
param staticWebAppSku = 'Standard'
```

### Required GitHub Secrets

Only one secret is required for the entire pipeline:

- **`AZURE_CREDENTIALS_SPONSORSHIP`**: Azure service principal credentials for authentication

All other configuration is handled automatically per instance!

## 🧪 Testing Deployment

After deployment completes:

1. Visit the Static Web App URL from deployment logs
2. Open browser Developer Tools (F12)
3. Go to Console tab
4. Add a game and watch for logs:
   ```
   [Azure] Loading data from table: games
   [Azure] Saving 1 items to table: games
   [Azure] Successfully saved data to games
   ```
5. Refresh the page - game should persist

## 🐛 Troubleshooting

### Issue: "Cannot find instance ID from previous deployment"

**Solution**: Check GitHub Actions logs or Azure Portal tags to find the instance ID

### Issue: "Resource group already exists"

**Solution**: This is normal for redeployment - the workflow updates existing resources

### Issue: "CORS policy blocked" in production

**Cause**: Production domain not in CORS settings

**Fix**: CORS is configured automatically, but if issues persist:
```bash
INSTANCE_ID="abc12345"
STORAGE_ACCOUNT="stgamevault$INSTANCE_ID"
WEB_APP_URL="https://swa-gamevault-prod-$INSTANCE_ID.azurestaticapps.net"

az storage cors add \
  --account-name "$STORAGE_ACCOUNT" \
  --services t \
  --methods GET POST PUT DELETE OPTIONS PATCH \
  --origins "$WEB_APP_URL" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600
```

### Issue: Data not persisting

**Check**:
1. Verify SAS token is valid (check deployment logs)
2. Confirm CORS is configured correctly
3. Check browser console for errors

## 📊 Monitoring Multiple Instances

### View All Instances

```bash
# List all resource groups
az group list \
  --query "[?starts_with(name, 'rg-gamevault-')].{Name:name, InstanceId:tags.instanceId, Env:tags.environment, Location:location}" \
  --output table

# Get costs per instance
az consumption usage list \
  --start-date 2024-01-01 \
  --end-date 2024-01-31 \
  --query "[?contains(instanceName, 'gamevault')]" \
  --output table
```

### Health Checks

```bash
# Check Static Web App status for an instance
INSTANCE_ID="abc12345"
RESOURCE_GROUP="rg-gamevault-$INSTANCE_ID"

az staticwebapp show \
  --name "swa-gamevault-prod-$INSTANCE_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --query "{Name:name, Status:sku.name, URL:defaultHostname}" \
  --output table
```

## 📚 Additional Resources

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/azure/static-web-apps/)
- [Azure Table Storage Documentation](https://docs.microsoft.com/azure/storage/tables/)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)

---

**Last Updated**: 2026-01-06  
**Platform**: Azure Static Web Apps  
**Framework**: Vite + React  
**Multi-Instance Support**: ✅ Enabled

## Shared Entry Platform Operations

Deploy the shared platform before registering an instance route. The lifecycle
has explicit rollback boundaries: `validate` and `what-if` do not mutate Azure,
an unsuccessful registration preserves the active route, and `unregister`
touches only an endpoint with matching ownership tags.

```bash
./scripts/platform.sh validate --environment prod --subscription-id "$AZURE_SUBSCRIPTION_ID" --resource-group "$PLATFORM_RG" --location "$LOCATION" | jq .
./scripts/platform.sh what-if --environment prod --subscription-id "$AZURE_SUBSCRIPTION_ID" --resource-group "$PLATFORM_RG" | jq .
./scripts/platform.sh deploy --environment prod --subscription-id "$AZURE_SUBSCRIPTION_ID" --resource-group "$PLATFORM_RG" --location "$LOCATION" --confirm | jq .
```

Expected platform outputs include `frontDoorProfileId`, `frontDoorId`,
`workspaceId`, `wafPolicyId`, `endpointCapacity`, and `budgetId`. Register and
verify each instance with `scripts/instance-route.sh`; route commands emit one
redacted JSON result to stdout and write diagnostics to stderr.

For a failed route deployment, rerun the same `register` command after fixing
the reported preflight issue. For a retired instance, first run `status`, then
run `unregister --confirm`, and finally confirm the sibling URLs remain healthy.
Use [specs/001-multi-instance-platform/quickstart.md](specs/001-multi-instance-platform/quickstart.md) for the complete commands and [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md) for topology and service limits.

## Automatic Front Door Publication

The `publish_front_door` job in `.github/workflows/ci-cd.yml` publishes a
successful instance without manual route changes. Configure these **repository
variables** (values are environment-specific and must not contain secrets):

| Environment | Platform resource group | Front Door profile |
|---|---|---|
| `dev` | `GAMEVAULT_PLATFORM_RESOURCE_GROUP_DEV` | `GAMEVAULT_FRONT_DOOR_PROFILE_DEV` |
| `staging` | `GAMEVAULT_PLATFORM_RESOURCE_GROUP_STAGING` | `GAMEVAULT_FRONT_DOOR_PROFILE_STAGING` |
| `prod` | `GAMEVAULT_PLATFORM_RESOURCE_GROUP_PROD` | `GAMEVAULT_FRONT_DOOR_PROFILE_PROD` |

The workflow resolves and validates the selected pair before any route
mutation. The values must identify the existing shared platform and must not
equal the instance resource group. The profile is normally named
`gvt-afd-{environment}`, but the configured value is authoritative; do not
construct or discover it by convention.

### Publication ordering

For persistent push, pull-request, and manual-dispatch deployments, the
publication phase runs only after both infrastructure and Static Web App
upload succeed:

1. Initialize and validate `publication-result.json`.
2. Register/update the instance with `scripts/instance-route.sh register`.
3. Add the verified route origin to Table Storage CORS with
   `scripts/cors-add-origin.sh` (idempotently).
4. Run `scripts/instance-route.sh verify` once to validate the deployed Azure
   Front Door control-plane properties; only `Succeeded` completes publication.
5. Report the HTTPS Front Door URL and retain sanitized results.

Registration is serialized per environment/profile with
`cancel-in-progress: false` because shared WAF associations are
read-modify-write. Infrastructure and application jobs for different
instances remain independently concurrent. A failed publication does not
roll back the deployed instance; it leaves the origin available for diagnosis
and retry.

### Verified URL and diagnostic artifacts

On success, the verified URL is written to the GitHub Actions job summary as
`Published Front Door URL` and exposed as the `publishedUrl` job output. The
`if: always()` upload creates artifact `route-registration-<instance-id>` from
the workflow workspace root:

- `publication-result.json` — always initialized and retained;
- `route-registration.json` — registration envelope, including valid CLI
  failures;
- `route-verification.json` — deterministic control-plane verification result,
  when verification ran;
- `route-forwarding-gateway.json` — generated forwarding-gateway metadata,
  when available.

Artifacts contain sanitized identifiers, statuses, URLs, and diagnostics only.
They must never contain SAS values, account keys, deployment credentials, or
bearer tokens. The forwarding-gateway file is retained for a later hardening
rollout; this workflow does not apply direct-origin restrictions.

### Current deployment identity

The workflow currently authenticates with the existing
`AZURE_CREDENTIALS_SPONSORSHIP` service-principal credential. Existing
deployment documentation grants that identity subscription-level **Contributor**
access, which covers the current instance deployment, Static Web App upload and
settings, storage key/SAS and CORS operations, and Front Door route lifecycle.
The identity must also be able to read the instance scope and manage the shared
platform scope. Platform Bicep can separately assign Contributor to the
platform-deployment and instance-route principals, and Reader to the operator;
empty principal parameters create no assignment.

This is the current auditable arrangement, not a least-privilege target.
Federated OIDC credentials and narrower custom roles are intentionally deferred
to a separate hardening change. Do not place credential JSON or generated
tokens in documentation or artifacts.
