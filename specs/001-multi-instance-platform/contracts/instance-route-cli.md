# Contract: Instance Route Lifecycle CLI

## Command Shape

```text
./scripts/instance-route.sh <register|verify|status|unregister> [options]
```

Common required options:

```text
--instance-id <lowercase-alphanumeric>
--instance-resource-group <name>
--static-web-app-name <name>
--platform-resource-group <name>
--front-door-profile <name>
--subscription-id <uuid>
```

`register` accepts an optional `--origin-hostname`; when omitted, it resolves the hostname from the named Static Web App and validates resource ownership. `unregister` requires `--confirm` and deletes only deterministically named, matching-tag route resources.

## Preconditions

- The shared platform exists and has fewer than 25 endpoints, unless updating the same instance.
- The instance ID matches `^[a-z0-9]{1,8}$`.
- The Static Web App exists in the supplied resource group and subscription.
- The origin hostname is HTTPS reachable and ends in `.azurestaticapps.net`.
- No endpoint or tagged route resources belong to a different instance ID.
- Azure validation and what-if succeed before mutation.

## Registration Success Output

```json
{
  "schemaVersion": "1.0",
  "action": "register",
  "status": "Succeeded",
  "operationId": "route-abc12345-20260721T120000Z",
  "instance": {
    "instanceId": "abc12345",
    "resourceGroupName": "rg-gamevault-abc12345",
    "staticWebAppName": "swa-gamevault-prod-abc12345",
    "originHostName": "example.azurestaticapps.net"
  },
  "route": {
    "endpointName": "gvt-prod-abc12345-<stable-suffix>",
    "endpointHostName": "gvt-prod-abc12345-<stable-suffix>.z01.azurefd.net",
    "url": "https://gvt-prod-abc12345-<stable-suffix>.z01.azurefd.net",
    "originGroupName": "og-abc12345",
    "originName": "origin-abc12345",
    "routeName": "route-abc12345",
    "provisioningState": "Succeeded"
  },
  "diagnostics": []
}
```

## Verification Output

`verify` checks resource associations, origin host header, HTTPS redirect, endpoint response, and isolation headers/content supplied by the test fixture. It returns `Succeeded`, `Degraded`, or `Failed` with individual checks.

## Idempotency and Failure Preservation

- Registering the same instance and origin repeatedly preserves the endpoint hostname and returns `NoChange` after convergence.
- Updating an origin changes only the matching origin resource and preserves the active route until validation succeeds.
- A conflict, capacity failure, or validation error causes no active routing mutation.
- Unregistering an absent instance returns `NoChange`.
- The 26th distinct instance is rejected with `ENDPOINT_CAPACITY_EXCEEDED`.

## Concurrency

Mutating commands use an Azure deployment name and instance-scoped concurrency key derived from platform ID plus instance ID. A second mutation for the same instance fails fast or waits with a bounded timeout; mutations for unrelated instances may proceed only when Front Door control-plane limits allow it.