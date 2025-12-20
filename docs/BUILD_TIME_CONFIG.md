# Build-Time vs Runtime Configuration Migration

This document explains how the application's configuration has been updated to support dynamic environment variable injection during CI/CD.

## Previous Approach: GitHub Secrets

Before:
- Environment variables were stored as GitHub repository secrets
- Values had to be manually updated in GitHub Settings
- Required coordination between infrastructure changes and secret updates

## Current Approach: Infrastructure Job Outputs

Now:
- The `deploy_infrastructure` job provisions Azure resources
- Automatically generates a SAS token (valid for 1 year)
- Passes values directly to the `build_and_deploy_job` as job outputs
- No manual secret management required

## How It Works

### 1. Infrastructure Deployment
```yaml
deploy_infrastructure:
  outputs:
    storageAccountName: ${{ steps.deploy.outputs.storageAccountName }}
    sasToken: ${{ steps.generate_sas.outputs.sasToken }}
    gamesTableName: ${{ steps.deploy.outputs.gamesTableName }}
    categoriesTableName: ${{ steps.deploy.outputs.categoriesTableName }}
```

### 2. SAS Token Generation
```bash
az storage account generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --services t \
  --resource-types sco \
  --permissions raud \
  --expiry "+1 year" \
  --https-only
```

### 3. Build-Time Injection
```yaml
build_and_deploy_job:
  needs: deploy_infrastructure
  env:
    VITE_AZURE_STORAGE_ACCOUNT_NAME: ${{ needs.deploy_infrastructure.outputs.storageAccountName }}
    VITE_AZURE_STORAGE_SAS_TOKEN: ${{ needs.deploy_infrastructure.outputs.sasToken }}
    VITE_AZURE_GAMES_TABLE_NAME: ${{ needs.deploy_infrastructure.outputs.gamesTableName }}
    VITE_AZURE_CATEGORIES_TABLE_NAME: ${{ needs.deploy_infrastructure.outputs.categoriesTableName }}
```

## Benefits

✅ **No Secret Management**: Values flow automatically from infrastructure to build  
✅ **Single Source of Truth**: Infrastructure deployment is the authoritative source  
✅ **Automatic Rotation**: SAS token regenerates on every deployment  
✅ **No Manual Updates**: Eliminates human error in configuration management  
✅ **Secure**: SAS token is masked in logs and never stored permanently  

## Security Considerations

⚠️ **SAS Token Expiry**: The generated token is valid for 1 year. Re-run the deployment pipeline before expiration.  
⚠️ **Permissions**: The SAS token has `raud` permissions (Read, Add, Update, Delete) on Table service only.  
⚠️ **HTTPS Only**: The SAS token enforces HTTPS connections only.  
⚠️ **Client-Side Visibility**: The SAS token will be visible in the compiled JavaScript. This is acceptable because:
  - It has limited permissions (tables only, not blobs/files/queues)
  - It has an expiration date
  - This is the standard pattern for browser-based Azure Storage access

## Local Development

Local development still uses `.env` files:

```bash
# Copy the example file
cp .env.example .env

# Fill in your values
VITE_AZURE_STORAGE_ACCOUNT_NAME=your-account
VITE_AZURE_STORAGE_SAS_TOKEN=your-token
```

The `.env` file is only used when running `npm run dev` locally. CI/CD deployments ignore this file entirely.

## GitHub Secrets (Optional Cleanup)

You can now safely **delete** these secrets from your GitHub repository:
- `VITE_AZURE_STORAGE_ACCOUNT_NAME`
- `VITE_AZURE_STORAGE_SAS_TOKEN`

These are no longer needed since values come from the infrastructure job outputs.

**Keep these secrets**:
- `AZURE_CREDENTIALS_SPONSORSHIP` (required for Azure login)
- `GITHUB_TOKEN` (automatically provided by GitHub)

## Alternative Approach: Runtime Configuration

If you need to change configuration **without rebuilding** (true runtime injection), see the [Runtime Configuration Guide](./RUNTIME_CONFIG.md) for an alternative implementation using `window.__RUNTIME_CONFIG__`.

## Troubleshooting

### SAS Token Expiration
If the deployed app stops working after ~1 year, re-run the deployment pipeline to generate a fresh SAS token.

### Build Failures
If the build fails with "environment variable required" errors:
- Ensure the infrastructure job completed successfully
- Check that job outputs are being passed correctly
- Verify the `needs: deploy_infrastructure` dependency is set

### Local Development Issues
If local dev doesn't work:
- Ensure you have a `.env` file (copy from `.env.example`)
- Verify the SAS token hasn't expired
- Check that the storage account name is correct
