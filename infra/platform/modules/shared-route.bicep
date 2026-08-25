// ============================================================================
// Shared Front Door Route
// ============================================================================
// Deployed once per environment against the existing shared Front Door
// profile. Creates exactly one endpoint, one origin group, one application
// origin (the shared Static Web App), and one catch-all route.
//
// Scaling invariant (see specs/003-shared-entry-scale/spec.md FR-002/FR-004):
// this module is independent of logical-instance count. Adding a logical
// instance is a Table Storage data operation and must never deploy this
// module, so the endpoint/route/origin-group/origin counts stay constant as
// the logical-instance population grows.
//
// Isolation invariant: this origin group must reference only the shared
// application origin (plus, from User Story 3, the shared maintenance
// fallback). It must never contain a legacy per-instance origin, because
// FR-009 forbids falling back to a legacy instance when the shared origin is
// unhealthy.
//
// The legacy modules/instance-route.bicep is retained unchanged for existing
// instances and is not used by the shared path.
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name prefix used for deterministic resource naming')
@minLength(1)
@maxLength(11)
param baseName string = 'gvt'

@description('Name of the existing shared Front Door profile to deploy into')
param frontDoorProfileName string

@description('Hostname of the shared application origin (the shared Static Web App default hostname)')
param originHostName string

@description('Whether the route is enabled. Kept as a parameter so the route can be provisioned but held disabled until verified.')
param routeEnabled bool = true

@description('Tags to apply to the shared Front Door child resources')
param tags object = {}

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

// Deterministic, environment-scoped names containing no instance identifier.
// Repeated deployments therefore always converge on the same resources and
// preserve the same Azure-assigned endpoint hostname.
var endpointName = toLower('${baseName}-${environment}-shared')
var originGroupName = 'og-shared'
var originName = 'origin-shared'
var routeName = 'route-shared'

var sharedTags = union(tags, {
  component: 'shared-entry'
  scalingModel: 'shared-entry'
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
  tags: sharedTags
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
      // Front Door probes from every edge location, so the probe interval is
      // multiplied by the PoP count. Four minutes preserves failover
      // behaviour while keeping probe volume and health-probe log ingestion
      // low. This matches the tuned value used by the legacy per-instance
      // origin group and is well inside the five-minute alerting target.
      probeIntervalInSeconds: 240
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
    // The host header stays the Static Web Apps hostname. Rewriting it to the
    // Azure-assigned Front Door hostname would break Static Web Apps host
    // matching and the certificate name check below, because that hostname
    // cannot be bound as a Static Web Apps custom domain.
    originHostHeader: originHostName
    priority: 1
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

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The shared Front Door endpoint name')
output endpointName string = endpoint.name

@description('The shared Front Door endpoint resource ID')
output endpointId string = endpoint.id

@description('The Azure-managed endpoint hostname (no owned domain required)')
output endpointHostName string = endpoint.properties.hostName

@description('The stable public HTTPS URL of the shared service')
output url string = 'https://${endpoint.properties.hostName}'

@description('The shared origin group name')
output originGroupName string = originGroup.name

@description('The shared application origin name')
output originName string = origin.name

@description('The shared route name')
output routeName string = route.name

@description('The route provisioning state as reported by Azure')
output routeProvisioningState string = route.properties.provisioningState
