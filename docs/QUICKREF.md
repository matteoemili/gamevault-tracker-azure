# Quick Reference - Azure Table Storage Integration

## 🚀 Quick Start

```bash
# 1. Clone and setup
git clone <repo-url>
cd gamevault-tracker-azure
bash setup.sh

# 2. Configure Azure credentials
# Edit .env file with your Azure credentials

# 3. Run development server
npm run dev
```

## 📋 Environment Variables

```env
# Required
VITE_AZURE_STORAGE_ACCOUNT_NAME=mystorageaccount
VITE_AZURE_STORAGE_SAS_TOKEN=?sv=2022-11-02&ss=t&srt=sco&sp=rwdlacu&...

# Optional (with defaults)
VITE_AZURE_STORAGE_ENDPOINT=https://mystorageaccount.table.core.windows.net
VITE_AZURE_GAMES_TABLE_NAME=games
VITE_AZURE_CATEGORIES_TABLE_NAME=categories
```

## 🔧 Azure Setup (CLI)

```bash
# Variables
RESOURCE_GROUP="gamevault-rg"
STORAGE_ACCOUNT="gamevaulttracker"
LOCATION="eastus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

# Create tables
az storage table create --name games --account-name $STORAGE_ACCOUNT
az storage table create --name categories --account-name $STORAGE_ACCOUNT

# Configure CORS
az storage cors add \
  --account-name $STORAGE_ACCOUNT \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "http://localhost:5173" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600

# Generate SAS token (valid for 1 year)
az storage account generate-sas \
  --account-name $STORAGE_ACCOUNT \
  --services t \
  --resource-types sco \
  --permissions rwdlacu \
  --expiry $(date -u -d "1 year" '+%Y-%m-%dT%H:%MZ') \
  --https-only \
  --output tsv
```

## 📊 Table Structure

### Games Table
```typescript
{
  PartitionKey: "default",
  RowKey: "uuid-v4",
  data: JSON.stringify({
    id: string,
    name: string,
    platform: string,
    acquired: boolean,
    targetPrice?: number,
    priority?: boolean,
    purchasePrice?: number,
    acquisitionDate?: string,
    seller?: string,
    notes?: string
  })
}
```

### Categories Table
```typescript
{
  PartitionKey: "default",
  RowKey: "category-id",  // e.g., "PS1", "PS2"
  data: JSON.stringify({
    id: string,
    name: string,
    logoUrl: string
  })
}
```

## 💻 Code Examples

### Using the Hook
```typescript
import { useAzureTableList } from '@/hooks/use-azure-table';
import { getAzureConfig } from '@/lib/azure-config';

function MyComponent() {
  const azureConfig = getAzureConfig();
  const [games, setGames, loading, error] = useAzureTableList<Game>(
    azureConfig.tables.games,
    []
  );

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error.message}</div>;

  return (
    <div>
      {games.map(game => (
        <div key={game.id}>{game.name}</div>
      ))}
    </div>
  );
}
```

### Direct API Usage
```typescript
import { AzureTableStorageService } from '@/lib/azure-storage';

const service = new AzureTableStorageService({
  accountName: 'mystorageaccount',
  sasToken: '?sv=...',
});

// Query all entities
const games = await service.queryEntities('games');

// Get specific entity
const game = await service.getEntity('games', 'default', 'game-123');

// Upsert entity
await service.upsertEntity('games', {
  PartitionKey: 'default',
  RowKey: 'game-123',
  data: JSON.stringify({ name: 'My Game', ... })
});

// Delete entity
await service.deleteEntity('games', 'default', 'game-123');
```

## 🔍 Common Commands

```bash
# Development
npm run dev          # Start dev server
npm run build        # Build for production
npm run preview      # Preview production build

# Azure CLI
az storage table list --account-name <name>           # List tables
az storage entity query --table-name games --account-name <name>  # Query entities
az storage cors list --services t --account-name <name>           # Show CORS rules
```

## 🐛 Troubleshooting

### CORS Error
```javascript
// Error: CORS policy blocked
// Fix: Check Azure Portal > Storage Account > CORS settings
// Ensure origin matches exactly: http://localhost:5173
```

### 401 Unauthorized
```javascript
// Error: 401 Unauthorized
// Fix: Check SAS token is valid and not expired
// Verify token has permissions: rwdlacu (read,write,delete,list,add,create,update)
```

### Table Not Found
```javascript
// Error: ResourceNotFound
// Fix: Create tables in Azure Portal
// Table names: 'games' and 'categories'
```

### Environment Variables Not Loaded
```javascript
// Error: VITE_AZURE_STORAGE_ACCOUNT_NAME is undefined
// Fix: Create .env file in project root
// Restart dev server after creating .env
```

## 📚 Documentation Links

- **Full Setup Guide**: [AZURE_SETUP.md](./AZURE_SETUP.md)
- **Migration Info**: [MIGRATION.md](./MIGRATION.md)
- **Changelog**: [CHANGES.md](./CHANGES.md)
- **Azure Docs**: https://docs.microsoft.com/azure/storage/tables/

## 🔐 Security Checklist

- [ ] `.env` file in `.gitignore`
- [ ] SAS token has minimal required permissions
- [ ] SAS token has expiration date
- [ ] CORS configured for specific origins only
- [ ] HTTPS-only connections enforced
- [ ] Secrets stored in environment variables, not code

## 📞 Getting Help

1. Check [AZURE_SETUP.md](./AZURE_SETUP.md) troubleshooting section
2. Review Azure Storage logs in Azure Portal
3. Check browser console for errors
4. Open an issue on GitHub

---

**Last Updated**: 2025-10-23
