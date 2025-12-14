// ============================================================================
// GameVault Tracker - Development Parameters
// ============================================================================
// This parameters file configures the development deployment.
// Use this for local development and testing.
// ============================================================================

using './main.bicep'

// Environment configuration
param environment = 'dev'
param baseName = 'gamevault'

// Resource SKUs - use minimal SKUs for dev
param staticWebAppSku = 'Free'
param storageSkuName = 'Standard_LRS'

// GitHub repository configuration
// Leave empty for dev - manual deployment
param repositoryUrl = ''
param repositoryBranch = 'main'

// CORS Configuration - includes localhost for development
param corsAllowedOrigins = [
  'http://localhost:5173'
  'http://localhost:5000'
  'http://localhost:3000'
  'http://127.0.0.1:5173'
]

// Resource tags
param tags = {
  application: 'GameVault Tracker'
  environment: 'dev'
  managedBy: 'Bicep'
  repository: 'gamevault-tracker-azure'
}
