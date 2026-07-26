// ============================================================================
// GameVault Tracker - Shared Multi-Instance Entry Platform
// ============================================================================
// Provisions the shared, domain-free entry point that fronts up to 25
// isolated application instances (see specs/001-multi-instance-platform/).
//
// This template intentionally does NOT provision per-instance routing
// (endpoint/origin-group/origin/route). Per-instance routes are deployed
// separately, one at a time, via infra/platform/instance-route.bicep so
// that redeploying the shared platform never touches existing instance
// routes (see plan.md "Deployment Safety").
//
// Monitoring (Log Analytics, diagnostic settings, WAF policy, budget/alert
// wiring) is added by later User Story 3 tasks (T046-T051) and is not part
// of this template yet. The monthlyBudgetAmount and alertRecipientEmails
// parameters below are accepted now (so prod parameter files can declare
// them) but are only surfaced as pass-through outputs until T047/T049 wire
// them to real resources.
// ============================================================================

targetScope = 'resourceGroup'

// ----------------------------------------------------------------------------
// Parameters
// ----------------------------------------------------------------------------

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name prefix used for deterministic resource naming across the shared platform')
@minLength(1)
@maxLength(11)
param baseName string = 'gvt'

@description('Azure region for the shared platform resources')
param location string = resourceGroup().location

@description('WAF policy mode. Detection first; promote to Prevention only after log review (see research.md)')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Detection'

@description('Platform owner identity (person or team), applied as a tag')
param platformOwner string = ''

@description('Cost-center identifier, applied as a tag')
param costCenter string = ''

@description('Reserved for T049 (cost-management budget). Monthly budget amount in the billing currency; 0 disables budget creation')
@minValue(0)
param monthlyBudgetAmount int = 0

@description('Reserved for T047 (monitor alerting). Email addresses notified on platform alerts')
param alertRecipientEmails array = []

@description('Object ID of the platform operator group or user. Empty leaves no operator assignment.')
param operatorPrincipalId string = ''

@description('Object ID used by shared-platform deployment automation. Empty leaves no assignment.')
param platformDeploymentPrincipalId string = ''

@description('Object ID used by instance-route deployment automation. Empty leaves no assignment.')
param instanceRoutePrincipalId string = ''

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

var baseTags = union(
  {
    application: 'GameVault Tracker Platform'
    environment: environment
    managedBy: 'Bicep'
    component: 'shared-entry-platform'
  },
  empty(platformOwner) ? {} : { owner: platformOwner },
  empty(costCenter) ? {} : { costCenter: costCenter }
)

var frontDoorProfileName = toLower('${baseName}-afd-${environment}')
var maintenanceStorageAccountName = toLower(replace('st${baseName}maint${environment}${uniqueString(resourceGroup().id)}', '-', ''))

// ----------------------------------------------------------------------------
// Modules
// ----------------------------------------------------------------------------

module frontDoor 'modules/front-door.bicep' = {
  name: 'platform-front-door'
  params: {
    profileName: frontDoorProfileName
    tags: baseTags
    wafMode: wafMode
  }
}

module maintenanceOrigin 'modules/maintenance-origin.bicep' = {
  name: 'platform-maintenance-origin'
  params: {
    // maintenanceStorageAccountName is always >= 24 chars by construction
    // ('st' + baseName[>=1] + 'maint' + environment[>=3] + uniqueString[13]),
    // so this is always a safe, non-empty, <=24-char name. Bicep's static
    // analyzer cannot prove the length of replace()/uniqueString() results,
    // so it emits a benign BCP334 warning here (build still succeeds).
    storageAccountName: take(maintenanceStorageAccountName, 24)
    location: location
    tags: baseTags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'platform-monitoring'
  params: {
    location: location
    frontDoorProfileName: frontDoorProfileName
    tags: baseTags
    alertRecipientEmails: alertRecipientEmails
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'platform-rbac'
  params: {
    operatorPrincipalId: operatorPrincipalId
    platformDeploymentPrincipalId: platformDeploymentPrincipalId
    instanceRoutePrincipalId: instanceRoutePrincipalId
  }
}

module costManagement 'modules/cost-management.bicep' = {
  name: 'platform-cost-management'
  scope: subscription()
  params: {
    platformResourceGroupName: resourceGroup().name
    monthlyBudgetAmount: monthlyBudgetAmount
    alertRecipientEmails: alertRecipientEmails
    tags: baseTags
  }
}

// ----------------------------------------------------------------------------
// Outputs
// ----------------------------------------------------------------------------

@description('The resource group name the shared platform was deployed into')
output platformResourceGroupName string = resourceGroup().name

@description('The name of the shared Front Door profile')
output frontDoorProfileName string = frontDoor.outputs.name

@description('The resource ID of the shared Front Door profile')
output frontDoorProfileId string = frontDoor.outputs.id

@description('The unique Front Door ID (expected value of the X-Azure-FDID origin header for origin hardening)')
output frontDoorId string = frontDoor.outputs.frontDoorId

@description('The centrally managed Front Door WAF policy ID')
output wafPolicyId string = frontDoor.outputs.wafPolicyId

@description('Maximum number of instance endpoints supported by the Premium_AzureFrontDoor SKU')
output endpointCapacity int = frontDoor.outputs.endpointCapacity

@description('The hostname of the shared maintenance origin, for use by instance-route deployments')
output maintenanceOriginHostName string = maintenanceOrigin.outputs.hostName

@description('The public URL of the shared maintenance placeholder page')
output maintenancePageUrl string = maintenanceOrigin.outputs.maintenancePageUrl

@description('The configured WAF policy mode (Detection or Prevention)')
output wafMode string = wafMode

@description('The shared Log Analytics workspace ID retaining platform diagnostics')
output workspaceId string = monitoring.outputs.workspaceId

@description('The shared Log Analytics workspace name')
output workspaceName string = monitoring.outputs.workspaceName

@description('The action group receiving shared platform alerts')
output alertActionGroupId string = monitoring.outputs.actionGroupId

@description('The budget resource ID when monthlyBudgetAmount is nonzero')
output budgetId string = costManagement.outputs.budgetId

@description('Reserved for T049: the configured monthly budget amount (0 = disabled)')
output reservedMonthlyBudgetAmount int = monthlyBudgetAmount

@description('Reserved for T047: the configured alert recipient email addresses')
output reservedAlertRecipientEmails array = alertRecipientEmails
