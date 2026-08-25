# Contract: Logical Instance CLI

## Command

```text
scripts/logical-instance.sh <create|show|list|retire|bulk-create> [options]
```

The command uses Azure identity-based Table access, invokes no ARM deployment, and follows the repository JSON envelope and redaction conventions.

## Common Options

| Option | Rule |
|---|---|
| `--environment <dev\|staging\|prod>` | Required |
| `--subscription-id <uuid>` | Required |
| `--storage-account-name <name>` | Required |
| `--table-name <name>` | Defaults to `logicalinstances` |

## Actions

### `create`

Additional options:

| Option | Rule |
|---|---|
| `--logical-instance-id <id>` | Required; normalized to lowercase, 3-32 chars, `^[a-z0-9][a-z0-9-]*[a-z0-9]$` |
| `--display-name <name>` | Required; 1-100 characters |

Creates one `Reserved` record with `dataNamespace` equal to the normalized ID and a deterministic `instance-xx` metadata partition.

- Same normalized ID and all stored values: return `NoChange`.
- Same normalized ID with a different display name or other stored value: return `Failed` with `INSTANCE_CONFLICT`.
- Existing retired ID: return `Failed` with `INSTANCE_RETIRED`.
- Existing incompatible immutable values: return `Failed` with `INSTANCE_CONFLICT`.
- Concurrent creates: exactly one succeeds; equivalent losers return `NoChange`; incompatible losers fail.

### `show`

Returns one logical instance by normalized ID. Absence fails with `INSTANCE_NOT_FOUND`.

### `list`

Returns all records by default, with optional `--state <Reserved\|Retired>`. Results are sorted by normalized ID. Pagination must be followed until complete; 10,000 records cannot be silently truncated.

### `retire`

Requires `--logical-instance-id` and `--confirm`. Performs a soft transition to `Retired`, sets `retiredAt`, and leaves the namespace reserved. Repeating retire returns `NoChange`. It deletes no infrastructure or application data.

### `bulk-create`

Requires `--input-jsonl <file>` and `--confirm`. This operator-only action:

- validates the complete file before mutation;
- normalizes and de-duplicates IDs;
- groups entities by deterministic metadata partition;
- writes groups of at most 100 entities per transaction;
- applies the same idempotency/conflict rules as `create`;
- reports created, unchanged, and failed counts plus redacted per-record diagnostics;
- exits nonzero if any record conflicts or any batch is partial.

The 10,000-record scale proof uses this action rather than spawning 10,000 independent Azure CLI processes.

## Result Envelope

```json
{
  "schemaVersion": "1.0",
  "action": "Create",
  "status": "Succeeded",
  "operationId": "logical-instance-demo-20260825T160000Z",
  "logicalInstance": {
    "id": "demo-user",
    "displayName": "Demo User",
    "dataNamespace": "demo-user",
    "environment": "dev",
    "state": "Reserved",
    "createdAt": "2026-08-25T16:00:00Z",
    "updatedAt": "2026-08-25T16:00:00Z",
    "retiredAt": null,
    "metadataVersion": 1
  },
  "diagnostics": []
}
```

The result must not expose ETags as caller-controlled values, storage credentials, authorization headers, or account keys.

## Constant-Resource Invariant

Contract tests inspect the CLI and reject references to:

- `az deployment`
- `az group create`
- `az staticwebapp create`
- `az afd endpoint`
- `instance-route.sh register`

Live scale validation snapshots shared resource IDs and counts before and after one 10,000-record `bulk-create` and requires exact equality.
