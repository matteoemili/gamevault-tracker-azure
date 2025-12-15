// ============================================================================
// GameVault Tracker - Infrastructure as Code
// ============================================================================
// This Bicep template provisions all Azure resources required for the
// GameVault Tracker application:
// - Azure Storage Account with Table Service
// - Azure Static Web App
// - CORS configuration for browser-based access
// ============================================================================

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Base name for all resources')
@minLength(3)
@maxLength(11)
param baseName string = 'gamevault'

@description('SKU for the Static Web App')
@allowed(['Free', 'Standard'])
param staticWebAppSku string = 'Free'

@description('Storage Account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageSkuName string = 'Standard_LRS'

@description('Allowed origins for CORS (comma-separated). Leave empty to auto-configure after deployment.')
param corsAllowedOrigins array = []

@description('GitHub repository URL for the Static Web App')
param repositoryUrl string = ''

@description('GitHub repository branch')
param repositoryBranch string = 'main'

@description('Tags to apply to all resources')
param tags object = {
  application: 'GameVault Tracker'
  environment: environment
  managedBy: 'Bicep'
}

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

// Generate unique names for resources
var uniqueSuffix = uniqueString(resourceGroup().id, baseName)
var storageAccountName = toLower('st${baseName}${uniqueSuffix}')
var staticWebAppName = 'swa-${baseName}-${environment}-${uniqueSuffix}'

// Table names for the application
var gamesTableName = 'games'
var categoriesTableName = 'categories'

// Default CORS settings for development and production
var defaultCorsOrigins = [
  'http://localhost:5173'
  'http://localhost:5000'
  'http://localhost:3000'
  'http://127.0.0.1:5173'
]

// Merge default CORS with user-provided origins
var effectiveCorsOrigins = empty(corsAllowedOrigins) ? defaultCorsOrigins : union(defaultCorsOrigins, corsAllowedOrigins)

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

// Storage Account for Azure Table Storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
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

// Table Service for the Storage Account
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
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

// Games table
resource gamesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: gamesTableName
}

// Categories table
resource categoriesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: categoriesTableName
}

// Azure Static Web App
resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: staticWebAppName
  location: location
  tags: tags
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

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the Storage Account')
output storageAccountId string = storageAccount.id

@description('The Table Service endpoint')
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table

@description('The name of the games table')
output gamesTableName string = gamesTable.name

@description('The name of the categories table')
output categoriesTableName string = categoriesTable.name

@description('The name of the Static Web App')
output staticWebAppName string = staticWebApp.name

@description('The resource ID of the Static Web App')
output staticWebAppId string = staticWebApp.id

@description('The default hostname of the Static Web App')
output staticWebAppDefaultHostname string = staticWebApp.properties.defaultHostname

@description('The URL of the Static Web App')
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output deploymentLocation string = location
