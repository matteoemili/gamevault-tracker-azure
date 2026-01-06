# 🎮 GameVault Tracker

A modern web application for tracking your video game collection, built with React, TypeScript, and Azure Table Storage.

## 🎯 Multi-Instance Deployment Support

**NEW**: This application now supports multiple isolated instances! Each deployment can have its own:
- ✅ Dedicated Azure resource group
- ✅ Unique instance identifier
- ✅ Independent data storage
- ✅ Ability to redeploy to existing instances

Perfect for:
- Multiple environments (dev, staging, production)
- Team member isolation
- Feature testing
- Customer demos
- A/B testing

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed multi-instance deployment instructions.

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

### Quick Deploy (New Instance)

Push to main branch to automatically create a new instance:

```bash
git add .
git commit -m "Deploy new instance"
git push origin main
```

The workflow will automatically:
1. Generate a unique instance ID
2. Create a dedicated resource group
3. Deploy all Azure resources
4. Build and deploy your application

### Redeploy to Existing Instance

Via GitHub Actions UI:
1. Go to **Actions** tab
2. Select **Azure Static Web Apps CI/CD**
3. Click **Run workflow**
4. Enter your instance ID (e.g., `abc12345`)
5. Select environment (prod/dev/staging)
6. Click **Run workflow**

### Multi-Instance Management

**View all instances**:
```bash
az group list --query "[?starts_with(name, 'rg-gamevault-')]" --output table
```

**Delete an instance**:
```bash
az group delete --name "rg-gamevault-{instanceId}" --yes
```

**Find your instance ID**:
- Check deployment logs in GitHub Actions
- Look at resource group tags in Azure Portal
- Use: `az group show --name rg-gamevault-{id} --query tags.instanceId`

For complete deployment documentation, see [DEPLOYMENT.md](./DEPLOYMENT.md).

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
