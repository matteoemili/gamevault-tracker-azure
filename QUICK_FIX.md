# 🚨 IMMEDIATE FIX - Production Not Working

## The Problem

Azure Static Web Apps **Configuration properties don't work for Vite** because:
- Vite bundles environment variables at **BUILD time**
- Azure config properties are **RUNTIME** settings
- You need to set variables in **GitHub Secrets** instead

## Quick Fix (5 minutes)

### Step 1: Add GitHub Secrets

1. Go to: https://github.com/matteoemili/gamevault-tracker-azure/settings/secrets/actions

2. Click **"New repository secret"**

3. Add **Secret #1**:
   ```
   Name:  VITE_AZURE_STORAGE_ACCOUNT_NAME
   Value: stvgcollection
   ```
   Click "Add secret"

4. Add **Secret #2**:
   ```
   Name:  VITE_AZURE_STORAGE_SAS_TOKEN
   Value: sv=2024-11-04&ss=t&srt=sco&sp=rwdlacu&se=2025-11-24T01:49:03Z&st=2025-10-23T16:34:03Z&spr=https&sig=EsJ69R%2BuaaaOPZ3D%2F9TcD4nfS%2FvYFr9rs8fWiF863HY%3D
   ```
   Click "Add secret"

### Step 2: Remove Azure Config (Optional Cleanup)

These don't work for Vite, so you can remove them:
1. Azure Portal > Your Static Web App
2. Settings > Configuration
3. Remove `VITE_AZURE_STORAGE_ACCOUNT_NAME` and `VITE_AZURE_STORAGE_ACCOUNT_KEY`

### Step 3: Update CORS for Production

1. Azure Portal > Storage Account `stvgcollection`
2. Settings > Resource sharing (CORS)
3. Table service tab
4. Add CORS rule:
   ```
   Allowed origins: https://ambitious-glacier-063139803.azurestaticapps.net
   Allowed methods: GET, POST, PUT, DELETE, OPTIONS
   Allowed headers: *
   Exposed headers: *
   Max age: 3600
   ```
5. Click Save

### Step 4: Trigger New Deployment

The GitHub workflow file has been updated. Now deploy:

```bash
# Option A: Push any change to main branch
git add .
git commit -m "Configure production environment"
git push origin main

# Option B: Merge storage branch to main
git checkout main
git merge storage
git push origin main
```

### Step 5: Wait for Build & Test

1. Watch deployment: https://github.com/matteoemili/gamevault-tracker-azure/actions
2. Wait for "Build and Deploy Job" to complete (2-3 minutes)
3. Visit your site: https://ambitious-glacier-063139803.azurestaticapps.net
4. Open browser DevTools (F12) > Console
5. Add a game - you should see:
   ```
   [Azure] Loading data from table: games
   [Azure] Saving 1 items to table: games
   [Azure] Successfully saved data to games
   ```
6. Refresh page - game should still be there! ✅

## Why This Matters

### ❌ What Doesn't Work:
```
Azure Static Web Apps Configuration
├── Application Settings (Runtime)
└── Does NOT affect Vite build variables
```

### ✅ What Works:
```
GitHub Secrets
├── Used during npm run build
├── Baked into JavaScript bundle
└── Available in production ✅
```

## Mac-Specific Quick Commands

```bash
# Check your current branch
git branch

# If you're on 'storage' branch, merge to main:
git checkout main
git merge storage
git push origin main

# Watch the deployment
open "https://github.com/matteoemili/gamevault-tracker-azure/actions"
```

## Verification Checklist

After deployment completes:

- [ ] Visit production site
- [ ] Open DevTools Console (⌘+Option+J on Mac)
- [ ] Add a test game
- [ ] Check for `[Azure]` log messages
- [ ] Refresh page (⌘+R)
- [ ] Game should still be there ✅

## If It Still Doesn't Work

Check this in browser console:
```javascript
// Should show your account name
console.log(import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_NAME);

// Should show 'Token loaded'
console.log(import.meta.env.VITE_AZURE_STORAGE_SAS_TOKEN ? 'Token loaded' : 'Token missing');
```

If it shows `undefined`:
1. Verify GitHub Secrets are spelled exactly: `VITE_AZURE_STORAGE_ACCOUNT_NAME`
2. Check workflow YAML has the `env:` section (already updated)
3. Re-run the deployment

## Security Note

🔒 **Never use ACCOUNT KEYS in production!** 

Your `.env` currently has a SAS token which is correct. The account key you added to Azure config:
- ❌ Wouldn't work anyway (wrong place)
- ❌ Would be a security risk if it did work
- ✅ Remove it and use SAS token in GitHub Secrets

---

**Next Steps**: See [DEPLOYMENT.md](DEPLOYMENT.md) for full details
