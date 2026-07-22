targetScope = 'subscription'

@description('Shared platform resource group name')
param platformResourceGroupName string

@description('Monthly budget amount. Zero disables budget deployment.')
@minValue(0)
param monthlyBudgetAmount int = 0

@description('Email addresses notified when budget thresholds are reached')
param alertRecipientEmails array = []

@description('First day of the billing period used when creating the budget')
param budgetStartDate string = utcNow('yyyy-MM-01T00:00:00Z')

@description('Tags used for application and environment cost attribution')
param tags object = {}

resource platformBudget 'Microsoft.Consumption/budgets@2024-08-01' = if (monthlyBudgetAmount > 0) {
  name: 'gvt-platform-${platformResourceGroupName}'
  properties: {
    category: 'Cost'
    amount: monthlyBudgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: dateTimeAdd(budgetStartDate, 'P1M')
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          platformResourceGroupName
        ]
      }
      tags: {
        name: 'application'
        operator: 'In'
        values: [
          'GameVault Tracker Platform'
        ]
      }
    }
    notifications: {
      actual80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: alertRecipientEmails
      }
      forecast100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: alertRecipientEmails
      }
    }
  }
}

output budgetId string = monthlyBudgetAmount > 0 ? platformBudget.id : ''
output costAttributionTags object = tags
