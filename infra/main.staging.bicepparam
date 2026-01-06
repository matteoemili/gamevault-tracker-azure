// ============================================================================
// GameVault Tracker - Staging Environment Parameters
// ============================================================================
// This parameters file configures the staging deployment.
// Use this for pre-production testing and validation.
// ============================================================================

using './main.bicep'

// Environment configuration
param environment = 'staging'
param baseName = 'gamevault'

// Instance identifier for multi-instance deployments
// Leave empty to generate a new random instance ID
// For redeployment to existing instance, provide the instance ID from previous deployment
// Example: param instanceId = 'abc12345'
param instanceId = ''

// Resource SKUs
param staticWebAppSku = 'Free'
param storageSkuName = 'Standard_LRS'

// GitHub repository configuration
// Note: Leave empty if linking manually or via Azure Portal
param repositoryUrl = ''
param repositoryBranch = 'main'

// CORS Configuration
// Staging environment typically includes localhost and staging domains
param corsAllowedOrigins = [
  // Add any additional staging origins here
]

// Resource tags
param tags = {
  application: 'GameVault Tracker'
  environment: 'staging'
  managedBy: 'Bicep'
  repository: 'gamevault-tracker-azure'
}
