#!/bin/bash
# ============================================================================
# logical-instance.sh - Logical instance lifecycle CLI (stub)
# ============================================================================
# Usage:
#   ./scripts/logical-instance.sh <create|list|show|retire> [options]
#
# A logical instance is a Table Storage record, not infrastructure. Creating
# one MUST NOT deploy any Azure resource: the shared application and the
# shared Front Door entry point are provisioned once per environment by
# scripts/shared-service.sh and are unchanged by instance lifecycle actions.
#
# This is a Phase 1 scaffold. The behaviour is implemented by User Story 2
# (tasks T024-T034) per
# specs/003-shared-entry-scale/contracts/logical-instance-cli.md.
#
# Bash 3.2 compatible.
# ============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/azure-common.sh
. "$SCRIPT_DIR/lib/azure-common.sh"

DATA_KEY="logicalInstance"

usage() {
  cat >&2 <<'USAGE'
Usage: logical-instance.sh <create|list|show|retire> [options]
  --environment <dev|staging|prod>
  --instance-id <3-32 chars, ^[a-z0-9][a-z0-9-]*[a-z0-9]$>
  --subscription-id <uuid>
  --shared-resource-group <name>
  --display-name <text>
  --state <Reserved|Retired>

Not yet implemented (User Story 2). Creating a logical instance never
provisions infrastructure.
USAGE
}

ACTION="${1:-}"
if [ -z "$ACTION" ]; then
  usage
  exit 2
fi

usage
fail_fast "$DATA_KEY" "$ACTION" "$(operation_id instance unknown)" "NOT_IMPLEMENTED" \
  "logical-instance.sh is not implemented yet; see specs/003-shared-entry-scale/tasks.md User Story 2"
