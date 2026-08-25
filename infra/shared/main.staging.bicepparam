// ============================================================================
// Shared Service - Staging Parameters
// ============================================================================
// Configures the ONE shared GameVault application for the staging environment.
// Use with: ./scripts/shared-service.sh validate --environment staging ...
//
// There is deliberately no instanceId parameter: logical instances are Table
// Storage records, not deployments.
// ============================================================================

using './main.bicep'

param environment = 'staging'
param baseName = 'gamevault'

param staticWebAppSku = 'Free'
param storageSkuName = 'Standard_LRS'

param repositoryUrl = ''
param repositoryBranch = 'main'

// The shared Front Door origin is added after route deployment by
// scripts/shared-service.sh; no localhost origins in staging.
param corsAllowedOrigins = []

param tags = {
  application: 'GameVault Tracker Platform'
  environment: 'staging'
  managedBy: 'Bicep'
  repository: 'gamevault-tracker-azure'
}

param platformOwner = 'gamevault-staging'
param costCenter = 'gamevault-platform'
