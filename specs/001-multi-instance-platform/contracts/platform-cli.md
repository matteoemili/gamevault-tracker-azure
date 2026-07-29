# Contract: Platform Lifecycle CLI

## Command Shape

```text
./scripts/platform.sh <validate|what-if|deploy|outputs|status|retire-profile> [options]
```

Required options for Azure-scoped commands:

```text
--environment <dev|staging|prod>
--subscription-id <uuid>
--resource-group <name>
--location <azure-region>
```

`validate` performs local Bicep compilation followed by Azure deployment validation when authenticated. `what-if` never mutates resources. `deploy` MUST internally rerun validation and what-if and requires `--confirm` when invoked interactively; CI supplies `--non-interactive --confirm` only after its approval gate.

## SKU Change and `retire-profile`

Azure does not support downgrading a Front Door profile from Premium to Standard in place, and a WAF policy's SKU must match its profile. Changing `frontDoorSku` in a parameter file from `Premium_AzureFrontDoor` to `Standard_AzureFrontDoor` therefore cannot be applied by `deploy` alone; the deployment fails on the immutable SKU property.

`retire-profile` deletes exactly the two SKU-locked resources - the Front Door profile and its WAF policy - and nothing else. The resource group, Log Analytics workspace, diagnostic settings, alerts, action group, budget, role assignments, and maintenance origin are all preserved so that `deploy` recreates only the profile.

`retire-profile` MUST:

- require `--confirm`;
- capture the profile ID, Front Door ID, SKU-derived endpoint capacity, and registered instance list *before* deleting anything, and report them in the success envelope;
- delete the profile before the WAF policy, because the profile's security policy references it;
- return `NoChange` with a `PROFILE_NOT_FOUND` diagnostic when the profile is already absent; and
- emit `PROFILE_RETIRED`, `REREGISTRATION_REQUIRED`, and one `RETIRED_INSTANCE` diagnostic per affected instance.

Deleting the profile removes every instance endpoint, and recreation issues new `*.azurefd.net` hostnames. Every instance must be re-registered with `scripts/instance-route.sh register` and have its Table Storage CORS rules updated with `scripts/cors-add-origin.sh` afterwards. Upgrading Standard to Premium is supported in place and does not need this command.

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
    "endpointCapacity": 10,
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