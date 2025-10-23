# Troubleshooting: Games Not Persisting

## Issue
Games disappear after page refresh, indicating data is not being saved to Azure Table Storage.

## Debugging Steps

### 1. Check Browser Console
Open your browser's Developer Tools (F12) and check the Console tab for:

```
[Azure] Loading data from table: games
[Azure] Loaded X entities from games
[Azure] Parsed X items from games
[Azure] Saving X items to table: games
[Azure] Upserting X items
[Azure] Successfully saved data to games
```

### 2. Check for Errors
Look for error messages in the console:
- **CORS errors**: Need to configure CORS in Azure Portal
- **401/403 errors**: Authentication issue with SAS token or account key
- **404 errors**: Table doesn't exist
- **Network errors**: Check internet connection

### 3. Verify Azure Configuration

#### Check Environment Variables
```bash
# In your terminal, run:
cat .env

# Should show:
VITE_AZURE_STORAGE_ACCOUNT_NAME=stvgcollection
VITE_AZURE_STORAGE_SAS_TOKEN=sv=...
```

#### Verify in Browser Console
```javascript
// In browser console, check if env vars are loaded:
console.log(import.meta.env.VITE_AZURE_STORAGE_ACCOUNT_NAME);
console.log(import.meta.env.VITE_AZURE_STORAGE_SAS_TOKEN ? 'Token loaded' : 'Token missing');
```

### 4. Check Azure Portal

#### Verify Tables Exist
1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your Storage Account: `stvgcollection`
3. Go to **Tables** under **Data storage**
4. Verify tables exist:
   - `games` ✅
   - `categories` ✅

#### Check CORS Configuration
1. In Storage Account, go to **Settings** > **Resource sharing (CORS)**
2. Select **Table service** tab
3. Verify CORS rule exists:
   - **Allowed origins**: `http://localhost:5173` or `*` for testing
   - **Allowed methods**: GET, POST, PUT, DELETE, OPTIONS
   - **Allowed headers**: `*`
   - **Exposed headers**: `*`

### 5. Test Authentication

#### Using SAS Token (Current Method)
Your current token expires: **2025-11-24**

Check if token is valid:
```bash
# Test with curl
curl "https://stvgcollection.table.core.windows.net/games?sv=2024-11-04&ss=t&srt=sco&sp=rwdlacu&se=2025-11-24T01:49:03Z&st=2025-10-23T16:34:03Z&spr=https&sig=EsJ69R%2BuaaaOPZ3D%2F9TcD4nfS%2FvYFr9rs8fWiF863HY%3D" \
  -H "Accept: application/json;odata=nometadata" \
  -H "x-ms-version: 2024-11-04"
```

Expected: 200 OK with `{"value": [...]}`
Error: 403 = invalid token, 404 = table doesn't exist

#### Using Account Key (Alternative)
If you want to use account key instead:

1. Get your account key from Azure Portal:
   - Storage Account > **Security + networking** > **Access keys**
   - Copy **key1** (long base64 string)

2. Update `.env`:
   ```env
   VITE_AZURE_STORAGE_ACCOUNT_NAME=stvgcollection
   # Comment out or remove SAS token:
   # VITE_AZURE_STORAGE_SAS_TOKEN=...
   # Add account key:
   VITE_AZURE_STORAGE_ACCOUNT_KEY=your-base64-key-here
   ```

3. **WARNING**: Account keys provide full access. Use only for testing!

### 6. Check Network Tab

1. Open Developer Tools > **Network** tab
2. Filter by "table.core.windows.net"
3. Add a game and watch for requests:
   - `PUT` to `/games(PartitionKey='default',RowKey='...')`
   - Should return **204 No Content** (success)
   - **401/403**: Auth problem
   - **CORS error**: CORS not configured

### 7. Restart Dev Server

After changing `.env`, always restart:
```bash
# Stop dev server (Ctrl+C)
npm run dev
```

### 8. Common Issues and Fixes

#### Issue: "CORS policy blocked"
**Fix**: Configure CORS in Azure Portal (see step 4)

#### Issue: "401 Unauthorized"
**Fix**: 
- Check SAS token hasn't expired
- Verify token has permissions: `sp=rwdlacu`
- Regenerate token if needed

#### Issue: "404 Not Found"
**Fix**: Create tables in Azure Portal

#### Issue: Data saves but doesn't load
**Check**:
- Console shows "Loaded 0 entities"
- Data might be in wrong partition
- Check PartitionKey is 'default'

#### Issue: Games save locally but not to Azure
**Check**:
- Console shows save attempt
- Check for error messages after "Saving X items"
- Network tab shows failed requests

### 9. Manual Data Check

Check data directly in Azure Portal:
1. Storage Account > **Tables**
2. Click on `games` table
3. Should see entities with PartitionKey='default'

Or use Azure Storage Explorer (free tool):
https://azure.microsoft.com/features/storage-explorer/

### 10. Enable Detailed Logging

The latest code includes detailed console logging. You should see:
```
[Azure] Loading data from table: games
[Azure] Loaded X entities from games
[Azure] Parsed X items from games
[Azure] Saving X items to table: games
[Azure] Deleting X items (if any removed)
[Azure] Upserting X items
[Azure] Successfully saved data to games
```

If you don't see these messages, the hooks aren't being called properly.

## Quick Test Script

Run this in your browser console to test the Azure connection:

```javascript
// Test configuration
const config = {
  accountName: 'stvgcollection',
  sasToken: 'sv=2024-11-04&ss=t&srt=sco&sp=rwdlacu&se=2025-11-24T01:49:03Z&st=2025-10-23T16:34:03Z&spr=https&sig=EsJ69R%2BuaaaOPZ3D%2F9TcD4nfS%2FvYFr9rs8fWiF863HY%3D'
};

// Test query
fetch(`https://${config.accountName}.table.core.windows.net/games?${config.sasToken}`, {
  headers: {
    'Accept': 'application/json;odata=nometadata',
    'x-ms-version': '2024-11-04'
  }
})
.then(r => r.json())
.then(data => console.log('Success!', data))
.catch(err => console.error('Error:', err));
```

## Still Not Working?

1. Check all console messages (including errors)
2. Verify CORS is configured for your exact origin
3. Test with `*` for allowed origins temporarily
4. Try using account key instead of SAS token
5. Check Azure Storage Account firewall settings
6. Verify network connectivity to Azure

## Need More Help?

Share the following information:
- Console logs (all [Azure] messages)
- Network tab screenshots of failed requests
- Azure CORS configuration screenshot
- Any error messages

---

**Last Updated**: 2025-10-23
