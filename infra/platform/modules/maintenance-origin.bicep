// ============================================================================
// Shared Maintenance Origin
// ============================================================================
// Provisions a shared, public, HTTPS-only Storage Account that serves a
// generic "instance unavailable" placeholder page. This resource holds no
// tenant data and is referenced (by hostname only, never by resource ID) as
// an optional, lower-priority fallback origin inside each instance's Front
// Door origin group (see modules/instance-route.bicep).
//
// Blob content upload (the maintenance index.html) is intentionally NOT done
// here - Bicep/ARM cannot upload blob content declaratively. Content upload
// is a post-deploy step performed by scripts/platform.sh (see T032, out of
// scope for the initial platform bring-up).
// ============================================================================

@description('Globally-unique Storage Account name for the shared maintenance origin')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for the Storage Account')
param location string

@description('Tags to apply to the Storage Account')
param tags object = {}

@description('Blob container name that holds the maintenance placeholder page')
param containerName string = 'maintenance'

@description('Storage Account SKU')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS'])
param storageSkuName string = 'Standard_LRS'

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
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
    // Public, anonymous, read-only blob access is required so Front Door can
    // reach the maintenance page without credentials. No tenant data is ever
    // stored in this account - see module header.
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource maintenanceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    // 'Blob' grants anonymous read on blobs (not container listing).
    publicAccess: 'Blob'
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The name of the shared maintenance Storage Account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the shared maintenance Storage Account')
output storageAccountId string = storageAccount.id

@description('The blob container name holding the maintenance placeholder page')
output containerName string = maintenanceContainer.name

@description('The bare hostname (no scheme, no path) used as the Front Door maintenance origin hostname')
output hostName string = replace(replace(storageAccount.properties.primaryEndpoints.blob, 'https://', ''), '/', '')

@description('The full public URL of the maintenance placeholder page')
output maintenancePageUrl string = '${storageAccount.properties.primaryEndpoints.blob}${maintenanceContainer.name}/index.html'
