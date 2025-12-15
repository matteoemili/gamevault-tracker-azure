#!/bin/bash
# ============================================================================
# GameVault Tracker - Infrastructure Validation Script
# ============================================================================
# This script validates and previews infrastructure changes using what-if.
# 
# Prerequisites:
#   - Azure CLI installed and configured (az login)
#   - Bicep CLI installed (comes with Azure CLI 2.20.0+)
#
# Usage:
#   ./scripts/validate-infra.sh [environment] [resource-group]
#
# Examples:
#   ./scripts/validate-infra.sh                      # Validate prod
#   ./scripts/validate-infra.sh dev rg-gamevault-dev # Validate dev environment
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
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

validate_syntax() {
    log_info "Validating Bicep syntax..."
    
    az bicep build --file "$INFRA_DIR/main.bicep" --outfile /tmp/main.json 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "Bicep syntax is valid"
        rm -f /tmp/main.json
    else
        log_error "Bicep syntax validation failed"
        exit 1
    fi
}

lint_template() {
    log_info "Running Bicep linter..."
    
    # Build with warnings as errors to catch linting issues
    local LINT_OUTPUT=$(az bicep build --file "$INFRA_DIR/main.bicep" --outfile /dev/null 2>&1)
    
    if [[ -z "$LINT_OUTPUT" ]]; then
        log_success "No linting warnings"
    else
        log_warning "Linting warnings found:"
        echo "$LINT_OUTPUT"
    fi
}

ensure_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group does not exist. Creating for validation..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags application="GameVault Tracker" environment="$ENVIRONMENT" managedBy="Bicep"
        log_success "Resource group created"
    else
        log_info "Resource group exists"
    fi
}

run_what_if() {
    log_info "Running what-if deployment preview..."
    echo ""
    
    if [[ -f "$PARAMS_FILE" ]]; then
        az deployment group what-if \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$INFRA_DIR/main.bicep" \
            --parameters "$PARAMS_FILE"
    else
        log_warning "Parameters file not found: $PARAMS_FILE"
        log_info "Using default parameters..."
        az deployment group what-if \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$INFRA_DIR/main.bicep" \
            --parameters environment="$ENVIRONMENT"
    fi
}

validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ -f "$PARAMS_FILE" ]]; then
        az deployment group validate \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$INFRA_DIR/main.bicep" \
            --parameters "$PARAMS_FILE"
    else
        az deployment group validate \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$INFRA_DIR/main.bicep" \
            --parameters environment="$ENVIRONMENT"
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "Deployment validation passed"
    else
        log_error "Deployment validation failed"
        exit 1
    fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
    echo ""
    echo "╔════════════════════════════════════════════════╗"
    echo "║  GameVault Tracker - Infrastructure Validation ║"
    echo "╚════════════════════════════════════════════════╝"
    echo ""
    echo "  Environment:     $ENVIRONMENT"
    echo "  Resource Group:  $RESOURCE_GROUP"
    echo "  Parameters:      $PARAMS_FILE"
    echo ""
    
    check_prerequisites
    validate_syntax
    lint_template
    ensure_resource_group
    validate_deployment
    
    echo ""
    echo "============================================"
    echo "  What-If Deployment Preview"
    echo "============================================"
    echo ""
    
    run_what_if
    
    echo ""
    log_success "Validation complete!"
    echo ""
    echo "To deploy, run: ./scripts/deploy-infra.sh $ENVIRONMENT $RESOURCE_GROUP"
    echo ""
}

# Run main function
main
