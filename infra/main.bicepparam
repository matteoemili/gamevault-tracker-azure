// ============================================================================
// GameVault Tracker - Production Parameters
// ============================================================================
// This parameters file configures the production deployment.
// For other environments, create additional .bicepparam files:
// - main.dev.bicepparam
// - main.staging.bicepparam
// ============================================================================

using './main.bicep'

// Environment configuration
param environment = 'prod'
param baseName = 'gamevault'

// Resource SKUs
param staticWebAppSku = 'Free'
param storageSkuName = 'Standard_LRS'

// GitHub repository configuration
// Note: Leave empty if linking manually or via Azure Portal
param repositoryUrl = ''
param repositoryBranch = 'main'

// CORS Configuration
// Add your production domains here after deployment
// The Static Web App URL will be added automatically
param corsAllowedOrigins = [
  // 'https://your-custom-domain.com'
  // The Static Web App URL will need to be added after first deployment
]

// Resource tags
param tags = {
  application: 'GameVault Tracker'
  environment: 'prod'
  managedBy: 'Bicep'
  repository: 'gamevault-tracker-azure'
}
