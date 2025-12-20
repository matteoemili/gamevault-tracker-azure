# Azure Table Storage Migration Guide

This document provides comprehensive instructions for setting up and configuring Azure Table Storage for the GameVault Tracker application.

## Table of Contents

1. [Overview](#overview)
2. [Azure Setup](#azure-setup)
3. [CORS Configuration](#cors-configuration)
4. [Environment Variables](#environment-variables)
5. [Table Structure](#table-structure)
6. [Migration from GitHub Spark](#migration-from-github-spark)
7. [Local Development](#local-development)
8. [Troubleshooting](#troubleshooting)

## Overview

The application has been migrated from GitHub Spark's built-in key-value storage to Azure Table Storage. This provides:

- **Persistent Cloud Storage**: Data is stored in Azure, accessible from anywhere
- **Scalability**: Azure Table Storage can handle large amounts of data
- **Cost-Effective**: Pay only for what you use
- **Security**: SAS token-based authentication with fine-grained permissions

### Architecture Changes

- **Before**: `useKV()` hooks from `@github/spark/hooks`
- **After**: `useAzureTableList()` hooks from `@/hooks/use-azure-table`

The application uses two tables:
1. **games**: Stores the game collection
2. **categories**: Stores platform categories (PS1, PS2, PS3, etc.)

## Azure Setup

### Step 1: Create a Storage Account

1. Log in to [Azure Portal](https://portal.azure.com)
2. Navigate to **Storage accounts**
3. Click **+ Create**
4. Fill in the required information:
   - **Subscription**: Your Azure subscription
   - **Resource Group**: Create new or use existing
   - **Storage account name**: Choose a unique name (e.g., `gamevaulttracker`)
   - **Region**: Select a region close to your users
   - **Performance**: Standard
   - **Redundancy**: LRS (Locally-redundant storage) for development, or higher for production
5. Click **Review + Create**, then **Create**

### Step 2: Create Tables

1. Navigate to your Storage Account
2. Go to **Tables** under **Data storage**
3. Click **+ Table** to create two tables:
   - Name: `games`
   - Name: `categories`

### Step 3: Generate SAS Token

A Shared Access Signature (SAS) token provides secure access to your storage account without exposing the account key.

#### Option A: Azure Portal (Recommended for Development)

1. In your Storage Account, go to **Security + networking** > **Shared access signature**
2. Configure the SAS:
   - **Allowed services**: ✅ Table
   - **Allowed resource types**: ✅ Service, ✅ Container, ✅ Object
   - **Allowed permissions**: ✅ Read, ✅ Write, ✅ Delete, ✅ List, ✅ Add, ✅ Update
   - **Start and expiry date/time**: Set appropriate dates
   - **Allowed protocols**: HTTPS only
3. Click **Generate SAS and connection string**
4. Copy the **SAS token** (starts with `?sv=...`)

#### Option B: Azure CLI

```bash
# Set variables
STORAGE_ACCOUNT="your-storage-account-name"
EXPIRY_DATE="2025-12-31T23:59:59Z"

# Generate SAS token
az storage account generate-sas \
  --account-name $STORAGE_ACCOUNT \
  --services t \
  --resource-types sco \
  --permissions rwdlacu \
  --expiry $EXPIRY_DATE \
  --https-only \
  --output tsv
```

**Important Security Notes:**
- Never commit SAS tokens to version control
- Use short expiry times for development
- Regenerate tokens regularly
- Use managed identities for production deployments

## CORS Configuration

**Note**: CORS is automatically configured by the CI/CD pipeline. This section is for reference or manual troubleshooting only.

The GitHub Actions workflow automatically:
1. Retrieves the Static Web App URL from deployment outputs
2. Configures CORS for the Table Service with:
   - Allowed origin: The Static Web App URL
   - Methods: GET, POST, PUT, DELETE, OPTIONS, PATCH
   - Headers: * (all)
   - Exposed headers: * (all)
   - Max age: 3600 seconds

Cross-Origin Resource Sharing (CORS) allows your web application to access Azure Table Storage from the browser.

### Configure CORS in Azure Portal

1. Navigate to your Storage Account
2. Go to **Settings** > **Resource sharing (CORS)**
3. Select the **Table service** tab
4. Add a new CORS rule:

   | Setting | Value |
   |---------|-------|
   | **Allowed origins** | `http://localhost:5173` (for development)<br/>`https://your-production-domain.com` (for production) |
   | **Allowed methods** | GET, POST, PUT, DELETE, OPTIONS |
   | **Allowed headers** | * |
   | **Exposed headers** | * |
   | **Max age** | 3600 |

5. Click **Save**

### Configure CORS via Azure CLI

```bash
az storage cors add \
  --account-name your-storage-account-name \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "http://localhost:5173" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600
```

### Production CORS Configuration

For production, be more restrictive:

```bash
# Add your production domain
az storage cors add \
  --account-name your-storage-account-name \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "https://your-app.azurestaticapps.net" \
  --allowed-headers "content-type,accept,x-ms-version,x-ms-date" \
  --exposed-headers "*" \
  --max-age 3600
```

## Environment Variables

### Setup

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and fill in your values:
   ```env
   VITE_AZURE_STORAGE_ACCOUNT_NAME=gamevaulttracker
   VITE_AZURE_STORAGE_SAS_TOKEN=?sv=2022-11-02&ss=t&srt=sco&sp=rwdlacu&se=2025-12-31T23:59:59Z&st=2025-01-01T00:00:00Z&spr=https&sig=...
   ```

3. **Never commit `.env` to version control!** It's already in `.gitignore`.

### Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VITE_AZURE_STORAGE_ACCOUNT_NAME` | Yes | - | Your Azure Storage Account name |
| `VITE_AZURE_STORAGE_SAS_TOKEN` | Yes | - | SAS token with Table permissions |
| `VITE_AZURE_STORAGE_ENDPOINT` | No | `https://{accountName}.table.core.windows.net` | Custom endpoint URL |
| `VITE_AZURE_GAMES_TABLE_NAME` | No | `games` | Name of the games table |
| `VITE_AZURE_CATEGORIES_TABLE_NAME` | No | `categories` | Name of the categories table |

## Table Structure

### Games Table

Each game is stored as an entity with the following structure:

```typescript
{
  PartitionKey: "default",        // All games in same partition
  RowKey: "game-uuid",           // Unique game ID
  data: "{...}"                  // JSON-serialized Game object
}
```

**Game Object Structure:**
```typescript
{
  id: string;
  name: string;
  platform: string;
  acquired: boolean;
  targetPrice?: number;
  priority?: boolean;
  purchasePrice?: number;
  acquisitionDate?: string;
  seller?: string;
  notes?: string;
}
```

### Categories Table

Each category is stored as an entity:

```typescript
{
  PartitionKey: "default",
  RowKey: "category-id",         // e.g., "PS1", "PS2", "PC"
  data: "{...}"                  // JSON-serialized Category object
}
```

**Category Object Structure:**
```typescript
{
  id: string;
  name: string;
  logoUrl: string;
}
```

### Why This Structure?

- **Single Partition**: Simplifies queries and works well for small to medium datasets
- **RowKey as ID**: Natural mapping from application IDs to table keys
- **JSON Data**: Flexible schema, easy to extend with new fields
- **Future Scaling**: Can partition by platform or user if needed

## Migration from GitHub Spark

### Code Changes Summary

1. **Removed Dependency**: `@github/spark/hooks`
2. **New Modules**:
   - `src/lib/azure-storage.ts`: Azure Table Storage REST API client
   - `src/lib/azure-config.ts`: Configuration management
   - `src/hooks/use-azure-table.ts`: React hooks for Azure storage

3. **Updated Components**:
   - `src/App.tsx`: Replaced `useKV` with `useAzureTableList`

### API Comparison

#### Before (GitHub Spark)
```typescript
const [games, setGames] = useKV<Game[]>('game-collection', []);
```

#### After (Azure Table Storage)
```typescript
const azureConfig = getAzureConfig();
const [games, setGames, loading] = useAzureTableList<Game>(
  azureConfig.tables.games,
  []
);
```

### Data Migration

If you have existing data in GitHub Spark storage:

1. Export your data using the **Import/Export** menu in the app
2. Set up Azure Table Storage following this guide
3. Import the data back into the app

The app will automatically sync to Azure Table Storage.

## Local Development

### Prerequisites

- Node.js 18+ and npm/yarn
- Azure Storage Account (or Azure Storage Emulator/Azurite)

### Using Azurite (Local Storage Emulator)

For local development without Azure:

1. Install Azurite:
   ```bash
   npm install -g azurite
   ```

2. Start Azurite:
   ```bash
   azurite --silent --location ./azurite --debug ./azurite/debug.log
   ```

3. Configure `.env` for local development:
   ```env
   VITE_AZURE_STORAGE_ACCOUNT_NAME=devstoreaccount1
   VITE_AZURE_STORAGE_SAS_TOKEN=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==
   VITE_AZURE_STORAGE_ENDPOINT=http://127.0.0.1:10002/devstoreaccount1
   ```

4. Create tables using Azure Storage Explorer or code

### Running the Application

```bash
# Install dependencies
npm install

# Start development server
npm run dev
```

The app will be available at `http://localhost:5173`

## Troubleshooting

### Issue: "CORS policy" error in browser console

**Cause**: CORS is not configured correctly in Azure Storage.

**Solution**:
1. Verify CORS rules in Azure Portal (see [CORS Configuration](#cors-configuration))
2. Ensure your origin matches exactly (including port)
3. Clear browser cache and try again

### Issue: "401 Unauthorized" or "403 Forbidden"

**Cause**: SAS token is invalid or expired.

**Solution**:
1. Check token expiry date
2. Verify token permissions include: Read, Write, Delete, List, Add
3. Generate a new token
4. Update `.env` file

### Issue: "Table not found" error

**Cause**: Tables don't exist in Azure Storage.

**Solution**:
1. Navigate to Azure Portal > Storage Account > Tables
2. Create tables: `games` and `categories`
3. Verify table names match environment variables

### Issue: Data not loading

**Cause**: Multiple possible causes.

**Debugging Steps**:
1. Open browser DevTools > Console
2. Check for errors
3. Verify environment variables are loaded:
   ```javascript
   console.log(import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_NAME);
   ```
4. Check Network tab for failed requests
5. Verify Azure Storage account is accessible

### Issue: TypeScript errors

**Cause**: Environment variable types not recognized.

**Solution**:
- Ensure `src/vite-end.d.ts` has the proper type declarations
- Restart TypeScript server in VS Code: `Cmd+Shift+P` > "TypeScript: Restart TS Server"

## Security Best Practices

1. **Never commit secrets**: Keep `.env` out of version control
2. **Rotate tokens regularly**: Generate new SAS tokens periodically
3. **Use least privilege**: Grant only necessary permissions
4. **Monitor access**: Enable Azure Storage Analytics
5. **Use HTTPS only**: Enforce secure connections
6. **Production considerations**:
   - Use Azure Key Vault for secrets
   - Implement Azure AD authentication for server-side apps
   - Consider using a backend API instead of direct browser access

## Performance Optimization

- **Partitioning**: For large datasets, consider partitioning by user or date
- **Batch operations**: The service supports batch operations for bulk updates
- **Caching**: Implement client-side caching for frequently accessed data
- **Indexes**: Azure Table Storage automatically indexes PartitionKey and RowKey

## Support and Resources

- [Azure Table Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/tables/)
- [Azure Storage REST API Reference](https://docs.microsoft.com/en-us/rest/api/storageservices/)
- [SAS Token Best Practices](https://docs.microsoft.com/en-us/azure/storage/common/storage-sas-overview)
- [CORS in Azure Storage](https://docs.microsoft.com/en-us/rest/api/storageservices/cross-origin-resource-sharing--cors--support-for-the-azure-storage-services)

## License

This migration guide is part of the GameVault Tracker project. See LICENSE for details.
