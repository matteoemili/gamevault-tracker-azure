# Contract: Shared Service CLI

## Command

```text
scripts/shared-service.sh <validate|what-if|deploy|verify|status> [options]
```

The command is Bash 3.2-compatible, non-interactive except for explicit deployment confirmation, writes progress to stderr, writes exactly one JSON document to stdout, and exits nonzero on failure.

## Common Options

| Option | Rule |
|---|---|
| `--environment <dev\|staging\|prod>` | Required |
| `--subscription-id <uuid>` | Required for Azure operations |
| `--shared-resource-group <name>` | Required |
| `--platform-resource-group <name>` | Required for route actions |
| `--front-door-profile <name>` | Required for route actions |
| `--location <region>` | Required for first deployment |
| `--confirm` | Required for `deploy` |
| `--local-only` | Allowed only for `validate`; performs no Azure calls |

## Actions

### `validate`

Builds shared application and shared-route templates, validates required inputs, confirms deterministic names, and optionally runs Azure deployment validation. It performs no mutation.

### `what-if`

Runs resource-group what-if for the shared application and shared route in deployment order. The result must identify no legacy resource deletion or modification.

### `deploy`

1. Captures shared and legacy inventory.
2. Validates and runs what-if.
3. Deploys the shared Standard application resources and Table data-role assignments.
4. Resolves the shared SWA origin hostname.
5. Deploys the dedicated shared Front Door profile and one shared route.
6. Configures shared-origin CORS.
7. Verifies the route.
8. On bootstrap, generates forwarding-gateway configuration and requires the caller to rebuild/re-upload the application before final verification; on steady-state deploys, verifies the already-restricted upload.
9. Captures resulting inventory and emits the stable public address.

A failure after a previous successful deployment preserves the last known working route and reports the failed stage.

### `verify`

Validates control-plane properties and performs bounded HTTPS probes:

- exactly one deterministic shared profile, endpoint, and route exist;
- route references only the shared origin group;
- application origin host and host header match the shared SWA;
- HTTPS redirect is enabled;
- WAF association includes the shared endpoint;
- `/.auth/*` cache-bypass/no-path-rewrite rule is attached;
- the public root returns success or controlled maintenance;
- no legacy endpoint or origin is attached to the shared route.

### `status`

Returns stable resource IDs, public address, origin hostname, route health, WAF mode, monitoring identifiers, logical-instance count, and shared inventory counts.

## Result Envelope

```json
{
  "schemaVersion": "1.0",
  "action": "Deploy",
  "status": "Succeeded",
  "operationId": "shared-prod-20260825T160000Z",
  "sharedService": {
    "environment": "prod",
    "resourceGroupName": "rg-gamevault-shared-prod",
    "staticWebAppId": "/subscriptions/.../staticSites/...",
    "storageAccountId": "/subscriptions/.../storageAccounts/...",
    "frontDoorProfileId": "/subscriptions/.../profiles/...",
    "endpointId": "/subscriptions/.../afdEndpoints/...",
    "publicUrl": "https://example-hash.z01.azurefd.net",
    "originHostName": "example.azurestaticapps.net",
    "healthState": "Healthy",
    "logicalInstanceCount": 0,
    "resourceCounts": {
      "staticWebApps": 1,
      "endpoints": 1,
      "routes": 1,
      "originGroups": 1,
      "applicationOrigins": 1
    }
  },
  "diagnostics": []
}
```

Secrets, deployment tokens, SAS values, account keys, bearer tokens, connection strings, and unredacted command output are forbidden.

## Idempotency

- Repeating `deploy` with unchanged inputs returns `NoChange` or `Succeeded` with the same public URL and resource IDs.
- The twentieth consecutive deployment creates no duplicate resource.
- Logical-instance count never changes shared resource counts.
