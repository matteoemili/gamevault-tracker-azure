#!/bin/bash
# ============================================================================
# GameVault Tracker - Infrastructure Cleanup Script
# ============================================================================
# This script removes all Azure resources by deleting the resource group.
# 
# ⚠️  WARNING: This will permanently delete all resources in the resource group!
#
# Prerequisites:
#   - Azure CLI installed and configured (az login)
#
# Usage:
#   ./scripts/cleanup-infra.sh [resource-group]
#
# Examples:
#   ./scripts/cleanup-infra.sh                     # Delete default RG
#   ./scripts/cleanup-infra.sh rg-gamevault-dev    # Delete specific RG
# ============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_RESOURCE_GROUP="rg-gamevault-tracker"

# Parse arguments
RESOURCE_GROUP="${1:-$DEFAULT_RESOURCE_GROUP}"

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
        log_error "Azure CLI is not installed."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

confirm_deletion() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  ⚠️   WARNING: DESTRUCTIVE OPERATION                   ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo "  This will permanently delete the resource group:"
    echo "  ${RED}$RESOURCE_GROUP${NC}"
    echo ""
    echo "  All resources in this group will be destroyed:"
    
    # List resources in the group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo ""
        az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name, Type:type}' -o table 2>/dev/null || true
        echo ""
    else
        log_warning "Resource group does not exist: $RESOURCE_GROUP"
        exit 0
    fi
    
    echo ""
    read -p "  Are you sure you want to delete these resources? (type 'yes' to confirm): " CONFIRM
    echo ""
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

delete_resource_group() {
    log_info "Deleting resource group '$RESOURCE_GROUP'..."
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated"
    log_info "Deletion is running in the background. It may take a few minutes to complete."
}

check_deletion_status() {
    log_info "Checking deletion status..."
    
    local MAX_WAIT=300  # 5 minutes
    local WAIT_TIME=0
    local CHECK_INTERVAL=10
    
    while [[ $WAIT_TIME -lt $MAX_WAIT ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_success "Resource group deleted successfully"
            return 0
        fi
        
        echo -n "."
        sleep $CHECK_INTERVAL
        WAIT_TIME=$((WAIT_TIME + CHECK_INTERVAL))
    done
    
    echo ""
    log_warning "Deletion is still in progress. Check Azure Portal for status."
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
    echo ""
    echo "╔════════════════════════════════════════════════╗"
    echo "║  GameVault Tracker - Infrastructure Cleanup    ║"
    echo "╚════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    confirm_deletion
    delete_resource_group
    
    echo ""
    read -p "Would you like to wait for deletion to complete? (y/n): " WAIT_CONFIRM
    
    if [[ "$WAIT_CONFIRM" == "y" || "$WAIT_CONFIRM" == "Y" ]]; then
        check_deletion_status
    fi
    
    echo ""
    log_success "Cleanup process complete!"
    echo ""
}

# Run main function
main
