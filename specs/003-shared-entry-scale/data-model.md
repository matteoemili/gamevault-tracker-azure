# Data Model: Shared Entry Scale

The model separates constant Azure control-plane state from unbounded logical-instance records. It reserves namespaces for later identity and data-isolation work but does not grant end-user access.

## Shared Service

| Field | Type | Rules |
|---|---|---|
| environment | enum | `dev`, `staging`, or `prod`; one shared service per environment |
| subscriptionId | UUID | Explicit selected subscription |
| resourceGroupName | string | Stable environment-scoped shared-service resource group |
| staticWebAppId | Azure resource ID | Exactly one active shared application |
| staticWebAppHostName | hostname | Azure-provided secure origin hostname |
| storageAccountId | Azure resource ID | Exactly one shared application storage account |
| gamesTableName | string | Existing application table name |
| categoriesTableName | string | Existing application table name |
| logicalInstancesTableName | string | Defaults to `logicalinstances` |
| lifecycleState | enum | `Planned`, `Deploying`, `Deployed`, `Publishing`, `Published`, `Failed` |
| tags | object | Application, environment, owner, managedBy, component, cost center |

**Relationships**: Has one Shared Entry Point and zero or more Logical Instances. Does not own or mutate Legacy Instances.

## Shared Entry Point

| Field | Type | Rules |
|---|---|---|
| environment | enum | Matches Shared Service |
| frontDoorProfileId | Azure resource ID | Existing environment platform profile |
| endpointId | Azure resource ID | Exactly one deterministic shared endpoint |
| endpointHostName | hostname | Stable Azure-provided `azurefd.net` address |
| originGroupId | Azure resource ID | References only the shared SWA and optional maintenance origin |
| applicationOriginId | Azure resource ID | Host header equals shared SWA hostname |
| maintenanceOriginId | Azure resource ID or null | Contains no logical-instance data |
| routeId | Azure resource ID | Matches all application paths |
| wafPolicyId | Azure resource ID | Existing central policy |
| authCacheBypass | boolean | Always true for `/.auth/*` |
| healthState | enum | `Unknown`, `Healthy`, `Degraded`, `Unavailable` |
| provisioningState | enum | `Pending`, `Succeeded`, `Failed` |

**Routing invariant**: The shared route can reference only the shared origin group. The group can contain the shared application origin and optional generic maintenance origin; it can never contain a legacy application origin.

## Logical Instance

Stored in the `logicalinstances` table.

| Field | Type | Rules |
|---|---|---|
| PartitionKey | string | `instance-` plus deterministic two-hex-character digest prefix of normalized ID |
| RowKey | string | Normalized logical-instance ID; globally unique within an environment |
| displayName | string | Operator-facing label, 1-100 characters; immutable in this feature |
| dataNamespace | string | Immutable; equals normalized ID for this feature |
| environment | enum | Matches Shared Service |
| state | enum | `Reserved` or `Retired` |
| createdAt | timestamp | UTC ISO 8601; immutable |
| createdBy | string | Azure principal object ID or auditable workflow identity; no credentials |
| updatedAt | timestamp | UTC ISO 8601 |
| retiredAt | timestamp or null | Required only in `Retired` state |
| metadataVersion | integer | Starts at 1; supports future schema migration |
| ETag | string | Service concurrency token, never accepted from an untrusted caller |

### Validation

- Normalize the requested ID to lowercase before validation.
- ID is 3-32 characters and matches `^[a-z0-9][a-z0-9-]*[a-z0-9]$`.
- A repeated `create` with the same normalized ID, namespace, display name, and environment returns `NoChange`.
- A create collision with any incompatible field, including display name, fails without overwrite.
- `dataNamespace` cannot change after creation.
- `displayName` cannot change in this feature; a future update contract may add that transition.
- Retirement is soft and guarded; it does not delete data or infrastructure.
- Retired identifiers remain reserved and cannot be claimed as a new instance.

### State Transitions

```text
(absent) -> Reserved
Reserved -> Reserved  (idempotent create with identical values)
Reserved -> Retired   (guarded operator action)
Retired  -> Retired   (idempotent retire)
```

Reactivation is excluded because future identity and data-retention requirements must define its semantics.

## Legacy Instance

| Field | Type | Rules |
|---|---|---|
| instanceId | string | Existing legacy identifier |
| resourceGroupName | string | Existing isolated resource group |
| staticWebAppId | Azure resource ID | Existing application |
| storageAccountId | Azure resource ID | Existing data store |
| endpointId | Azure resource ID | Existing per-instance Front Door endpoint |
| publicAddress | URL | Existing stable address |
| coexistenceState | enum | `Unchanged`, `VerificationFailed` |

Legacy Instance is read-only in this feature. Inventory snapshots are used only to prove preservation.

## Deployment Result

| Field | Type | Rules |
|---|---|---|
| schemaVersion | string | `1.0` |
| action | enum | `Validate`, `WhatIf`, `Deploy`, `Verify`, `Status` |
| status | enum | `Succeeded`, `NoChange`, `Degraded`, `Failed` |
| operationId | string | Environment-scoped correlation identifier |
| environment | enum | Required |
| sharedService | object or null | Stable IDs, hostnames, health, and inventory counts; no secrets |
| beforeInventory | object or null | Counts and IDs captured before mutation |
| afterInventory | object or null | Counts and IDs captured after mutation |
| diagnostics | array | Redacted code/message objects |

## Logical-Instance Operation Result

| Field | Type | Rules |
|---|---|---|
| schemaVersion | string | `1.0` |
| action | enum | `Create`, `Show`, `List`, `Retire` |
| status | enum | `Succeeded`, `NoChange`, `Failed` |
| operationId | string | Correlation identifier |
| logicalInstance | object, array, or null | Never contains credentials or storage authorization |
| diagnostics | array | Redacted code/message objects |
