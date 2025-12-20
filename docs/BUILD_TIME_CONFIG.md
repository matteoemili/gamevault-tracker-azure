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
  steps:
    - Deploy Bicep templates
    - Extract outputs (storage account name, static web app name/URL, table names)
    - Configure CORS automatically for the Static Web App URL
  outputs:
    storageAccountName: ${{ steps.deploy.outputs.storageAccountName }}
    staticWebAppName: ${{ steps.deploy.outputs.staticWebAppName }}
    staticWebAppUrl: ${{ steps.deploy.outputs.staticWebAppUrl }}
    gamesTableName: ${{ steps.deploy.outputs.gamesTableName }}
    categoriesTableName: ${{ steps.deploy.outputs.categoriesTableName }}
```

### 2. CORS Configuration (Automatic)
```bash
az storage cors add \
  --account-name "$STORAGE_ACCOUNT" \
  --services t \
  --methods GET POST PUT DELETE OPTIONS PATCH \
  --origins "$WEB_APP_URL" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600
```

### 3. SAS Token Generation (In Build Job)
```yaml
build_and_deploy_job:
  steps:
    - name: Generate SAS Token
      run: |
        # Retrieve storage account key
        ACCOUNT_KEY=$(az storage account keys list ...)
        
        # Generate SAS token (valid for 1 year)
        SAS_TOKEN=$(az storage account generate-sas \
          --account-name "$STORAGE_ACCOUNT" \
          --account-key "$ACCOUNT_KEY" \
          --services t \
          --resource-types sco \
          --permissions raud \
          --expiry "+1 year" \
          --https-only)
```

**Important**: The SAS token is generated in the build job (not infrastructure job) to avoid GitHub Actions' security restriction that prevents masked values from being passed as job outputs.

### 4. Build-Time Injection
```yaml
- name: Create Production Environment File
  run: |
    cat > .env.production << EOF
    VITE_AZURE_STORAGE_ACCOUNT_NAME=${{ needs.deploy_infrastructure.outputs.storageAccountName }}
    VITE_AZURE_STORAGE_SAS_TOKEN=${{ steps.generate_sas.outputs.sas_token }}
    VITE_AZURE_GAMES_TABLE_NAME=${{ needs.deploy_infrastructure.outputs.gamesTableName }}
    VITE_AZURE_CATEGORIES_TABLE_NAME=${{ needs.deploy_infrastructure.outputs.categoriesTableName }}
    EOF

- name: Build And Deploy
  # Vite automatically reads .env.production during build
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

## GitHub Secrets

**Only one secret is required**:
- `AZURE_CREDENTIALS_SPONSORSHIP` - Azure service principal credentials for authentication

**Automatically provided by GitHub**:
- `GITHUB_TOKEN` - Used for deployment token retrieval

**Not needed** (handled automatically by the pipeline):
- ~~`VITE_AZURE_STORAGE_ACCOUNT_NAME`~~ - Retrieved from infrastructure deployment
- ~~`VITE_AZURE_STORAGE_SAS_TOKEN`~~ - Generated dynamically in the build job
- ~~`VITE_AZURE_GAMES_TABLE_NAME`~~ - Retrieved from infrastructure deployment
- ~~`VITE_AZURE_CATEGORIES_TABLE_NAME`~~ - Retrieved from infrastructure deployment

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
