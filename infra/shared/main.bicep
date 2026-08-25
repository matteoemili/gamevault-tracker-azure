// ============================================================================
// GameVault Tracker - Shared Application Infrastructure
// ============================================================================
// Provisions the ONE shared application deployment used by every logical
// instance in an environment:
// - One Storage Account with Table Service (games, categories)
// - One Static Web App
//
// Scaling invariant (see specs/003-shared-entry-scale/spec.md FR-002/FR-003):
// this template contains no instance identifier and no per-instance resource.
// Adding a logical instance is a Table Storage data operation and must never
// deploy this template.
//
// This template is deliberately separate from the legacy per-instance
// infra/main.bicep, which remains the deployed contract for existing
// instances and must not be modified by the shared-service path.
// ============================================================================

targetScope = 'resourceGroup'

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('The Azure region for all shared resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name for all shared resources')
@minLength(3)
@maxLength(11)
param baseName string = 'gamevault'

@description('SKU for the shared Static Web App. Free is sufficient because exactly one is deployed per environment regardless of logical-instance count.')
@allowed(['Free', 'Standard'])
param staticWebAppSku string = 'Free'

@description('Storage Account SKU for the shared application data store')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageSkuName string = 'Standard_LRS'

@description('Additional allowed origins for Table Storage CORS. The shared Front Door origin is added after route deployment by scripts/shared-service.sh.')
param corsAllowedOrigins array = []

@description('GitHub repository URL for the Static Web App')
param repositoryUrl string = ''

@description('GitHub repository branch')
param repositoryBranch string = 'main'

@description('Tags to apply to all shared resources')
param tags object = {
  application: 'GameVault Tracker Platform'
  environment: environment
  managedBy: 'Bicep'
}

@description('Platform owner identity (person or team), applied as a tag')
param platformOwner string = ''

@description('Cost-center identifier, applied as a tag')
param costCenter string = ''

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

// Deterministic, environment-scoped names. No instance identifier participates
// in naming, so repeated deployments always converge on the same resources.
var storageAccountName = toLower(replace('st${baseName}shared${environment}', '-', ''))
var staticWebAppName = 'swa-${baseName}-shared-${environment}'

var gamesTableName = 'games'
var categoriesTableName = 'categories'
var logicalInstancesTableName = 'logicalinstances'

var defaultCorsOrigins = [
  'http://localhost:5173'
  'http://localhost:5000'
  'http://localhost:3000'
  'http://127.0.0.1:5173'
]

var effectiveCorsOrigins = empty(corsAllowedOrigins) ? defaultCorsOrigins : union(defaultCorsOrigins, corsAllowedOrigins)

// The shared service is identified by scope rather than by instance id.
var effectiveTags = union(
  tags,
  {
    application: 'GameVault Tracker Platform'
    environment: environment
    managedBy: 'Bicep'
    component: 'shared-service'
    scalingModel: 'shared-entry'
  },
  empty(platformOwner) ? {} : { owner: platformOwner },
  empty(costCenter) ? {} : { costCenter: costCenter }
)

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: effectiveTags
  kind: 'StorageV2'
  sku: {
    name: storageSkuName
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: effectiveCorsOrigins
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'DELETE'
            'MERGE'
            'OPTIONS'
            'HEAD'
          ]
          allowedHeaders: [
            '*'
          ]
          exposedHeaders: [
            '*'
          ]
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

resource gamesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2025-01-01' = {
  parent: tableService
  name: gamesTableName
}

resource categoriesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2025-01-01' = {
  parent: tableService
  name: categoriesTableName
}

resource logicalInstancesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2025-01-01' = {
  parent: tableService
  name: logicalInstancesTableName
}

resource staticWebApp 'Microsoft.Web/staticSites@2024-11-01' = {
  name: staticWebAppName
  location: location
  tags: effectiveTags
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    repositoryUrl: empty(repositoryUrl) ? null : repositoryUrl
    branch: empty(repositoryUrl) ? null : repositoryBranch
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    buildProperties: {
      appLocation: '/'
      outputLocation: 'dist'
      appBuildCommand: 'npm run build'
    }
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The name of the shared Static Web App')
output staticWebAppName string = staticWebApp.name

@description('The resource ID of the shared Static Web App')
output staticWebAppId string = staticWebApp.id

@description('The default hostname of the shared Static Web App; used as the shared Front Door origin')
output staticWebAppDefaultHostname string = staticWebApp.properties.defaultHostname

@description('The direct URL of the shared Static Web App origin')
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The name of the shared Storage Account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the shared Storage Account')
output storageAccountId string = storageAccount.id

@description('The Table Service endpoint of the shared Storage Account')
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table

@description('The name of the shared games table')
output gamesTableName string = gamesTable.name

@description('The name of the shared categories table')
output categoriesTableName string = categoriesTable.name

@description('The name of the shared logical instances table')
output logicalInstancesTableName string = logicalInstancesTable.name

@description('Resource Group name holding the shared service')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output deploymentLocation string = location

@description('Stable inputs for deploying the shared Front Door route against this shared application origin. Treat as one versioned bundle rather than reconstructing it from individual outputs.')
output sharedRouteInputs object = {
  environment: environment
  baseName: baseName
  resourceGroupName: resourceGroup().name
  staticWebAppName: staticWebApp.name
  staticWebAppId: staticWebApp.id
  originHostName: staticWebApp.properties.defaultHostname
}
