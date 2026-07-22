# Contract: Platform Lifecycle CLI

## Command Shape

```text
./scripts/platform.sh <validate|what-if|deploy|outputs|status> [options]
```

Required options for Azure-scoped commands:

```text
--environment <dev|staging|prod>
--subscription-id <uuid>
--resource-group <name>
--location <azure-region>
```

`validate` performs local Bicep compilation followed by Azure deployment validation when authenticated. `what-if` never mutates resources. `deploy` MUST internally rerun validation and what-if and requires `--confirm` when invoked interactively; CI supplies `--non-interactive --confirm` only after its approval gate.

## Success Output

Commands write human-readable progress to stderr and exactly one JSON document to stdout.

```json
{
  "schemaVersion": "1.0",
  "action": "deploy",
  "status": "Succeeded",
  "operationId": "platform-prod-20260721T120000Z",
  "platform": {
    "resourceGroupName": "rg-gamevault-platform-prod",
    "frontDoorProfileId": "/subscriptions/.../providers/Microsoft.Cdn/profiles/...",
    "frontDoorId": "redacted-non-secret-identifier",
    "endpointCapacity": 25,
    "registeredEndpointCount": 0,
    "wafMode": "Detection"
  },
  "diagnostics": []
}
```

## Failure Output

```json
{
  "schemaVersion": "1.0",
  "action": "deploy",
  "status": "Failed",
  "operationId": "platform-prod-20260721T120000Z",
  "platform": null,
  "diagnostics": [
    {
      "code": "AZURE_VALIDATION_FAILED",
      "message": "Deployment validation failed; no resources were changed."
    }
  ]
}
```

Failures return a nonzero exit code. Output MUST NOT contain access keys, SAS tokens, deployment credentials, or unmasked secrets.

## Idempotency

- Repeating `deploy` with unchanged inputs returns `Succeeded` or `NoChange` and stable resource IDs.
- `what-if` after a successful unchanged deployment reports no create, modify, or delete operations.
- Complete deployment mode is prohibited.