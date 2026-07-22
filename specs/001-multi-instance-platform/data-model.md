# Data Model: Multi-Instance Entry Platform

The model describes Azure control-plane state and command results. It does not introduce an application database.

## Shared Entry Platform

| Field | Type | Rules |
|---|---|---|
| platformId | string | Stable lowercase identifier, 3-16 characters |
| subscriptionId | UUID | Must match the active or explicitly selected subscription |
| resourceGroupName | string | Dedicated shared group; must not equal an instance resource group |
| environment | enum | `dev`, `staging`, or `prod` |
| frontDoorProfileId | Azure resource ID | Premium profile in the shared resource group |
| frontDoorId | string | Output used by Static Web App forwarding-gateway restrictions |
| maintenanceOriginHost | hostname | Shared, non-tenant static content endpoint |
| endpointCapacity | integer | 25 for the initial Premium profile |
| registeredEndpointCount | integer | Computed from endpoint resources; must be 0-25 |
| logWorkspaceId | Azure resource ID | Workspace retaining platform logs for at least 90 days |
| wafMode | enum | `Detection` during rollout, then `Prevention` |
| tags | object | Includes application, environment, owner, managedBy, and cost center |

**Relationships**: Owns one Front Door profile, WAF policy, maintenance origin, monitoring configuration, and zero to 25 Instance Routes.

## Application Instance

| Field | Type | Rules |
|---|---|---|
| instanceId | string | Lowercase alphanumeric, 1-8 characters; stable across redeployments |
| environment | enum | Must match an allowed deployment environment |
| subscriptionId | UUID | Must match the platform subscription in v1 |
| resourceGroupName | string | Must exist and be distinct from the platform group |
| staticWebAppResourceId | Azure resource ID | Must resolve to the expected resource type and group |
| originHostName | hostname | Must be HTTPS-capable and end in `.azurestaticapps.net` |
| lifecycleState | enum | `Deployed`, `Registering`, `Registered`, `Updating`, `Unregistering`, `Retired`, `Failed` |

**Relationships**: Has at most one active Instance Route in the v1 platform profile.

## Instance Route

| Field | Type | Rules |
|---|---|---|
| instanceId | string | Foreign key to Application Instance |
| endpointName | string | Deterministically derived, globally unique, at most 46 characters |
| endpointHostName | hostname | Azure-generated `azurefd.net` hostname; immutable public address |
| originGroupName | string | Deterministically derived from instance ID |
| originName | string | Deterministically derived from instance ID |
| routeName | string | Deterministically derived from instance ID |
| originHostHeader | hostname | Exactly equals originHostName |
| forwardingProtocol | enum | `HttpsOnly` |
| httpsRedirect | boolean | Always true |
| enabled | boolean | False until origin and route validation succeeds |
| healthState | enum | `Unknown`, `Healthy`, `Degraded`, `Unavailable` |
| provisioningState | enum | `Pending`, `Succeeded`, `Failed`, `Deleting` |
| tags | object | Includes instanceId, instanceResourceGroup, environment, and managedBy |

**Isolation invariant**: The route references only its matching origin group. The group contains exactly one application origin and may contain only the shared maintenance origin as a fallback. It can never contain another Application Instance.

## Registration Record

| Field | Type | Rules |
|---|---|---|
| operationId | string | Azure deployment name or correlation identifier |
| action | enum | `Validate`, `WhatIf`, `Register`, `Update`, `Verify`, `Unregister` |
| instanceId | string | Required for instance lifecycle actions |
| requestedBy | string | Azure principal object ID; no credentials |
| startedAt | timestamp | UTC ISO 8601 |
| completedAt | timestamp | UTC ISO 8601 when terminal |
| previousState | object | Resource IDs and ETags sufficient to confirm preservation |
| resultingState | object | Normalized route outputs; secrets excluded |
| status | enum | `Pending`, `Succeeded`, `Failed`, `NoChange` |
| diagnostics | array | Redacted error codes and actionable messages |

## Health Event

| Field | Type | Rules |
|---|---|---|
| timestamp | timestamp | UTC event time |
| platformId | string | Required |
| instanceId | string or null | Null only for shared-platform events |
| signalType | enum | `Endpoint`, `Origin`, `WAF`, `Capacity`, `Deployment`, `Cost` |
| previousState | string | Optional for initial observation |
| currentState | string | Required |
| correlationId | string | Connects alert, log, and deployment records |
| actionableMessage | string | Identifies scope and next operator action without secrets |

## State Transitions

```text
Deployed -> Registering -> Registered
                    \-> Failed -> Registering
Registered -> Updating -> Registered
                    \-> Failed (last working route preserved)
Registered -> Unregistering -> Retired
                         \-> Failed -> Unregistering
```

Route activation occurs only after the origin is reachable and the deployment succeeds. Origin hardening occurs only after the Azure-provided endpoint passes verification.