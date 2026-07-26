# Quickstart: Validate Automatic Front Door Registration

This guide validates the planned workflow changes without duplicating the route lifecycle contract. Start offline; run Azure scenarios only against an approved test environment.

## Prerequisites

- Bash 3.2 or newer
- Azure CLI with Bicep
- `jq` and `curl`
- Existing shared Front Door platform and test instances for live validation
- Azure login authorized for both the instance and platform test resource groups

## 1. Offline Validation

From the repository root:

```bash
bash tests/infrastructure/run-all.sh
```

Expected outcome:

- Every platform Bicep template compiles.
- Shell syntax and lifecycle schemas pass.
- The automatic-registration workflow contract confirms ordering, input mapping, profile-level serialization, verification gating, URL reporting, and artifact retention.
- CORS contract checks prove an existing published origin is not duplicated.

No Azure resources are mutated by this stage.

## 2. Configure a Test Publication

Set the existing lifecycle inputs for one approved test instance and its environment-specific platform. Use the variable names documented by the existing instance-route CLI contract and do not print credentials.

Confirm the Static Web App is already deployed and healthy before testing publication. The workflow contract is documented in [contracts/registration-workflow.md](contracts/registration-workflow.md).

## 3. Validate Idempotent Registration

Run the existing opt-in integration scenario:

```bash
RUN_AZURE_INTEGRATION=1 \
  bash tests/infrastructure/integration/registration-idempotency.sh
```

Expected outcome: twenty registrations converge on exactly one endpoint and preserve the same published hostname.

## 4. Validate Failure Preservation

```bash
RUN_AZURE_INTEGRATION=1 \
  bash tests/infrastructure/integration/registration-rejection.sh
```

Expected outcome: invalid identifiers, origins, and scopes fail without changing the target's prior route.

When a second approved test instance is available, also run the existing origin-update preservation scenario and confirm the sibling route snapshot is unchanged.

## 5. Validate Published Routing

After a workflow deployment reports its Front Door URL:

```bash
bash tests/infrastructure/integration/secure-routing.sh \
  --url "$INSTANCE_URL"
```

For two distinguishable instances:

```bash
bash tests/infrastructure/integration/routing-isolation.sh \
  --url-a "$INSTANCE_A_URL" --marker-a "$INSTANCE_A_MARKER" \
  --url-b "$INSTANCE_B_URL" --marker-b "$INSTANCE_B_MARKER" \
  --repeat 5
```

Expected outcome: both addresses use secure routing and each serves only its assigned instance.

## 6. Inspect Workflow Results

A successful run must show the verified Front Door URL in its summary and retain an artifact named `route-registration-<instance-id>`.

Use [data-model.md](data-model.md) to inspect state and [contracts/registration-workflow.md](contracts/registration-workflow.md) for required files. A failed preflight, registration, CORS, or verification stage must retain `publication-result.json`; later-stage failures also retain every lifecycle result produced before the failure.

## Exit Criteria

- Offline validation passes.
- A new healthy test instance is published without manual Front Door changes.
- Repeating the deployment preserves its published hostname.
- A forced failure marks the workflow incomplete and leaves actionable sanitized artifacts.
- A second registered instance remains unchanged throughout the target instance's redeployment.