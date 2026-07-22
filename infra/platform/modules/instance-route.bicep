// ============================================================================
// Per-Instance Front Door Route
// ============================================================================
// Deployed once per application instance against the existing shared Front
// Door Premium profile. Creates exactly one endpoint, one origin group, one
// application origin (the instance's Static Web App), an optional shared
// maintenance fallback origin, and one route.
//
// Isolation invariant (see data-model.md "Instance Route"): this origin
// group must reference only this instance's application origin plus,
// optionally, the shared maintenance origin - never another instance's
// origin.
// ============================================================================

@description('Instance identifier. Must match ^[a-z0-9]{1,8}$ (see contracts/instance-route-cli.md)')
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

@description('Name of the existing shared Front Door profile to deploy into')
param frontDoorProfileName string

@description('Hostname of the instance application origin (its Static Web App default hostname)')
param originHostName string

@description('Hostname of the shared maintenance origin. Required only when enableMaintenanceFallback is true')
param maintenanceOriginHostName string = ''

@description('Whether to add the shared maintenance origin as an optional, lower-priority fallback origin')
param enableMaintenanceFallback bool = false

@description('Whether the route is enabled. Kept as a parameter so a route can be provisioned but held disabled until verified')
param routeEnabled bool = true

@description('Resource ID of the centrally managed Front Door WAF policy')
param wafPolicyId string = ''

@description('Name of the shared Front Door security policy that associates the WAF with managed endpoints')
param wafSecurityPolicyName string = ''

@description('Resource IDs of all managed Front Door endpoints protected by the shared WAF policy')
param wafAssociatedEndpointIds array = []

@description('Tags to apply to the per-instance Front Door child resources')
param tags object = {}

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

var normalizedInstanceId = toLower(instanceId)
var endpointName = toLower('${baseName}-${environment}-${normalizedInstanceId}')
var originGroupName = 'og-${normalizedInstanceId}'
var originName = 'origin-${normalizedInstanceId}'
var maintenanceOriginName = 'origin-${normalizedInstanceId}-maintenance'
var routeName = 'route-${normalizedInstanceId}'
var instanceTags = union(tags, {
  instanceId: normalizedInstanceId
})

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' existing = {
  name: frontDoorProfileName
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  parent: frontDoorProfile
  name: endpointName
  location: 'global'
  tags: instanceTags
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  parent: frontDoorProfile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 60
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  parent: originGroup
  name: originName
  properties: {
    hostName: originHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: originHostName
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource maintenanceOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = if (enableMaintenanceFallback && !empty(maintenanceOriginHostName)) {
  parent: originGroup
  name: maintenanceOriginName
  properties: {
    hostName: maintenanceOriginHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: maintenanceOriginHostName
    priority: 2
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  parent: endpoint
  name: routeName
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: routeEnabled ? 'Enabled' : 'Disabled'
  }
  dependsOn: [
    origin
  ]
}

resource wafAssociation 'Microsoft.Cdn/profiles/securityPolicies@2024-09-01' = if (!empty(wafPolicyId) && !empty(wafSecurityPolicyName)) {
  parent: frontDoorProfile
  name: wafSecurityPolicyName
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            for endpointId in wafAssociatedEndpointIds: {
              id: endpointId
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The Front Door endpoint name')
output endpointName string = endpoint.name

@description('The Azure-managed endpoint hostname (no owned domain required)')
output endpointHostName string = endpoint.properties.hostName

@description('The full HTTPS URL for the instance')
output url string = 'https://${endpoint.properties.hostName}'

@description('The origin group name for this instance')
output originGroupName string = originGroup.name

@description('The application origin name for this instance')
output originName string = origin.name

@description('The route name for this instance')
output routeName string = route.name

@description('The route provisioning state as reported by Azure')
output routeProvisioningState string = route.properties.provisioningState
