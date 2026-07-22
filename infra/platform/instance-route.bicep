// ============================================================================
// Direct Per-Instance Route Deployment Harness
// ============================================================================
// Resolves an EXISTING Static Web App (deployed by the top-level
// infra/main.bicep, possibly in a different resource group/subscription
// than the shared platform) and deploys modules/instance-route.bicep for it
// against the existing shared Front Door profile.
//
// This harness is deployed directly (not yet wrapped by scripts/instance-route.sh
// full automation - see T033-T035, out of scope for the initial platform
// bring-up). See tests/infrastructure/integration/README.md for exact
// commands used to validate User Story 1 with two instances.
//
// Deploy into the SHARED PLATFORM resource group, e.g.:
//   az deployment group create \
//     --resource-group "$PLATFORM_RESOURCE_GROUP" \
//     --template-file infra/platform/instance-route.bicep \
//     --parameters instanceId=a1 environment=dev \
//                  frontDoorProfileName="$FRONT_DOOR_PROFILE" \
//                  instanceResourceGroupName="$INSTANCE_RESOURCE_GROUP" \
//                  staticWebAppName="$INSTANCE_SWA_NAME"
// ============================================================================

targetScope = 'resourceGroup'

@description('Instance identifier. Must match ^[a-z0-9]{1,8}$')
@minLength(1)
@maxLength(8)
param instanceId string

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name prefix used for deterministic resource naming')
@minLength(1)
@maxLength(11)
param baseName string = 'gvt'

@description('Name of the existing shared Front Door profile, deployed in THIS resource group')
param frontDoorProfileName string

@description('Resource group name containing the existing instance Static Web App')
param instanceResourceGroupName string

@description('Subscription ID containing the existing instance Static Web App. Defaults to the current subscription')
param instanceSubscriptionId string = subscription().subscriptionId

@description('Name of the existing instance Static Web App')
param staticWebAppName string

@description('Override the resolved origin hostname instead of reading it from the Static Web App. Leave empty in normal use')
param originHostNameOverride string = ''

@description('Hostname of the shared maintenance origin (from the platform deployment outputs). Required only when enableMaintenanceFallback is true')
param maintenanceOriginHostName string = ''

@description('Whether to add the shared maintenance origin as an optional, lower-priority fallback origin')
param enableMaintenanceFallback bool = false

@description('Whether the route is enabled')
param routeEnabled bool = true

@description('Tags to apply to the per-instance Front Door child resources')
param tags object = {}

// ----------------------------------------------------------------------------
// Resolve the existing instance Static Web App
// ----------------------------------------------------------------------------

resource instanceStaticWebApp 'Microsoft.Web/staticSites@2024-11-01' existing = {
  name: staticWebAppName
  scope: resourceGroup(instanceSubscriptionId, instanceResourceGroupName)
}

var resolvedOriginHostName = empty(originHostNameOverride) ? instanceStaticWebApp.properties.defaultHostname : originHostNameOverride

// ----------------------------------------------------------------------------
// Deploy the instance route against the existing shared Front Door profile
// ----------------------------------------------------------------------------

module route 'modules/instance-route.bicep' = {
  name: 'instance-route-module-${instanceId}'
  params: {
    instanceId: instanceId
    environment: environment
    baseName: baseName
    frontDoorProfileName: frontDoorProfileName
    originHostName: resolvedOriginHostName
    maintenanceOriginHostName: maintenanceOriginHostName
    enableMaintenanceFallback: enableMaintenanceFallback
    routeEnabled: routeEnabled
    tags: tags
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The Front Door endpoint name for this instance')
output endpointName string = route.outputs.endpointName

@description('The Azure-managed endpoint hostname for this instance')
output endpointHostName string = route.outputs.endpointHostName

@description('The full HTTPS URL for this instance (no owned domain required)')
output url string = route.outputs.url

@description('The origin group name for this instance')
output originGroupName string = route.outputs.originGroupName

@description('The application origin name for this instance')
output originName string = route.outputs.originName

@description('The route name for this instance')
output routeName string = route.outputs.routeName

@description('The route provisioning state as reported by Azure')
output routeProvisioningState string = route.outputs.routeProvisioningState

@description('The resolved application origin hostname that was used')
output resolvedOriginHostName string = resolvedOriginHostName
