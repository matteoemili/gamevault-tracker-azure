# GameVault Tracker - Infrastructure as Code

This document provides comprehensive documentation for the Infrastructure as Code (IaC) implementation of the GameVault Tracker application using Azure Bicep.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Infrastructure Components](#infrastructure-components)
3. [Prerequisites](#prerequisites)
4. [Local Development](#local-development)
5. [CI/CD Integration](#cicd-integration)
6. [Configuration Reference](#configuration-reference)
7. [Security Considerations](#security-considerations)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

## Shared Multi-Instance Entry Platform

The shared platform lives in its own resource group and contains one Azure
Front Door profile, a central WAF policy, Log Analytics diagnostics,
alerts, and a tagged cost budget. Each instance remains in its own resource
group with its own Static Web App and Table Storage account. A route lifecycle
operation creates one Azure-provided `azurefd.net` endpoint, one route, one
origin group, and one application origin for that instance only.

There is no owned domain in this design. The published address is the generated
Front Door endpoint hostname; Front Door provides the certificate and redirects
HTTP to HTTPS. A route can use only its matching origin group, so an unhealthy
instance cannot fail over to another instance.

The security boundary is centralized WAF enforcement plus endpoint-scoped
associations, while management is limited by resource-group role assignments.
Operational logs remain in the shared workspace for at least 90 days.

The profile is deployed on `Standard_AzureFrontDoor` by default, which costs
roughly a tenth of Premium's fixed monthly base fee. Standard supports custom
and rate-limit WAF rules but not Microsoft-managed rule sets or bot protection,
and it allows 10 endpoints per profile instead of 25. Set the `frontDoorSku`
parameter to `Premium_AzureFrontDoor` to restore both. The endpoint capacity
reported by the CLI is read from the live profile SKU; create a new profile and
shard new instance IDs once the capacity check reports the limit as reached.

Use `scripts/instance-route.sh status` to inspect a route’s HTTP health,
capacity, last lifecycle deployment, and orphaned-instance indication. Use
`unregister --confirm` before deleting a retired instance resource group.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Azure Resource Group                          │
│                         (rg-gamevault-tracker)                          │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Azure Static Web App                          │   │
│  │                   (swa-gamevault-prod-xxx)                       │   │
│  │                                                                   │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │   │
│  │  │   React     │    │   Vite      │    │   GitHub Actions    │  │   │
│  │  │   Frontend  │───▶│   Build     │◀───│   CI/CD Pipeline    │  │   │
│  │  │   (dist/)   │    │   Output    │    │                     │  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    │ HTTPS + SAS Token                   │
│                                    ▼                                     │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                   Azure Storage Account                          │   │
│  │                    (stgamevaultxxxxxxx)                          │   │
│  │                                                                   │   │
│  │  ┌─────────────────────────────────────────────────────────────┐│   │
│  │  │                   Table Service                              ││   │
│  │  │                                                              ││   │
│  │  │  ┌──────────────────┐    ┌──────────────────┐              ││   │
│  │  │  │   games table    │    │ categories table │              ││   │
│  │  │  │                  │    │                  │              ││   │
│  │  │  │  - PartitionKey  │    │  - PartitionKey  │              ││   │
│  │  │  │  - RowKey        │    │  - RowKey        │              ││   │
│  │  │  │  - Game data     │    │  - Category data │              ││   │
│  │  │  └──────────────────┘    └──────────────────┘              ││   │
│  │  │                                                              ││   │
│  │  │  CORS Rules:                                                ││   │
│  │  │  - localhost:5173, 5000, 3000 (dev)                         ││   │
│  │  │  - Static Web App URL (prod)                                ││   │
│  │  └─────────────────────────────────────────────────────────────┘│   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **User Request**: Browser loads the React application from Azure Static Web App
2. **API Calls**: Frontend makes REST API calls to Azure Table Storage using SAS token
3. **CORS**: Storage Account validates the origin against configured CORS rules
4. **Data Operations**: CRUD operations on `games` and `categories` tables

---

## Infrastructure Components

### Azure Storage Account

| Property | Value |
|----------|-------|
| **Type** | StorageV2 (General Purpose v2) |
| **SKU** | Standard_LRS (Locally Redundant Storage) |
| **Access Tier** | Hot |
| **TLS Version** | TLS 1.2 minimum |
| **Public Access** | Enabled (secured via SAS tokens) |

**Table Service Configuration:**
- Automatic table creation: `games`, `categories`
- CORS rules configured for local development and production
- Supports all necessary HTTP methods for CRUD operations

### Azure Static Web App

| Property | Value |
|----------|-------|
| **SKU** | Free |
| **Staging Environments** | Enabled |
| **Build Configuration** | Vite (npm run build) |
| **Output Directory** | dist |

---

## Prerequisites

### Local Development

1. **Azure CLI** (v2.50.0 or later)
   ```bash
   # macOS
   brew install azure-cli
   
   # Verify installation
   az --version
   ```

2. **Bicep CLI** (included with Azure CLI)
   ```bash
   # Install/upgrade Bicep
   az bicep install
   az bicep upgrade
   
   # Verify installation
   az bicep version
   ```

3. **Azure Subscription**
   ```bash
   # Login to Azure
   az login
   
   # Set subscription (if you have multiple)
   az account set --subscription "Your Subscription Name"
   ```

### CI/CD Prerequisites

For GitHub Actions infrastructure deployment, you need to configure a Service Principal with a client secret:

1. **Create Service Principal**
   Run the following command to create a Service Principal with Contributor access to your subscription:
   ```bash
   # Replace <subscription-id> with your Azure Subscription ID
   az ad sp create-for-rbac \
     --name "GameVault-GitHub-Actions" \
     --role contributor \
     --scopes /subscriptions/<subscription-id> \
     --sdk-auth
   ```

2. **Add GitHub Secret**
   Copy the entire JSON output from the command above and add it as a repository secret:
   - Name: `AZURE_CREDENTIALS`
   - Value: (The JSON output)

   *Note: This method uses a client secret. Ensure you rotate this secret periodically.*

---

## Local Development

### Quick Start

```bash
# 1. Validate the infrastructure template
./scripts/validate-infra.sh

# 2. Deploy infrastructure
./scripts/deploy-infra.sh

# 3. Copy the SAS token to your .env file
# (Output will be displayed after deployment)

# 4. Start local development
npm run dev
```

### Script Reference

#### deploy-infra.sh

Deploys the complete infrastructure to Azure.

```bash
# Syntax
./scripts/deploy-infra.sh [environment] [resource-group] [location]

# Examples
./scripts/deploy-infra.sh                              # Deploy prod
./scripts/deploy-infra.sh dev rg-gamevault-dev         # Deploy dev
./scripts/deploy-infra.sh prod rg-gamevault westus2    # Custom location
```

**What it does:**
1. Validates prerequisites (Azure CLI, Bicep, login status)
2. Validates Bicep template syntax
3. Creates resource group if it doesn't exist
4. Deploys infrastructure using Bicep
5. Displays deployment outputs
6. Generates a SAS token for storage access

#### validate-infra.sh

Validates templates and shows what-if preview.

```bash
# Syntax
./scripts/validate-infra.sh [environment] [resource-group]

# Examples
./scripts/validate-infra.sh                      # Validate prod
./scripts/validate-infra.sh dev rg-gamevault-dev # Validate dev
```

**What it does:**
1. Validates Bicep syntax
2. Runs linting checks
3. Validates deployment against Azure
4. Shows what-if preview of changes

#### cleanup-infra.sh

Removes all infrastructure by deleting the resource group.

```bash
# Syntax
./scripts/cleanup-infra.sh [resource-group]

# Examples
./scripts/cleanup-infra.sh                     # Delete default RG
./scripts/cleanup-infra.sh rg-gamevault-dev    # Delete specific RG
```

**⚠️ Warning:** This permanently deletes all resources. Use with caution.

---

## CI/CD Integration

### Workflow Overview

The GitHub Actions workflow (`.github/workflows/ci-cd.yml`) includes:

1. **Infrastructure Deployment Job** (`deploy_infrastructure`)
   - Triggered on push, pull request, or manual dispatch
   - Uses Service Principal authentication with Azure
   - Deploys Bicep templates to ensure infrastructure is up-to-date

2. **Build and Deploy Job** (`build_and_deploy_job`)
   - Runs on every push/PR to main
   - Builds the React application with Vite
   - Deploys to Azure Static Web App

3. **Close Pull Request Job** (`close_pull_request_job`)
   - Cleans up preview environments when PRs are closed

4. **Front Door Publication Job** (`publish_front_door`)
   - Runs only after infrastructure and application upload succeed
   - Registers the instance route, aligns published-origin CORS, verifies the
     route, and reports the verified URL
   - Serializes publication per environment/profile with
     `cancel-in-progress: false`

### Environment-specific Front Door configuration

The publication job receives explicit, non-secret GitHub repository variables
for each environment. Set all six variables before enabling publication:

| Environment | Platform resource group variable | Front Door profile variable |
|---|---|---|
| `dev` | `GAMEVAULT_PLATFORM_RESOURCE_GROUP_DEV` | `GAMEVAULT_FRONT_DOOR_PROFILE_DEV` |
| `staging` | `GAMEVAULT_PLATFORM_RESOURCE_GROUP_STAGING` | `GAMEVAULT_FRONT_DOOR_PROFILE_STAGING` |
| `prod` | `GAMEVAULT_PLATFORM_RESOURCE_GROUP_PROD` | `GAMEVAULT_FRONT_DOOR_PROFILE_PROD` |

The workflow selects the pair from `DEPLOYMENT_ENVIRONMENT`, validates that
both values are present and that the platform and instance resource groups
differ, then passes them to `instance-route.sh`. The configured profile name
is authoritative; the platform Bicep naming convention is
`gvt-afd-{environment}`. The subscription is read from the authenticated Azure
context and is not duplicated in repository variables.

### Publication ordering and verification

Publication is an ordered phase, not a second infrastructure deployment:

1. Create `publication-result.json` before preflight so configuration failures
   have a retained result.
2. Validate the subscription, instance outputs, origin hostname, and platform
   mapping without mutating the route.
3. Run `scripts/instance-route.sh register`, accepting `Succeeded`, `NoChange`,
   or `Degraded` only when it returns an HTTPS route URL.
4. Run `scripts/cors-add-origin.sh` for the published Front Door URL.
5. Run the read-only `verify` command once. It validates the deployed Azure
   Front Door endpoint, route, origin group, and origin properties through the
   control plane without waiting for data-plane propagation. Only verification
   status `Succeeded` is a successful publication.
6. Write the URL to the job summary/output and upload available sanitized
   result files with `if: always()`.

The artifact is named `route-registration-<instance-id>` and is created from
the workflow workspace. It may contain `publication-result.json`,
`route-registration.json`, `route-verification.json`, and
`route-forwarding-gateway.json`. The last file is generated metadata only; it
is not applied by this feature. No artifact may contain account keys, SAS
values, credentials, bearer tokens, or unmasked secret-bearing command output.

### Manual Infrastructure Deployment

To manually trigger infrastructure deployment:

1. Go to **Actions** tab in GitHub
2. Select **Azure Static Web Apps CI/CD**
3. Click **Run workflow**
4. Set `deploy_infrastructure` to `true`
5. Click **Run workflow**

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Azure AD App Registration Client ID |
| `AZURE_TENANT_ID` | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID |
| `AZURE_STATIC_WEB_APPS_API_TOKEN_AMBITIOUS_GLACIER_063139803` | Static Web App deployment token |
| `VITE_AZURE_STORAGE_ACCOUNT_NAME` | Storage account name |
| `VITE_AZURE_STORAGE_SAS_TOKEN` | SAS token for storage access |

The current workflow uses `AZURE_CREDENTIALS_SPONSORSHIP` for `azure/login` in
the infrastructure, application, and publication jobs. The documented current
permission is subscription-level **Contributor** for the service principal.
That broad role permits instance resource-group deployment and read access,
Static Web App deployment/settings, storage key/SAS and Table CORS operations,
and Front Door route management in the shared platform resource group. The
route identity must be able to read the instance scope and mutate the matching
platform route without changing sibling routes.

The shared platform Bicep RBAC module can assign Contributor to separate
platform-deployment and instance-route principals and Reader to an operator
when their object-ID parameters are supplied. Those assignments are optional
and disabled when parameters are empty. Migrating the workflow to federated
OIDC and least-privilege custom roles is intentionally deferred; it is not part
of automatic publication.

---

## Configuration Reference

### Bicep Parameters

#### main.bicepparam (Production)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environment` | string | `prod` | Environment name |
| `baseName` | string | `gamevault` | Base name for resources |
| `staticWebAppSku` | string | `Free` | Static Web App SKU |
| `storageSkuName` | string | `Standard_LRS` | Storage redundancy |
| `corsAllowedOrigins` | array | `[]` | Additional CORS origins |
| `repositoryUrl` | string | `''` | GitHub repo URL |
| `repositoryBranch` | string | `main` | Git branch |
| `tags` | object | `{...}` | Resource tags |

#### main.dev.bicepparam (Development)

Same parameters with development-specific defaults:
- Includes localhost origins for CORS
- Tagged with `environment: dev`

### Environment Variables

Create a `.env` file in the project root:

```bash
# Azure Storage Configuration
VITE_AZURE_STORAGE_ACCOUNT_NAME=stgamevaultxxxxxxx
VITE_AZURE_STORAGE_SAS_TOKEN=sv=2024-11-04&ss=t&srt=sco&sp=rwdlacu&se=...

# Optional: Custom table names (defaults shown)
VITE_AZURE_GAMES_TABLE_NAME=games
VITE_AZURE_CATEGORIES_TABLE_NAME=categories
```

---

## Security Considerations

### SAS Token Best Practices

1. **Minimum Permissions**: Only grant necessary permissions (Table service, Read/Write/Delete)
2. **Short Expiry**: Use 6-12 month expiry for production, shorter for development
3. **HTTPS Only**: Always require HTTPS in SAS token
4. **Rotate Regularly**: Implement token rotation before expiry
5. **Never Commit**: Add `.env` to `.gitignore`

### CORS Configuration

The CORS configuration allows:
- **Development**: localhost on ports 5173, 5000, 3000
- **Production**: Static Web App URL (add after deployment)

To add your production URL to CORS:
1. Deploy infrastructure first
2. Get the Static Web App URL from outputs
3. Update `corsAllowedOrigins` in parameters file
4. Redeploy infrastructure

### Network Security

- Storage Account uses public network access (required for browser-based app)
- All traffic uses HTTPS (TLS 1.2 minimum)
- SAS tokens provide authentication and authorization

### Direct-origin hardening (deferred)

The route registration command may retain
`route-forwarding-gateway.json`, which contains the Front Door forwarding
metadata needed for a future Static Web App restriction. This feature
intentionally does **not** apply forwarding-gateway restrictions or disable
direct Static Web App origins. Applying them would require another application
deployment and changes rollback/recovery behavior. Treat direct-origin access
as an intentional current state until a separately approved hardening rollout
verifies every instance through Front Door.

---

## Troubleshooting

### Common Issues

#### "Not logged in to Azure"
```bash
az login
az account set --subscription "Your Subscription"
```

#### "Bicep validation failed"
```bash
# Check for syntax errors
az bicep build --file infra/main.bicep

# View detailed errors
az deployment group validate \
  --resource-group rg-gamevault-tracker \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

#### "CORS error in browser"
1. Verify your origin is in the CORS allowed origins
2. Check the Storage Account CORS settings in Azure Portal
3. Ensure SAS token hasn't expired

#### "403 Forbidden on Table operations"
1. Verify SAS token permissions include Table service
2. Check SAS token hasn't expired
3. Verify storage account name matches

#### "Resource group already exists in different location"
```bash
# Either delete existing RG or use same location
az group show --name rg-gamevault-tracker --query location

# Or delete and recreate
./scripts/cleanup-infra.sh rg-gamevault-tracker
./scripts/deploy-infra.sh prod rg-gamevault-tracker westeurope
```

### Getting Help

1. Check the [Azure CLI documentation](https://docs.microsoft.com/cli/azure/)
2. Review [Bicep documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
3. Check deployment logs in Azure Portal

---

## File Structure

```
gamevault-tracker-azure/
├── infra/
│   ├── main.bicep           # Main infrastructure template
│   ├── main.bicepparam      # Production parameters
│   └── main.dev.bicepparam  # Development parameters
├── scripts/
│   ├── deploy-infra.sh      # Deploy infrastructure
│   ├── validate-infra.sh    # Validate and preview
│   └── cleanup-infra.sh     # Remove infrastructure
├── .github/
│   └── workflows/
│       └── azure-static-web-apps-*.yml  # CI/CD workflow
└── docs/
    └── INFRASTRUCTURE.md    # This documentation
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-12-13 | Initial IaC implementation |

---

## Contributing

When modifying infrastructure:

1. Update Bicep templates in `infra/`
2. Test locally with `./scripts/validate-infra.sh`
3. Update documentation if parameters change
4. Create a PR - infrastructure changes will be previewed
5. Merge to main - infrastructure will be deployed automatically
