# Environment Variables Flow - Automated CI/CD Approach

## Current Implementation (Automated)

**This application now uses a fully automated CI/CD pipeline that eliminates manual secret management.**

Environment variables are:
1. ✅ Generated dynamically during deployment (SAS token)
2. ✅ Retrieved from infrastructure outputs (storage account name, table names)
3. ✅ Injected at build time via `.env.production` file
4. ✅ Baked into the JavaScript bundle by Vite

## Legacy Documentation: The Problem We Solved

## Current Automated Flow

```
┌─────────────────────────────────────────────────────────────┐
│  INFRASTRUCTURE JOB                                         │
│  ✅ Deploys Azure Resources                                 │
├─────────────────────────────────────────────────────────────┤
│  1. Deploy Bicep templates (storage, static web app)        │
│  2. Extract deployment outputs                              │
│     • Storage account name                                  │
│     • Static Web App URL                                    │
│     • Table names (games, categories)                       │
│  3. Configure CORS automatically                            │
│     • Adds Static Web App URL to storage CORS rules        │
└─────────────────────────────────────────────────────────────┘
          ↓
┌─────────────────────────────────────────────────────────────┐
│  BUILD JOB                                                  │
│  ✅ Generates SAS Token & Builds Application                │
├─────────────────────────────────────────────────────────────┤
│  1. Retrieve storage account key (secure)                   │
│  2. Generate SAS token (1 year expiry)                      │
│  3. Create .env.production file with:                       │
│     • Storage account name (from infrastructure)            │
│     • SAS token (freshly generated)                         │
│     • Table names (from infrastructure)                     │
│  4. Run npm run build                                       │
│     • Vite reads .env.production                            │
│     • Variables baked into JavaScript bundle                │
│  5. Deploy dist/ folder to Azure Static Web Apps            │
└─────────────────────────────────────────────────────────────┘
```

## Legacy Documentation: Why Manual Secrets Don't Work

```
┌─────────────────────────────────────────────────────────────┐
│  AZURE STATIC WEB APPS CONFIGURATION (Runtime Settings)    │
│  ❌ DOES NOT WORK FOR VITE                                 │
├─────────────────────────────────────────────────────────────┤
│  These settings are for:                                    │
│  • Backend APIs                                             │
│  • Server-side rendering                                    │
│  • Runtime environment variables                            │
│                                                              │
│  But Vite needs variables at BUILD time, not runtime!       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  GITHUB SECRETS → BUILD PROCESS                             │
│  ✅ CORRECT WAY FOR VITE                                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. GitHub Secrets stored securely                          │
│     VITE_AZURE_STORAGE_ACCOUNT_NAME = "stvgcollection"      │
│     VITE_AZURE_STORAGE_SAS_TOKEN = "sv=..."                 │
│                                                              │
│  2. GitHub Action runs (on push to main)                    │
│     └─> npm install                                         │
│     └─> npm run build (with env vars)                       │
│                                                              │
│  3. Vite build process                                      │
│     └─> Reads import.meta.env.VITE_*                        │
│     └─> Replaces in code with actual values                 │
│     └─> Creates dist/ folder                                │
│                                                              │
│  4. Variables are now BAKED INTO the JavaScript             │
│     dist/assets/index-abc123.js contains:                   │
│     "stvgcollection" (hardcoded in the bundle)              │
│                                                              │
│  5. Deploy dist/ folder to Azure Static Web Apps            │
│     └─> Static files are served                             │
│     └─> JavaScript already has the values                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Build-time vs Runtime

```
BUILD TIME (GitHub Actions)          RUNTIME (Browser)
├─ npm run build                     ├─ User visits site
├─ Vite reads .env vars              ├─ Downloads JS bundle
├─ Replaces in source code           ├─ JS runs in browser
├─ Creates dist/ folder              ├─ Values already in code
└─ Variables → JavaScript            └─ No .env lookup needed
     ✅ Works                             ✅ Works

Azure Config Properties
├─ Set at deployment
├─ Available at runtime
├─ But build already completed
└─ Vite can't access them
     ❌ Too late!
```

## Comparison

| Aspect | GitHub Secrets | Azure Config |
|--------|---------------|--------------|
| **When available** | Build time | Runtime |
| **For Vite** | ✅ Works | ❌ Doesn't work |
| **For backend APIs** | ❌ No access | ✅ Works |
| **Security** | ✅ Hidden | ✅ Hidden |
| **Update method** | Re-deploy | Edit in portal |

## The Correct Flow

```
You (Developer)
    │
    ├─> 1. Add secrets to GitHub
    │      Repository Settings > Secrets
    │      • VITE_AZURE_STORAGE_ACCOUNT_NAME
    │      • VITE_AZURE_STORAGE_SAS_TOKEN
    │
    ├─> 2. Update workflow YAML
    │      env:
    │        VITE_AZURE_STORAGE_ACCOUNT_NAME: ${{ secrets.VITE_... }}
    │        VITE_AZURE_STORAGE_SAS_TOKEN: ${{ secrets.VITE_... }}
    │
    ├─> 3. Push to main branch
    │      git push origin main
    │
    └─> 4. GitHub Action runs
            │
            ├─> Checkout code
            ├─> Set environment variables from secrets
            ├─> Run: npm install
            ├─> Run: npm run build
            │   └─> Vite sees VITE_* env vars
            │   └─> Replaces in code
            │   └─> Output: dist/ with baked values
            │
            └─> Deploy dist/ to Azure
                └─> Site works! ✅
```

## Why Your Current Setup Doesn't Work

```
❌ CURRENT (Broken)
┌──────────────────────────────────┐
│ Azure Static Web Apps Config    │
│ • VITE_AZURE_STORAGE_ACCOUNT_KEY │ ← Added here
│ • VITE_AZURE_STORAGE_ACCOUNT_NAME│ ← Added here
└──────────────────────────────────┘
         │
         │ These are runtime settings
         │ Build already completed
         │ Vite can't see them
         ↓
    ❌ Variables undefined in production


✅ CORRECT (Working)
┌──────────────────────────────────┐
│ GitHub Repository Secrets        │
│ • VITE_AZURE_STORAGE_ACCOUNT_NAME│ ← Add here
│ • VITE_AZURE_STORAGE_SAS_TOKEN   │ ← Add here
└──────────────────────────────────┘
         │
         │ Used during build
         │ GitHub Action sets env vars
         │ Vite reads them
         ↓
    ✅ Variables in production bundle
```

## Security Comparison

```
SAS TOKEN (Current - Correct ✅)
├─ Limited permissions (Table only)
├─ Has expiration date
├─ Can be revoked
├─ Specific to one service
└─ Safe for client-side code

ACCOUNT KEY (Dangerous ❌)
├─ FULL access to entire storage account
├─ Never expires
├─ Rotate = regenerate for all apps
├─ Controls everything
└─ NEVER use in client-side code
```

## Mac Terminal Quick Reference

```bash
# Check current branch
git branch
# * storage  ← You're here
#   main

# Switch to main and merge
git checkout main
git merge storage
git push origin main

# Open GitHub Actions in browser
open "https://github.com/matteoemili/gamevault-tracker-azure/actions"

# After deployment, open production site
open "https://ambitious-glacier-063139803.azurestaticapps.net"

# Check local build (test)
npm run build
grep -r "stvgcollection" dist/assets/*.js
# Should show your account name in the built files
```

## Checklist

### ✅ What You Should Have Done:
- [x] Add `VITE_AZURE_STORAGE_ACCOUNT_NAME` to GitHub Secrets
- [x] Add `VITE_AZURE_STORAGE_SAS_TOKEN` to GitHub Secrets  
- [x] Updated workflow YAML (already done)
- [ ] Add production domain to CORS
- [ ] Push to main branch
- [ ] Wait for deployment
- [ ] Test in production

### ❌ What You Should NOT Do:
- [ ] ~~Use Azure Static Web Apps Configuration for Vite vars~~
- [ ] ~~Use account key in production~~
- [ ] ~~Commit .env to git~~

---

**TL;DR**: 
1. GitHub Secrets → Build Time → ✅ Works
2. Azure Config → Runtime → ❌ Too late for Vite
