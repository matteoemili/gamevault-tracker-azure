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

The GitHub Actions workflow (`.github/workflows/azure-static-web-apps-ambitious-glacier-063139803.yml`) includes:

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
