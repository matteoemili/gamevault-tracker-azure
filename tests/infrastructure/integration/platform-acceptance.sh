#!/bin/bash
# T057: Runs the release acceptance suite against a disposable 25-instance
# fixture. It is intentionally opt-in because it creates and removes routes.

set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"

[ "${RUN_AZURE_INTEGRATION:-}" = "1" ] || { echo "[platform-acceptance] skipped: set RUN_AZURE_INTEGRATION=1" >&2; exit 0; }
: "${CAPACITY_FIXTURE_FILE:?required}"
: "${ROUTE_INSTANCE_ID:?required}"

bash "$ROOT_DIR/tests/infrastructure/fixtures/generate-capacity-parameters.sh" --count 25 --output "$CAPACITY_FIXTURE_FILE"
bash "$ROOT_DIR/tests/infrastructure/integration/registration-idempotency.sh"
bash "$ROOT_DIR/tests/infrastructure/integration/registration-rejection.sh"
bash "$ROOT_DIR/tests/infrastructure/integration/origin-update-preservation.sh"

if [ -n "${ROUTING_URL_A:-}" ] && [ -n "${ROUTING_URL_B:-}" ] && [ -n "${ROUTING_MARKER_A:-}" ] && [ -n "${ROUTING_MARKER_B:-}" ]; then
  bash "$ROOT_DIR/tests/infrastructure/integration/routing-isolation.sh" \
    --url-a "$ROUTING_URL_A" --marker-a "$ROUTING_MARKER_A" \
    --url-b "$ROUTING_URL_B" --marker-b "$ROUTING_MARKER_B"
fi

if [ -n "${UNHEALTHY_ROUTE_URL:-}" ] && [ -n "${FOREIGN_INSTANCE_MARKER:-}" ]; then
  bash "$ROOT_DIR/tests/infrastructure/integration/controlled-unavailability.sh" \
    --url "$UNHEALTHY_ROUTE_URL" --foreign-marker "$FOREIGN_INSTANCE_MARKER"
fi

echo "[platform-acceptance] passed: fixture, idempotency, rejection, routing, and controlled-failure checks completed" >&2