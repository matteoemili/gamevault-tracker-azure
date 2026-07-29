// ============================================================================
// Shared Front Door Profile
// ============================================================================
// Provisions the single Azure Front Door profile that acts as the domain-free,
// global entry point for the application instances. Per-instance endpoints,
// origin groups, origins, and routes are NOT created here; see
// modules/instance-route.bicep, which is deployed once per instance against
// this existing profile.
//
// SKU choice (cost): Standard_AzureFrontDoor is the default because it costs
// roughly a tenth of Premium's fixed monthly base fee. The only Premium
// capabilities this platform could use are managed WAF rule sets and bot
// protection; Private Link origins are unusable anyway because Azure Static
// Web Apps do not support them (see research.md). Standard trades the managed
// rule sets for custom rules only, and lowers the per-profile endpoint limit
// from 25 to 10. Set sku to Premium_AzureFrontDoor to restore both.
// ============================================================================

@description('Name of the Front Door profile (does not need to be globally unique; Azure appends a unique hash to endpoint hostnames)')
@minLength(1)
@maxLength(64)
param profileName string

@description('Front Door SKU. Standard is the cost-optimised default (custom WAF rules only, 10 endpoints per profile). Premium adds managed WAF rule sets, bot protection, and 25 endpoints per profile for roughly ten times the fixed monthly cost.')
@allowed(['Standard_AzureFrontDoor', 'Premium_AzureFrontDoor'])
param sku string = 'Standard_AzureFrontDoor'

@description('Tags to apply to the Front Door profile')
param tags object = {}

@description('Origin response timeout, in seconds, before Front Door considers a request to have failed')
@minValue(16)
param originResponseTimeoutSeconds int = 60

@description('WAF rollout mode. Keep Detection until the shared WAF logs have been reviewed.')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Detection'

@description('Requests per minute, per client IP, allowed by the WAF rate-limit rule before the configured wafMode action applies')
@minValue(1)
param wafRateLimitThreshold int = 1000

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

var isPremium = sku == 'Premium_AzureFrontDoor'

// Azure Front Door endpoints-per-profile limit, which differs by SKU.
var skuEndpointCapacity = isPremium ? 25 : 10

// Managed rule sets are a Premium-only capability. On Standard the WAF policy
// carries the rate-limit custom rule below and nothing else.
var premiumManagedRules = {
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

// ----------------------------------------------------------------------------
// Resources
// ----------------------------------------------------------------------------

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: profileName
  // Front Door profiles are global resources.
  location: 'global'
  tags: tags
  sku: {
    name: sku
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
    // The WAF policy SKU must match the profile SKU it is associated with.
    name: sku
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitPerClientIp'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: wafRateLimitThreshold
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'Any'
              negateCondition: false
              matchValue: []
            }
          ]
        }
      ]
    }
    managedRules: isPremium ? premiumManagedRules : { managedRuleSets: [] }
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

@description('The Front Door SKU the profile was provisioned with')
output sku string = sku

@description('Maximum number of endpoints supported per profile on the configured SKU (10 on Standard, 25 on Premium)')
output endpointCapacity int = skuEndpointCapacity
