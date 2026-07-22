// ============================================================================
// Shared Platform - Development Parameters
// ============================================================================
// Safe defaults for local, subscription-selected development deployments.
// Use with: ./scripts/platform.sh validate --environment dev ...
// ============================================================================
using 'main.bicep'

param environment = 'dev'
param baseName = 'gvt'
param location = 'uksouth'
param wafMode = 'Detection'
param platformOwner = 'gamevault-dev'
param costCenter = ''
param monthlyBudgetAmount = 0
param alertRecipientEmails = []
