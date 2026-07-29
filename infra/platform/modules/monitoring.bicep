@description('Azure region for the Log Analytics workspace')
param location string

@description('Name of the shared Front Door profile')
param frontDoorProfileName string

@description('Tags applied to monitoring resources')
param tags object = {}

@description('Email addresses notified by shared platform alerts')
param alertRecipientEmails array = []

@description('Days of log retention. The platform requires at least 90 days (FR-011).')
@minValue(90)
param retentionInDays int = 90

@description('Hard daily ingestion cap for the shared workspace, in GB. Protects against runaway log spend; use -1 to disable the cap.')
param dailyQuotaGb int = 1

var workspaceName = take(toLower('gvt-law-${uniqueString(resourceGroup().id)}'), 63)
var actionGroupName = 'gvt-platform-alerts'

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' existing = {
  name: frontDoorProfileName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
  }
}

// Only log categories are forwarded. Front Door platform metrics are already
// retained and queryable for free in Azure Monitor metrics, so exporting
// 'AllMetrics' here would pay PerGB2018 ingestion for data the alerts below
// do not read from the workspace.
resource frontDoorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: frontDoorProfile
  name: 'front-door-to-workspace'
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: true
      }
    ]
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'gvtalerts'
    enabled: true
    emailReceivers: [
      for (email, index) in alertRecipientEmails: {
        name: 'recipient-${index}'
        emailAddress: email
        useCommonAlertSchema: true
      }
    ]
  }
}

resource originHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'gvt-origin-health-shared'
  location: 'global'
  tags: tags
  properties: {
    description: 'Front Door origin health is below the required threshold. Origin group dimensions identify the affected instance.'
    severity: 2
    enabled: true
    scopes: [
      frontDoorProfile.id
    ]
    // Five-minute evaluation over a fifteen-minute window. A one-minute
    // evaluation frequency multiplied by the per-origin-group dimension split
    // bills a premium for detection speed this platform does not need, and it
    // makes the alert flap on single probe failures.
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    // targetResourceType/targetResourceRegion are only mandatory when the scope
    // is a subscription, a resource group, or more than one resource. Supplying
    // them for a single-resource scope pushes Azure Monitor down the
    // resolve-metric-definitions-by-type-and-region path, which does not resolve
    // reliably for a global Front Door profile.
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'OriginHealthPercentage'
          metricNamespace: 'Microsoft.Cdn/profiles'
          metricName: 'OriginHealthPercentage'
          operator: 'LessThan'
          threshold: 50
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'OriginGroup'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

resource deploymentFailureAlert 'Microsoft.Insights/activityLogAlerts@2023-01-01-preview' = {
  name: 'gvt-platform-deployment-failure'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Resources/deployments/write'
        }
        {
          field: 'status'
          equals: 'Failed'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

resource certificateFailureAlert 'Microsoft.Insights/activityLogAlerts@2023-01-01-preview' = {
  name: 'gvt-front-door-certificate-failure'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [
      frontDoorProfile.id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Cdn/profiles/customDomains/write'
        }
        {
          field: 'status'
          equals: 'Failed'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output actionGroupId string = actionGroup.id
output originHealthAlertId string = originHealthAlert.id
output deploymentFailureAlertId string = deploymentFailureAlert.id
output certificateFailureAlertId string = certificateFailureAlert.id
