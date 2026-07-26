// ============================================================================
// Shared Platform - Production Parameters
// ============================================================================
// Fill in platformOwner, costCenter, monthlyBudgetAmount, and
// alertRecipientEmails with real values before deploying to production.
// WAF starts in Detection mode; promote to Prevention only after reviewing
// Front Door WAF logs (see research.md "Monitoring and Security").
// ============================================================================
using 'main.bicep'

param environment = 'prod'
param baseName = 'gvt'
param location = 'uksouth'
param wafMode = 'Detection'
param platformOwner = 'CHANGE_ME_OWNER'
param costCenter = 'CHANGE_ME_COST_CENTER'
param monthlyBudgetAmount = 0
param alertRecipientEmails = []
