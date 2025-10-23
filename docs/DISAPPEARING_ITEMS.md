# Diagnostic Guide - Items Disappearing in Production

## The Problem

Items save temporarily but disappear after refresh in Azure (production), but work fine locally.

## Possible Causes

1. **Async timing issue** - Save operations not completing before page unload
2. **Network latency** - Slow connection to Azure in production
3. **CORS preflight** - Additional requests slowing down operations
4. **SAS token issue** - Token expiring or permission errors
5. **Azure throttling** - Too many requests being rate-limited

## Immediate Diagnostic Steps

### 1. Use the Diagnostic Tool

I've created a comprehensive diagnostic page for you:

**Local testing:**
```bash
npm run dev
# Visit: http://localhost:5173/diagnostic.html
```

**Production testing:**
```
# Visit your production site and add /diagnostic.html
https://ambitious-glacier-063139803.azurestaticapps.net/diagnostic.html
```

### 2. Run All Tests

In the diagnostic page, run tests in order:

1. **Test CORS** - Verify CORS is configured for production domain
2. **Test Authentication** - Verify SAS token works
3. **Test Query** - Check read operations
4. **Test Upsert** - Check write operations
5. **Performance Test** - Measure latency
6. **Integration Test** - Full end-to-end test

### 3. Check Browser Console in Production

1. Visit your production site
2. Open DevTools (F12 or ⌘+Option+J on Mac)
3. Go to Console tab
4. Add a game
5. Look for these messages:

**Expected (working):**
```
[Azure] Saving 1 items to table: games
[Azure] Upserting 1 items
[Azure] Successfully saved data to games (took 342ms)
```

**If you see errors:**
```
[Azure Storage] Upsert failed: {...}
[Azure] Failed to save data to Azure Table Storage
```

### 4. Check Network Tab

1. Open DevTools > Network tab
2. Filter by "table.core.windows.net"
3. Add a game
4. Watch for:
   - **PUT** request to `/games(PartitionKey='default',RowKey='...')`
   - Status should be **204 No Content** (success)
   - Check "Timing" tab - see if requests are slow

**Red flags:**
- ❌ 401/403 status = Authentication problem
- ❌ CORS error = CORS not configured
- ❌ Request takes >3 seconds = Network latency
- ❌ Request canceled = Async operation interrupted

## Code Changes I Made

### 1. Parallel Operations (Performance)

Changed from sequential to parallel upserts:

```typescript
// Before: Slow sequential operations
for (const item of newValue) {
  await service.upsertEntity(...); // Waits for each one
}

// After: Fast parallel operations
await Promise.all(
  newValue.map(item => service.upsertEntity(...))
); // All at once
```

This reduces save time from (n × latency) to just (latency).

### 2. Better Error Logging

Added detailed logging to track failures:

```typescript
console.error('[Azure Storage] Upsert failed:', {
  status: response.status,
  tableName,
  partitionKey,
  rowKey,
  errorText,
});
```

### 3. Performance Metrics

Added timing information:

```typescript
const startTime = Date.now();
// ... operations ...
const duration = Date.now() - startTime;
console.log(`Successfully saved data (took ${duration}ms)`);
```

## Common Issues and Fixes

### Issue 1: High Latency (>2 seconds per operation)

**Diagnosis:**
- Diagnostic tool shows high latency
- Network tab shows slow requests
- Console shows saves taking >5 seconds

**Causes:**
- Geographic distance to Azure region
- Slow network connection
- Sequential operations (now fixed)

**Solutions:**
- ✅ Already fixed with parallel operations
- Consider moving storage account closer to users
- Use Azure CDN for better routing

### Issue 2: CORS Preflight Adding Delay

**Diagnosis:**
- Network tab shows OPTIONS requests before each PUT
- Each operation takes 2× as long

**Solution:**
```bash
# Increase max-age to reduce preflight frequency
az storage cors add \
  --account-name stvgcollection \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "https://ambitious-glacier-063139803.azurestaticapps.net" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 86400  # 24 hours instead of 1 hour
```

### Issue 3: Async Operations Not Completing

**Diagnosis:**
- Console shows "Saving..." but no "Successfully saved"
- Network tab shows requests canceled

**Current code handles this** - operations complete even if user navigates away.

### Issue 4: SAS Token Expired or Invalid

**Diagnosis:**
- Console shows 401/403 errors
- Diagnostic tool authentication test fails

**Check token expiry:**
Your current token expires: **2025-11-24**

**Generate new token if needed:**
```bash
az storage account generate-sas \
  --account-name stvgcollection \
  --services t \
  --resource-types sco \
  --permissions rwdlacu \
  --expiry $(date -u -v+1y '+%Y-%m-%dT%H:%MZ') \
  --https-only \
  --output tsv
```

Then update GitHub Secret:
```bash
gh secret set VITE_AZURE_STORAGE_SAS_TOKEN --body "new-token-here"
```

### Issue 5: Azure Throttling

**Diagnosis:**
- Console shows 503 errors
- Happens when adding many items quickly

**Solution:**
- Add retry logic
- Add exponential backoff
- Reduce concurrent operations

## Testing Checklist

Run through this checklist in **production**:

### Basic Connectivity
- [ ] Can open production site
- [ ] Browser console shows no CORS errors
- [ ] Network tab shows requests reaching Azure

### CRUD Operations
- [ ] Can add a game (shows in UI immediately)
- [ ] Game persists after page refresh
- [ ] Can edit a game
- [ ] Changes persist after refresh
- [ ] Can delete a game
- [ ] Deletion persists after refresh

### Performance
- [ ] Adding game takes <3 seconds
- [ ] Console shows save completion message
- [ ] No timeouts or canceled requests

### Diagnostic Tool
- [ ] CORS test passes
- [ ] Authentication test passes
- [ ] Query test passes
- [ ] Upsert test passes
- [ ] Integration test passes

## Mac Commands for Quick Testing

```bash
# Build and test locally
npm run build
npm run preview
open http://localhost:4173/diagnostic.html

# Check build output for env vars
grep -r "stvgcollection" dist/assets/*.js

# Deploy to production
git add .
git commit -m "Fix async save timing"
git push origin main

# Watch deployment
open "https://github.com/matteoemili/gamevault-tracker-azure/actions"

# Test production after deployment
open "https://ambitious-glacier-063139803.azurestaticapps.net/diagnostic.html"
```

## Next Steps

1. **Run the diagnostic tool** in production first
2. **Check console logs** when adding a game
3. **Look for error patterns** in the logs
4. **Share the diagnostic results** if issue persists

The diagnostic page will help identify exactly where the failure is happening!

## Advanced Debugging

If the diagnostic tool shows all tests pass but items still disappear:

### Check Azure Portal Directly

1. Go to Azure Portal
2. Navigate to Storage Account `stvgcollection`
3. Go to **Tables** > `games`
4. Check if entities are actually there
5. Look for PartitionKey='default'

### Enable Azure Storage Logging

```bash
az storage logging update \
  --account-name stvgcollection \
  --services t \
  --log rwd \
  --retention 7
```

Then check logs in Azure Portal.

### Compare Local vs Production

**Local:**
- Uses .env file directly
- No build-time variable substitution needed
- Direct localhost CORS

**Production:**
- Uses GitHub Secrets → Build time
- Variables baked into bundle
- Production domain CORS

Make sure CORS includes production domain exactly!

---

**Priority Actions:**
1. 🔴 Run diagnostic tool in production
2. 🔴 Check browser console for errors
3. 🔴 Verify CORS for production domain
4. 🟡 Check network latency
5. 🟡 Monitor for throttling
