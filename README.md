# 🎮 GameVault Tracker

A modern web application for tracking your video game collection, built with React, TypeScript, and Azure Table Storage.

## 🎯 Shared Service Deployment Model

**Current shared path**: New environments use one shared GameVault application
deployment behind one protected Azure Front Door public address per environment
(`dev`, `staging`, `prod`). Logical instances are Azure Table Storage records
reserved by `scripts/logical-instance.sh`; creating one does **not** create a
resource group, Static Web App, storage account, or Front Door endpoint.

Shared service lifecycle:

```bash
./scripts/shared-service.sh <validate|what-if|deploy|verify|status|inventory> [options]
```

Core options are `--environment`, `--subscription-id`,
`--shared-resource-group`, `--platform-resource-group`,
`--front-door-profile`, `--location`, `--base-name`, `--local-only`,
`--confirm`, and `--non-interactive`. Use `--local-only` only with
`validate`; use `--confirm` for `deploy`.

Logical instance lifecycle:

```bash
./scripts/logical-instance.sh <create|list|show|retire> [options]
```

The current CLI usage block lists `--environment`, `--subscription-id`,
`--storage-account-name`, `--table-name`, `--logical-instance-id`,
`--display-name`, `--state`, `--confirm`, and `--non-interactive`. These
commands manage shared Table Storage records only.

### Legacy per-instance path

The older multi-instance model, where each instance had its own resource group,
storage account, Static Web App, and public route, is retained only for existing
legacy instances and explicit operator-controlled maintenance. Do not use it for
new logical instances. See [DEPLOYMENT.md](./DEPLOYMENT.md) for legacy details.

## Features

- 📚 **Collection Management**: Track games you own and games on your wishlist
- 🎯 **Priority System**: Mark high-priority games you want to acquire
- 💰 **Price Tracking**: Set target prices and track actual purchase prices
- 🏷️ **Categories**: Organize games by platform (PlayStation, PC, etc.)
- 📊 **Filtering**: Filter by platform, ownership status, and priority
- 🔍 **Search**: Quickly find games in your collection
- 📤 **Import/Export**: Backup and restore your collection data
- ☁️ **Cloud Storage**: Data stored in Azure Table Storage for access anywhere

## Technology Stack

- **Frontend**: React 18 + TypeScript + Vite
- **UI Components**: Radix UI + Tailwind CSS
- **Storage**: Azure Table Storage (REST API)
- **Icons**: Phosphor Icons
- **Hosting**: Azure Static Web Apps

## Getting Started

### Prerequisites

- Node.js 20 or higher
- Azure Storage Account (see [Azure Setup Guide](./AZURE_SETUP.md))

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/gamevault-tracker-azure.git
   cd gamevault-tracker-azure
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Set up Azure Table Storage:
   - Follow the comprehensive [Azure Setup Guide](./AZURE_SETUP.md)
   - Create a Storage Account and tables
   - Configure CORS settings
   - Generate a SAS token

4. Configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your Azure credentials
   ```

5. Start the development server:
   ```bash
   npm run dev
   ```

6. Open your browser to `http://localhost:5173`

## Azure Migration

This application was originally built with GitHub Spark and has been migrated to use Azure Table Storage for persistent cloud storage.

### Key Changes

- ✅ Removed dependency on GitHub Spark's key-value storage
- ✅ Implemented Azure Table Storage REST API client
- ✅ Created custom React hooks for Azure storage operations
- ✅ Configured environment-based setup
- ✅ Added comprehensive CORS support

For detailed migration information, see [AZURE_SETUP.md](./AZURE_SETUP.md).

## Configuration

Environment variables (`.env`):

```env
VITE_AZURE_STORAGE_ACCOUNT_NAME=your-storage-account-name
VITE_AZURE_STORAGE_SAS_TOKEN=your-sas-token
VITE_AZURE_GAMES_TABLE_NAME=games
VITE_AZURE_CATEGORIES_TABLE_NAME=categories
```

See [.env.example](./.env.example) for a template.

## Project Structure

```
src/
├── components/          # React components
│   ├── ui/             # Reusable UI components (Radix UI)
│   ├── GameCard.tsx    # Game display card
│   ├── GameDialog.tsx  # Add/edit game modal
│   └── ...
├── hooks/              # Custom React hooks
│   └── use-azure-table.ts  # Azure Table Storage hooks
├── lib/                # Utility libraries
│   ├── azure-storage.ts    # Azure REST API client
│   ├── azure-config.ts     # Configuration management
│   ├── types.ts            # TypeScript types
│   └── utils.ts
└── App.tsx             # Main application component
```

## Development

### Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run ESLint

### Code Style

- TypeScript for type safety
- ESLint for code quality
- Tailwind CSS for styling
- React hooks for state management

## Deployment

### Shared Deployment

Validate locally without Azure mutation:

```bash
./scripts/shared-service.sh validate --environment dev --local-only
```

Deploy one shared service for an environment:

```bash
./scripts/shared-service.sh deploy \
  --environment dev \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group rg-gamevault-shared-dev \
  --platform-resource-group rg-gamevault-platform-dev \
  --front-door-profile gvt-afd-dev \
  --location westeurope \
  --confirm
```

Inspect the single public address and health:

```bash
./scripts/shared-service.sh status \
  --environment dev \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group rg-gamevault-shared-dev \
  --platform-resource-group rg-gamevault-platform-dev \
  --front-door-profile gvt-afd-dev | jq .
```

Add or inspect logical instances with `scripts/logical-instance.sh`; those
actions are data-plane operations and do not change shared infrastructure.

### Legacy Per-Instance Management

Existing legacy instances may still be inspected with Azure CLI queries such as:

```bash
az group list --query "[?starts_with(name, 'rg-gamevault-')]" --output table
```

Delete or reroute legacy resources only as part of an explicit migration or
cleanup activity. Shared-service rollback never runs legacy unregister or
cleanup commands.

### Azure Static Web Apps

This application is configured for deployment to Azure Static Web Apps:

1. Push to GitHub repository
2. GitHub Actions automatically builds and deploys
3. Configure environment variables in Azure Portal

See `.github/workflows/azure-static-web-apps-*.yml` for CI/CD configuration.

### Manual Deployment

```bash
npm run build
# Deploy the dist/ folder to your hosting service
```

## Security

- 🔒 SAS tokens for secure Azure access
- 🔒 HTTPS-only connections
- 🔒 Environment-based configuration
- 🔒 No credentials in source code

**Important**: Never commit `.env` files to version control!

## Troubleshooting

Common issues and solutions are documented in the [Azure Setup Guide](./AZURE_SETUP.md#troubleshooting).

Quick checks:
- ✅ Azure tables created (`games` and `categories`)
- ✅ CORS configured correctly
- ✅ SAS token valid and not expired
- ✅ Environment variables set correctly

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [GitHub Spark](https://githubnext.com/projects/spark) (originally)
- Migrated to Azure Table Storage for production use
- UI components from [Radix UI](https://www.radix-ui.com/)
- Icons from [Phosphor Icons](https://phosphoricons.com/)

## Support

For issues and questions:
- 📖 Check the [Azure Setup Guide](./AZURE_SETUP.md)
- 🐛 Open an issue on GitHub
- 📧 Contact the maintainers

---

Made with ❤️ and ☕
