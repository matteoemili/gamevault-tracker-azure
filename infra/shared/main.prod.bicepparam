// ============================================================================
// Shared Service - Production Parameters
// ============================================================================
// Configures the ONE shared GameVault application for the prod environment.
// Use with: ./scripts/shared-service.sh validate --environment prod ...
//
// There is deliberately no instanceId parameter: logical instances are Table
// Storage records, not deployments.
// ============================================================================

using './main.bicep'

param environment = 'prod'
param baseName = 'gamevault'

// Free remains sufficient because exactly one shared application is deployed
// per environment regardless of logical-instance count. Switch to Standard
// when an SLA, custom domain, or private endpoint is required.
param staticWebAppSku = 'Free'
param storageSkuName = 'Standard_LRS'

param repositoryUrl = ''
param repositoryBranch = 'main'

// The shared Front Door origin is added after route deployment by
// scripts/shared-service.sh; no localhost origins in production.
param corsAllowedOrigins = []

param tags = {
  application: 'GameVault Tracker'
  environment: 'prod'
  managedBy: 'Bicep'
  repository: 'gamevault-tracker-azure'
}
