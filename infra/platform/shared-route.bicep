// ============================================================================
// Shared Route Deployment Harness
// ============================================================================
// Resolves the EXISTING shared Static Web App (deployed by
// infra/shared/main.bicep, in the shared-service resource group) and deploys
// modules/shared-route.bicep for it against the existing shared Front Door
// profile.
//
// Deployed by scripts/shared-service.sh into the SHARED PLATFORM resource
// group. The shared application must be deployed first, because its
// Azure-assigned hostname is this route's origin.
//
//   az deployment group create \
//     --resource-group "$PLATFORM_RESOURCE_GROUP" \
//     --template-file infra/platform/shared-route.bicep \
//     --parameters environment=dev \
//                  frontDoorProfileName="$FRONT_DOOR_PROFILE" \
//                  sharedResourceGroupName="$SHARED_RESOURCE_GROUP" \
//                  staticWebAppName="$SHARED_SWA_NAME"
//
// This harness takes no instance identifier. There is exactly one shared
// route per environment regardless of how many logical instances exist.
// ============================================================================

targetScope = 'resourceGroup'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name prefix used for deterministic resource naming')
@minLength(1)
@maxLength(11)
param baseName string = 'gvt'

@description('Name of the existing shared Front Door profile, deployed in THIS resource group')
param frontDoorProfileName string

@description('Resource group name containing the existing shared Static Web App')
param sharedResourceGroupName string

@description('Subscription ID containing the existing shared Static Web App. Defaults to the current subscription')
param sharedSubscriptionId string = subscription().subscriptionId

@description('Name of the existing shared Static Web App')
param staticWebAppName string

@description('Override the resolved origin hostname instead of reading it from the shared Static Web App. Leave empty in normal use')
param originHostNameOverride string = ''

@description('Whether the shared route is enabled')
param routeEnabled bool = true

@description('Tags to apply to the shared Front Door child resources')
param tags object = {}

// ----------------------------------------------------------------------------
// Resolve the existing shared Static Web App
// ----------------------------------------------------------------------------

resource sharedStaticWebApp 'Microsoft.Web/staticSites@2024-11-01' existing = {
  name: staticWebAppName
  scope: resourceGroup(sharedSubscriptionId, sharedResourceGroupName)
}

var resolvedOriginHostName = empty(originHostNameOverride) ? sharedStaticWebApp.properties.defaultHostname : originHostNameOverride

// ----------------------------------------------------------------------------
// Deploy the shared route against the existing shared Front Door profile
// ----------------------------------------------------------------------------

module route 'modules/shared-route.bicep' = {
  name: 'shared-route-module-${environment}'
  params: {
    environment: environment
    baseName: baseName
    frontDoorProfileName: frontDoorProfileName
    originHostName: resolvedOriginHostName
    routeEnabled: routeEnabled
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The shared Front Door endpoint name')
output endpointName string = route.outputs.endpointName

@description('The shared Front Door endpoint resource ID')
output endpointId string = route.outputs.endpointId

@description('The Azure-managed shared endpoint hostname')
output endpointHostName string = route.outputs.endpointHostName

@description('The stable public HTTPS URL of the shared service')
output url string = route.outputs.url

@description('The shared origin group name')
output originGroupName string = route.outputs.originGroupName

@description('The shared application origin name')
output originName string = route.outputs.originName

@description('The shared route name')
output routeName string = route.outputs.routeName

@description('The route provisioning state as reported by Azure')
output routeProvisioningState string = route.outputs.routeProvisioningState

@description('The resolved shared application origin hostname that was used')
output resolvedOriginHostName string = resolvedOriginHostName
