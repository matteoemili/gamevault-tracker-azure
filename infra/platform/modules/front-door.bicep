// ============================================================================
// Shared Front Door Premium Profile
// ============================================================================
// Provisions the single Azure Front Door Premium profile that acts as the
// domain-free, global entry point for up to 25 application instances (the
// Premium SKU's per-profile endpoint limit - see research.md "Global Entry
// Service"). Per-instance endpoints, origin groups, origins, and routes are
// NOT created here; see modules/instance-route.bicep, which is deployed once
// per instance against this existing profile.
//
// WAF policy association is intentionally deferred to the US3 monitoring/
// security tasks (T050) and is not part of this module yet.
// ============================================================================

@description('Name of the Front Door profile (does not need to be globally unique; Azure appends a unique hash to endpoint hostnames)')
@minLength(1)
@maxLength(64)
param profileName string

@description('Tags to apply to the Front Door profile')
param tags object = {}

@description('Origin response timeout, in seconds, before Front Door considers a request to have failed')
@minValue(16)
param originResponseTimeoutSeconds int = 60

@description('WAF rollout mode. Keep Detection until the shared WAF logs have been reviewed.')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Detection'

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: profileName
  // Front Door profiles are global resources.
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: originResponseTimeoutSeconds
  }
}

resource wafPolicy 'Microsoft.Network/frontdoorWebApplicationFirewallPolicies@2025-03-01' = {
  // The Network provider rejects hyphenated WAF policy names with a misleading ARM ID error.
  name: replace(profileName, '-', '')
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '1.1'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
    }
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The name of the Front Door profile')
output name string = frontDoorProfile.name

@description('The resource ID of the Front Door profile')
output id string = frontDoorProfile.id

@description('The unique Front Door ID (used as the expected value of the X-Azure-FDID origin header for origin hardening)')
output frontDoorId string = frontDoorProfile.properties.frontDoorId

@description('ID of the centrally managed Front Door WAF policy')
output wafPolicyId string = wafPolicy.id

@description('Name of the centrally managed Front Door WAF policy')
output wafPolicyName string = wafPolicy.name

@description('Maximum number of endpoints supported per profile on the Premium_AzureFrontDoor SKU')
output endpointCapacity int = 25
