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

`verify` requires `--expected-origin-hostname` (also accepted as
`--expected-origin-host`). The value is the deployed Static Web App hostname
and must end in `.azurestaticapps.net`. Verification compares the deployed
origin `hostName` and `originHostHeader` with that explicit value; it does not
mutate the route or make a live HTTP(S) request.

## Preconditions

- The shared platform exists and has fewer than 25 endpoints, unless updating the same instance.
- The instance ID matches `^[a-z0-9]{1,8}$`.
- The Static Web App exists in the supplied resource group and subscription.
- The origin hostname is HTTPS reachable and ends in `.azurestaticapps.net`.
- Registration rejects an endpoint-name conflict when the deterministic endpoint name is tagged for another instance.
- When an endpoint already exists for the instance, its `instanceResourceGroup` and `staticWebAppName` tags must match the requested resources; otherwise registration fails before deployment.
- `unregister` requires `--confirm`, a deterministic endpoint name, and matching `instanceId`, `instanceResourceGroup`, and `staticWebAppName` ownership tags. An ownership mismatch prevents teardown.
- Registration runs Azure validation and what-if before mutation. A new instance is rejected when the profile already has 25 endpoints.

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

`verify` returns the standard envelope with `status: "Succeeded"` when all
checks pass, or `status: "Degraded"` when any check fails. It checks:

- route provisioning state is `Succeeded`;
- the endpoint is enabled and successfully provisioned;
- the route is enabled, associated with the instance origin group, supports
  HTTP and HTTPS on `/*`, redirects HTTP to HTTPS, enables the default domain,
  and uses `HttpsOnly` forwarding;
- the origin group is successfully provisioned and has the Bicep-defined load
  balancing and HTTPS health-probe settings; and
- the enabled application origin belongs to that origin group, is successfully
  provisioned, and has the expected Static Web App value for both `hostName`
  and `originHostHeader`, plus the Bicep-defined port, priority, weight, and
  certificate-check defaults.

The implemented checks do not inspect isolation headers or content. A
degraded verification does not generate the forwarding-gateway configuration.
`Failed` is reserved for command/precondition failures (for example, a
missing route), not an individual verification check.

## Statuses and Diagnostics

Every invocation writes one JSON document to stdout, using the schema shown
above, and writes progress text to stderr. `status` returns `NoChange` with
null `instance` and `route` when no matching route is found. For an existing
route it returns `Succeeded` and may include these diagnostics:
`CAPACITY_STATUS`, `HEALTHY` or `ENDPOINT_UNHEALTHY`,
`ORPHANED_ROUTE`, and `LAST_LIFECYCLE_OPERATION`.

Failures use `status: "Failed"` and null data with a redacted diagnostic
`code` and `message`. Implemented failure codes include
`INVALID_ORIGIN_HOSTNAME`, `ORIGIN_UNREACHABLE`,
`ENDPOINT_NAME_CONFLICT`, `OWNERSHIP_TAG_MISMATCH`,
`ENDPOINT_CAPACITY_EXCEEDED`, `AZURE_VALIDATION_FAILED`,
`AZURE_WHATIF_FAILED`, `AZURE_DEPLOY_FAILED`, `CONFIRMATION_REQUIRED`,
`ENDPOINT_NAME_MISMATCH`, `WAF_ASSOCIATION_UPDATE_FAILED`,
`AZURE_DELETE_FAILED`, and `ROUTE_DELETE_INCOMPLETE`. Registration may
return `Degraded` with `ENDPOINT_VERIFICATION_PENDING` when deployment
completes but the generated endpoint is not yet reachable. Verification
check failures use `ROUTE_NOT_PROVISIONED`, `ORIGIN_NOT_FOUND`,
`ENDPOINT_CONFIGURATION_MISMATCH`, `ROUTE_CONFIGURATION_MISMATCH`,
`ORIGIN_GROUP_CONFIGURATION_MISMATCH`, or `ORIGIN_CONFIGURATION_MISMATCH`.

## Idempotency and Failure Preservation

- Registering the same instance and origin repeatedly preserves the endpoint hostname and returns `NoChange` after convergence.
- Updating an origin changes only the matching origin resource and preserves the active route until validation succeeds.
- A conflict, capacity failure, or validation/what-if error causes no deployment mutation. A deployment failure does not roll back Azure changes; the script reports `AZURE_DEPLOY_FAILED` and states that a prior route, if present, was preserved.
- Unregistering an absent instance returns `NoChange`.
- The 26th distinct instance is rejected with `ENDPOINT_CAPACITY_EXCEEDED`.

Lifecycle operations are not transactions. `unregister` removes the WAF
association before deleting the route graph; route and origin-group delete
errors are not rolled back, and a failed endpoint deletion returns
`AZURE_DELETE_FAILED`. A subsequent `ROUTE_DELETE_INCOMPLETE` check detects an
endpoint that remains. Callers must inspect `status` and Azure resources before
retrying or completing cleanup.

## Concurrency

Mutating commands use an Azure deployment name and instance-scoped concurrency key derived from platform ID plus instance ID. A second mutation for the same instance fails fast or waits with a bounded timeout; mutations for unrelated instances may proceed only when Front Door control-plane limits allow it.