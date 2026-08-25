// ============================================================================
// Shared Service - Development Parameters
// ============================================================================
// Configures the ONE shared GameVault application for the dev environment.
// Use with: ./scripts/shared-service.sh validate --environment dev ...
//
// There is deliberately no instanceId parameter: logical instances are Table
// Storage records, not deployments.
// ============================================================================

using './main.bicep'

param environment = 'dev'
param baseName = 'gamevault'

// Minimal SKUs for development.
param staticWebAppSku = 'Free'
param storageSkuName = 'Standard_LRS'

// Manual deployment in dev; the application bundle is uploaded by CI/CD.
param repositoryUrl = ''
param repositoryBranch = 'main'

// Localhost origins for local development. The shared Front Door origin is
// added after route deployment by scripts/shared-service.sh.
param corsAllowedOrigins = [
  'http://localhost:5173'
  'http://localhost:5000'
  'http://localhost:3000'
  'http://127.0.0.1:5173'
]

param tags = {
  application: 'GameVault Tracker'
  environment: 'dev'
  managedBy: 'Bicep'
  repository: 'gamevault-tracker-azure'
}
