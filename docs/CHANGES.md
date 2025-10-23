# Changelog - Azure Table Storage Migration

## [2.0.0] - 2025-10-23

### 🚀 Major Changes

#### Migrated from GitHub Spark KV Storage to Azure Table Storage
- **Breaking Change**: Application now requires Azure Storage Account
- Removed dependency on `@github/spark/hooks`
- Implemented Azure Table Storage REST API integration
- All data now stored in cloud (Azure Tables)

### ✨ New Features

#### Azure Integration
- **Azure Table Storage Client** (`src/lib/azure-storage.ts`)
  - Full CRUD operations via REST API
  - SAS token authentication
  - Query filtering support
  - Batch operations support
  
- **Custom React Hooks** (`src/hooks/use-azure-table.ts`)
  - `useAzureTableList<T>`: List management with automatic sync
  - Loading and error states
  - Optimistic updates for better UX
  
- **Configuration Management** (`src/lib/azure-config.ts`)
  - Environment-based configuration
  - Validation functions
  - Configurable table names

#### Developer Experience
- **Comprehensive Documentation**
  - `AZURE_SETUP.md`: Complete setup guide with CORS, SAS tokens, troubleshooting
  - `MIGRATION.md`: Detailed migration information
  - Updated `README.md` with new instructions
  
- **Environment Configuration**
  - `.env.example`: Template for required variables
  - TypeScript definitions for environment variables
  - Validation on startup

### 🔧 Technical Improvements

#### Architecture
- Cleaner separation of concerns
- Type-safe API client
- Error handling throughout
- Async state management

#### Security
- SAS token-based authentication
- HTTPS-only connections
- Secrets in environment variables (not in code)
- Fine-grained permission control

#### Performance
- Optimistic UI updates
- Local state caching
- Efficient entity queries

### 📝 Files Changed

#### Added
- `src/lib/azure-storage.ts` - Azure REST API client
- `src/lib/azure-config.ts` - Configuration management
- `src/hooks/use-azure-table.ts` - Custom React hooks
- `.env.example` - Environment variable template
- `AZURE_SETUP.md` - Setup documentation
- `MIGRATION.md` - Migration guide
- `setup.sh` - Quick start script
- `CHANGES.md` - This file

#### Modified
- `src/App.tsx` - Updated to use Azure hooks
- `src/vite-end.d.ts` - Added environment variable types
- `README.md` - Updated documentation

### 🗄️ Data Structure

#### Azure Tables Created
- `games` - Game collection data
- `categories` - Platform categories

#### Entity Structure
Each entity uses:
- `PartitionKey`: "default" (single partition)
- `RowKey`: Item ID (game.id or category.id)
- `data`: JSON-serialized object

### 📋 Migration Checklist

For users migrating from GitHub Spark version:

- [ ] Create Azure Storage Account
- [ ] Create `games` and `categories` tables
- [ ] Configure CORS for your domain
- [ ] Generate SAS token with Table permissions
- [ ] Update `.env` with Azure credentials
- [ ] Export data from old version (if needed)
- [ ] Import data to new version
- [ ] Verify data sync to Azure

### ⚙️ Configuration

#### Required Environment Variables
```env
VITE_AZURE_STORAGE_ACCOUNT_NAME=your-account-name
VITE_AZURE_STORAGE_SAS_TOKEN=your-sas-token
```

#### Optional Environment Variables
```env
VITE_AZURE_STORAGE_ENDPOINT=custom-endpoint
VITE_AZURE_GAMES_TABLE_NAME=games
VITE_AZURE_CATEGORIES_TABLE_NAME=categories
```

### 🔒 Security Notes

- Never commit `.env` to version control (already in `.gitignore`)
- Rotate SAS tokens regularly
- Use least-privilege permissions
- Monitor Azure Storage access logs
- Consider Azure Key Vault for production

### 🐛 Known Issues

- None at this time

### 🚧 Breaking Changes

1. **Requires Azure Setup**: Must have Azure Storage Account configured
2. **New Environment Variables**: Required for application to run
3. **Hook API Changed**: Additional return values (loading, error states)
4. **Internet Required**: Cloud storage requires network connection

### 📚 Documentation

- **Setup Guide**: See `AZURE_SETUP.md`
- **Migration Info**: See `MIGRATION.md`
- **Quick Start**: Run `bash setup.sh`

### 🙏 Acknowledgments

- Original GitHub Spark template for rapid prototyping
- Azure Table Storage for cloud persistence
- React and Vite for excellent developer experience

### 📞 Support

- Read `AZURE_SETUP.md` for comprehensive setup instructions
- Check `MIGRATION.md` for migration details
- Open an issue on GitHub for bugs or questions

---

## Previous Versions

### [1.0.0] - Initial Release
- Built with GitHub Spark
- Local key-value storage
- Game collection management
- Category management
- Import/export functionality
