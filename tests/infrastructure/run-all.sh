#!/bin/bash
# T055: Ordered, local-first infrastructure validation runner.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

run() {
  echo "[run-all] $*" >&2
  "$@"
}

run bash "$ROOT_DIR/tests/infrastructure/contracts/offline-validation.sh"
run bash "$ROOT_DIR/tests/infrastructure/integration/secure-routing.sh" --help 2>/dev/null || true

if [ "${RUN_AZURE_INTEGRATION:-}" = "1" ]; then
  run bash "$ROOT_DIR/tests/infrastructure/integration/registration-idempotency.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/registration-rejection.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/origin-update-preservation.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/observability.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/health-alert.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/authorization-audit.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/orphan-detection.sh"
  run bash "$ROOT_DIR/tests/infrastructure/integration/deregistration-isolation.sh"
else
  echo "[run-all] Azure integration checks skipped; set RUN_AZURE_INTEGRATION=1 with documented variables to run them." >&2
fi

echo "[run-all] completed" >&2