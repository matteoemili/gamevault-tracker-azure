@description('Object ID of the platform operator group or user. Empty disables this assignment.')
param operatorPrincipalId string = ''

@description('Object ID used for shared platform deployments. Empty disables this assignment.')
param platformDeploymentPrincipalId string = ''

@description('Object ID used for per-instance route lifecycle deployments. Empty disables this assignment.')
param instanceRoutePrincipalId string = ''

resource platformContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(platformDeploymentPrincipalId)) {
  name: guid(resourceGroup().id, platformDeploymentPrincipalId, 'platform-contributor')
  properties: {
    principalId: platformDeploymentPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalType: 'ServicePrincipal'
  }
}

resource routeContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(instanceRoutePrincipalId)) {
  name: guid(resourceGroup().id, instanceRoutePrincipalId, 'route-contributor')
  properties: {
    principalId: instanceRoutePrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalType: 'ServicePrincipal'
  }
}

resource operatorReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(operatorPrincipalId)) {
  name: guid(resourceGroup().id, operatorPrincipalId, 'platform-reader')
  properties: {
    principalId: operatorPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalType: 'Group'
  }
}

output operatorAssignmentId string = empty(operatorPrincipalId) ? '' : operatorReader.id
output platformDeploymentAssignmentId string = empty(platformDeploymentPrincipalId) ? '' : platformContributor.id
output instanceRouteAssignmentId string = empty(instanceRoutePrincipalId) ? '' : routeContributor.id
