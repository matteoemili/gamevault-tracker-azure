# Production Deployment Guide - Azure Static Web Apps

## ✅ Automated CI/CD Deployment

**This application uses a fully automated CI/CD pipeline.** Environment variables are automatically injected during the build process:

- ✅ SAS tokens are **generated automatically** from infrastructure deployment
- ✅ Storage account names are **passed dynamically** from Bicep outputs
- ✅ CORS settings are **automatically configured** for the deployed Static Web App URL
- ✅ **No manual GitHub secrets management required**

### How It Works

1. **Infrastructure Job**: Deploys Azure resources (storage account, static web app, tables)
2. **Build Job**: Generates fresh SAS token and builds the application with injected variables
3. **CORS Configuration**: Automatically adds the Static Web App URL to storage CORS rules

Vite environment variables are **baked into the JavaScript bundle at BUILD time**, not runtime.

## Security Consideration

### ⚠️ DO NOT USE ACCOUNT KEYS IN PRODUCTION

**Account keys provide FULL access to your storage account** and should NEVER be in client-side code. Always use SAS tokens with:
- ✅ Limited permissions (only Table Read/Write/Delete)
- ✅ Expiration date (rotate regularly)
- ✅ Revocable without changing account keys

## Automated Deployment Process

### How to Deploy

Simply push your code to the `main` branch:

```bash
git add .
git commit -m "Your changes"
git push origin main
```

The GitHub Actions workflow automatically:

1. **Deploys Infrastructure** (if needed)
   - Creates/updates Azure Storage Account
   - Creates/updates Azure Static Web App
   - Creates game and category tables

2. **Configures CORS**
   - Automatically adds the Static Web App URL to storage CORS rules
   - Allows all HTTP methods (GET, POST, PUT, DELETE, OPTIONS, PATCH)
   - Sets proper headers and max age (3600 seconds)

3. **Generates SAS Token**
   - Retrieves storage account key securely
   - Generates a SAS token valid for 1 year
   - Token has limited permissions (Table service only: Read, Add, Update, Delete)

4. **Builds Application**
   - Creates `.env.production` with injected values
   - Runs `npm run build` with environment variables
   - Vite bakes the configuration into the JavaScript bundle

5. **Deploys to Azure**
   - Uploads the built application to Azure Static Web Apps
   - Configures application settings (for future API functions if needed)

### Required GitHub Secrets

Only one secret is required for the entire pipeline:

- **`AZURE_CREDENTIALS_SPONSORSHIP`**: Azure service principal credentials for authentication

All other configuration is handled automatically!

## Manual Configuration (Only if Needed)

### Generate a SAS Token Manually

**Note**: The CI/CD pipeline handles this automatically. Manual generation is only needed for local development or troubleshooting.

#### Azure Portal

1. Open [Azure Portal](https://portal.azure.com)
2. Navigate to your Storage Account
3. Go to **Security + networking** > **Shared access signature**
4. Configure:
   - **Allowed services**: ✅ Table only
   - **Allowed resource types**: ✅ Service, ✅ Container, ✅ Object
   - **Allowed permissions**: ✅ Read, ✅ Write, ✅ Delete, ✅ List, ✅ Add, ✅ Update
   - **Start and expiry date/time**: Set expiry to 6-12 months
   - **Allowed protocols**: HTTPS only
5. Click **Generate SAS and connection string**
6. Copy the **SAS token**

### Manual CORS Configuration

**Note**: The CI/CD pipeline configures CORS automatically. Manual configuration is only needed for troubleshooting.

#### Azure Portal

1. Go to your Storage Account
2. **Settings** > **Resource sharing (CORS)**
3. **Table service** tab
4. Click **+ Add CORS rule**:
   - **Allowed origins**: `https://ambitious-glacier-063139803.azurestaticapps.net`
   - **Allowed methods**: GET, POST, PUT, DELETE, OPTIONS
   - **Allowed headers**: `*`
   - **Exposed headers**: `*`
   - **Max age**: `3600`
5. Click **Save**

**Option B: Azure CLI (Mac)**

```bash
# Add production domain
az storage cors add \
  --account-name stvgcollection \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "https://ambitious-glacier-063139803.azurestaticapps.net" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600

# For development, you can add localhost too
az storage cors add \
  --account-name stvgcollection \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "http://localhost:5173" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600
```

### 4. Verify GitHub Workflow Configuration

The workflow has been updated to use environment variables during build. Verify it looks like this:

```yaml
env:
  VITE_AZURE_STORAGE_ACCOUNT_NAME: ${{ secrets.VITE_AZURE_STORAGE_ACCOUNT_NAME }}
  VITE_AZURE_STORAGE_SAS_TOKEN: ${{ secrets.VITE_AZURE_STORAGE_SAS_TOKEN }}
```

### 5. Deploy to Production

#### Option A: Push to Main Branch

```bash
# Commit your changes
git add .
git commit -m "Configure Azure Storage for production"

# Push to trigger deployment
git push origin storage

# Or push directly to main to trigger deployment
git checkout main
git merge storage
git push origin main
```

#### Option B: Manual Trigger (GitHub UI)

1. Go to **Actions** tab in GitHub
2. Select the workflow
3. Click **Run workflow**
4. Select branch: `main`

### 6. Monitor Deployment

1. Go to **Actions** tab in GitHub
2. Watch the build process
3. Check for errors in the build logs
4. Verify environment variables are being set:
   - Look for `VITE_AZURE_STORAGE_ACCOUNT_NAME` in the build output
   - You won't see the token value (GitHub masks secrets)

### 7. Test Production Deployment

1. Visit your Static Web App URL
2. Open browser Developer Tools (F12)
3. Go to Console tab
4. Add a game and watch for logs:
   ```
   [Azure] Loading data from table: games
   [Azure] Saving 1 items to table: games
   [Azure] Successfully saved data to games
   ```
5. Refresh the page - game should persist

### 8. Troubleshooting Production Issues

#### Issue: "Cannot read properties of undefined (reading 'VITE_AZURE_STORAGE_ACCOUNT_NAME')"

**Cause**: Environment variables not set during build

**Fix**:
1. Verify GitHub Secrets are named correctly (exact names, case-sensitive)
2. Check workflow YAML has the `env:` section
3. Re-run the GitHub Action

#### Issue: "CORS policy blocked" in production

**Cause**: Production domain not in CORS settings

**Fix**:
1. Get exact URL from browser address bar
2. Add to CORS settings in Azure Portal
3. Wait 1-2 minutes for CORS to propagate
4. Clear browser cache and try again

#### Issue: "401 Unauthorized" in production

**Cause**: SAS token not set or invalid

**Fix**:
1. Verify `VITE_AZURE_STORAGE_SAS_TOKEN` secret exists in GitHub
2. Generate new SAS token
3. Update GitHub Secret
4. Re-run deployment

#### Issue: Data works locally but not in production

**Cause**: Different environment variables

**Check**:
```bash
# Local .env file
cat .env

# Should have:
VITE_AZURE_STORAGE_ACCOUNT_NAME=stvgcollection
VITE_AZURE_STORAGE_SAS_TOKEN=sv=...
```

**GitHub Secrets should have the SAME values**

### 9. Verify Build Output (Mac)

After the build completes, you can check the built files:

```bash
# Build locally to test
npm run build

# Check that env vars are in the bundle (Mac)
grep -r "stvgcollection" dist/assets/*.js

# Should show the account name embedded in the JS files
```

⚠️ **Note**: This also shows why you should NEVER use account keys - they'd be visible in the built JavaScript!

### 10. Security Checklist

- [ ] Using SAS token (NOT account key) ✅
- [ ] SAS token has expiration date ✅
- [ ] SAS token limited to Table service only ✅
- [ ] CORS configured for specific production domain ✅
- [ ] Secrets stored in GitHub (not in code) ✅
- [ ] `.env` file in `.gitignore` ✅

## Mac-Specific Commands

### Install Tools (using Homebrew)

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Azure CLI
brew install azure-cli

# Install GitHub CLI (optional, for managing secrets)
brew install gh

# Login to GitHub CLI
gh auth login

# Add secrets via CLI (alternative to web UI)
gh secret set VITE_AZURE_STORAGE_ACCOUNT_NAME --body "stvgcollection"
gh secret set VITE_AZURE_STORAGE_SAS_TOKEN --body "sv=2024-11-04&ss=t..."
```

### Date Commands (Mac vs Linux)

```bash
# Mac (BSD date)
EXPIRY_DATE=$(date -u -v+1y '+%Y-%m-%dT%H:%MZ')  # 1 year from now
EXPIRY_DATE=$(date -u -v+6m '+%Y-%m-%dT%H:%MZ')  # 6 months from now

# Linux (GNU date)
# EXPIRY_DATE=$(date -u -d "1 year" '+%Y-%m-%dT%H:%MZ')
```

### Check Build Output (Mac)

```bash
# Search built files for account name
grep -r "stvgcollection" dist/assets/

# Check file sizes
du -sh dist/

# List all built files
find dist -type f -name "*.js"
```

## Common Mistakes

1. ❌ Adding secrets to Azure Static Web Apps Configuration (doesn't work for Vite)
2. ❌ Using account key in production (security risk)
3. ❌ Forgetting to add production domain to CORS
4. ❌ Typos in secret names (they're case-sensitive)
5. ❌ Using `VITE_` prefix in Azure config but not in GitHub secrets

## Quick Reference

| Environment | Where to Set Variables | Method |
|-------------|----------------------|---------|
| **Local Dev** | `.env` file | Direct file |
| **Production Build** | GitHub Secrets | GitHub Actions |
| **NOT** Azure Static Web Apps Config | ❌ Doesn't work for Vite | N/A |

## Testing the Deployment

```bash
# 1. Make a change
echo "// test" >> src/App.tsx

# 2. Commit and push
git add .
git commit -m "Test deployment"
git push origin main

# 3. Watch GitHub Actions
# Visit: https://github.com/matteoemili/gamevault-tracker-azure/actions

# 4. After deployment completes, test production site
# Visit your Static Web App URL and test adding a game
```

## SAS Token Rotation (Security Best Practice)

Schedule regular token rotation:

```bash
# Every 6 months, generate new token
az storage account generate-sas \
  --account-name stvgcollection \
  --services t \
  --resource-types sco \
  --permissions rwdlacu \
  --expiry $(date -u -v+6m '+%Y-%m-%dT%H:%MZ') \
  --https-only \
  --output tsv

# Update GitHub Secret immediately
gh secret set VITE_AZURE_STORAGE_SAS_TOKEN --body "<new-token>"

# Trigger new deployment
git commit --allow-empty -m "Rotate SAS token"
git push origin main
```

## Support

If issues persist:
1. Check GitHub Actions logs for build errors
2. Check browser console for runtime errors
3. Verify CORS in Azure Portal
4. Test SAS token with curl (see TROUBLESHOOTING.md)

---

**Last Updated**: 2025-10-23  
**Platform**: Azure Static Web Apps  
**Framework**: Vite + React
