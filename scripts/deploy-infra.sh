#!/bin/bash
# ============================================================================
# GameVault Tracker - Infrastructure Deployment Script
# ============================================================================
# This script deploys the Azure infrastructure using Bicep templates.
# 
# Prerequisites:
#   - Azure CLI installed and configured (az login)
#   - Bicep CLI installed (comes with Azure CLI 2.20.0+)
#
# Usage:
#   ./scripts/deploy-infra.sh [environment] [resource-group] [location]
#
# Examples:
#   ./scripts/deploy-infra.sh                           # Deploy prod to default RG
#   ./scripts/deploy-infra.sh dev rg-gamevault-dev      # Deploy dev environment
#   ./scripts/deploy-infra.sh prod rg-gamevault westus2 # Deploy to specific location
# ============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="$PROJECT_ROOT/infra"

# Default values
DEFAULT_ENVIRONMENT="prod"
DEFAULT_RESOURCE_GROUP="rg-gamevault-tracker"
DEFAULT_LOCATION="westeurope"

# Parse arguments
ENVIRONMENT="${1:-$DEFAULT_ENVIRONMENT}"
RESOURCE_GROUP="${2:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${3:-$DEFAULT_LOCATION}"

# Determine parameters file based on environment
if [[ "$ENVIRONMENT" == "prod" ]]; then
    PARAMS_FILE="$INFRA_DIR/main.bicepparam"
else
    PARAMS_FILE="$INFRA_DIR/main.${ENVIRONMENT}.bicepparam"
fi

# ----------------------------------------------------------------------------
# Functions
# ----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Install: brew install azure-cli (macOS) or visit https://aka.ms/installazurecli"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Bicep
    if ! az bicep version &> /dev/null; then
        log_warning "Bicep CLI not found. Installing..."
        az bicep install
    fi
    
    log_success "All prerequisites met"
}

show_config() {
    echo ""
    echo "============================================"
    echo "  Deployment Configuration"
    echo "============================================"
    echo "  Environment:     $ENVIRONMENT"
    echo "  Resource Group:  $RESOURCE_GROUP"
    echo "  Location:        $LOCATION"
    echo "  Parameters:      $PARAMS_FILE"
    echo "  Template:        $INFRA_DIR/main.bicep"
    echo "============================================"
    echo ""
}

validate_template() {
    log_info "Validating Bicep template..."
    
    # Build Bicep to check for syntax errors
    az bicep build --file "$INFRA_DIR/main.bicep" --outfile /tmp/main.json
    
    if [[ $? -eq 0 ]]; then
        log_success "Template validation passed"
        rm -f /tmp/main.json
    else
        log_error "Template validation failed"
        exit 1
    fi
}

create_resource_group() {
    log_info "Checking resource group '$RESOURCE_GROUP'..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group already exists"
    else
        log_info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags application="GameVault Tracker" environment="$ENVIRONMENT" managedBy="Bicep"
        log_success "Resource group created"
    fi
}

deploy_infrastructure() {
    log_info "Deploying infrastructure..."
    
    local DEPLOYMENT_NAME="gamevault-deployment-$(date +%Y%m%d-%H%M%S)"
    
    # Check if parameters file exists
    if [[ ! -f "$PARAMS_FILE" ]]; then
        log_warning "Parameters file not found: $PARAMS_FILE"
        log_info "Using default parameters..."
        
        az deployment group create \
            --name "$DEPLOYMENT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$INFRA_DIR/main.bicep" \
            --parameters environment="$ENVIRONMENT" \
            --verbose
    else
        az deployment group create \
            --name "$DEPLOYMENT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$INFRA_DIR/main.bicep" \
            --parameters "$PARAMS_FILE" \
            --verbose
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "Infrastructure deployed successfully"
    else
        log_error "Deployment failed"
        exit 1
    fi
}

show_outputs() {
    log_info "Retrieving deployment outputs..."
    
    echo ""
    echo "============================================"
    echo "  Deployment Outputs"
    echo "============================================"
    
    # Get the latest deployment
    local OUTPUTS=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$(az deployment group list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)" \
        --query 'properties.outputs' \
        -o json 2>/dev/null)
    
    if [[ -n "$OUTPUTS" && "$OUTPUTS" != "null" ]]; then
        echo "$OUTPUTS" | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    else
        log_warning "Could not retrieve outputs"
    fi
    
    echo "============================================"
    echo ""
}

generate_sas_token() {
    log_info "Generating SAS token for storage account..."
    
    # Get storage account name from deployment
    local STORAGE_ACCOUNT=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$(az deployment group list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)" \
        --query 'properties.outputs.storageAccountName.value' \
        -o tsv 2>/dev/null)
    
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        log_warning "Could not retrieve storage account name"
        return
    fi
    
    # Calculate expiry date (1 year from now)
    local EXPIRY_DATE
    if [[ "$(uname)" == "Darwin" ]]; then
        EXPIRY_DATE=$(date -u -v+1y '+%Y-%m-%dT%H:%MZ')
    else
        EXPIRY_DATE=$(date -u -d "1 year" '+%Y-%m-%dT%H:%MZ')
    fi
    
    # Generate SAS token
    local SAS_TOKEN=$(az storage account generate-sas \
        --account-name "$STORAGE_ACCOUNT" \
        --services t \
        --resource-types sco \
        --permissions rwdlacu \
        --expiry "$EXPIRY_DATE" \
        --https-only \
        --output tsv 2>/dev/null)
    
    if [[ -n "$SAS_TOKEN" ]]; then
        echo ""
        echo "============================================"
        echo "  SAS Token Generated"
        echo "============================================"
        echo ""
        echo "  Storage Account: $STORAGE_ACCOUNT"
        echo "  Expiry: $EXPIRY_DATE"
        echo ""
        echo "  SAS Token (add to your .env file):"
        echo "  VITE_AZURE_STORAGE_SAS_TOKEN=$SAS_TOKEN"
        echo ""
        echo "============================================"
        echo ""
        log_warning "Store this SAS token securely. It provides access to your storage account."
    else
        log_warning "Could not generate SAS token"
    fi
}

print_next_steps() {
    echo ""
    echo "============================================"
    echo "  Next Steps"
    echo "============================================"
    echo ""
    echo "  1. Copy the SAS token to your .env file:"
    echo "     VITE_AZURE_STORAGE_ACCOUNT_NAME=<storage-account-name>"
    echo "     VITE_AZURE_STORAGE_SAS_TOKEN=<sas-token>"
    echo ""
    echo "  2. Add SAS token to GitHub Secrets for CI/CD:"
    echo "     - VITE_AZURE_STORAGE_ACCOUNT_NAME"
    echo "     - VITE_AZURE_STORAGE_SAS_TOKEN"
    echo ""
    echo "  3. Update CORS settings with your Static Web App URL:"
    echo "     - Go to Azure Portal > Storage Account > CORS"
    echo "     - Add your Static Web App URL to allowed origins"
    echo ""
    echo "============================================"
    echo ""
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  GameVault Tracker - Infrastructure Deploy ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    show_config
    check_prerequisites
    validate_template
    create_resource_group
    deploy_infrastructure
    show_outputs
    generate_sas_token
    print_next_steps
    
    log_success "Deployment complete!"
}

# Run main function
main
