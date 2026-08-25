# Contract: Shared Service Workflow

## Trigger Behavior

| Trigger | Required behavior |
|---|---|
| Push to `main` | Validate and deploy/update one shared environment; upload twice only on bootstrap, otherwise once; verify shared route |
| Manual dispatch | Same as push for the selected environment; no instance ID input |
| Pull request open/update | Build and run offline contracts; create no resource group, SWA, storage account, Front Door endpoint, or route |
| Pull request close | No per-PR resource deletion, because this feature creates no per-PR persistent resources |

## Required Ordering

The persistent deployment path executes:

1. Check out source and run offline contracts.
2. Authenticate to Azure.
3. Validate and what-if shared application and route.
4. Deploy or update the one shared application infrastructure.
5. Build and upload the application. On bootstrap this first upload is unrestricted; on steady state it includes the existing forwarding-gateway restriction.
6. Validate the deployed SWA hostname.
7. Deploy/update the dedicated shared Front Door profile and route.
8. Configure shared storage CORS for the shared public URL.
9. Verify control-plane route properties and public HTTPS behavior.
10. On bootstrap only, generate forwarding-gateway configuration, rebuild/re-upload the application a second time, then verify routed success and direct-origin denial.
11. Report the stable public URL and upload sanitized artifacts under `if: always()`.

## Concurrency

- Persistent deployment uses one environment-scoped concurrency key.
- `cancel-in-progress` is false.
- Logical-instance registry operations are not serialized with application builds because they cannot mutate shared infrastructure.
- Pull-request validation may run concurrently.

## Forbidden New-Path Behavior

The workflow and its shared-service pipeline adapters must not:

- accept or derive an instance ID for persistent deployment;
- generate a resource-group suffix from a run, branch, or pull-request number;
- invoke `infra/main.bicep`;
- invoke `instance-route.sh register`, `verify`, or `unregister`;
- create one Static Web App or Front Door endpoint per run or logical instance;
- attach the shared endpoint to a capacity-constrained legacy profile;
- delete legacy resource groups on pull-request close.

Legacy scripts remain present but cannot be reachable from the new shared persistent path.

## Artifacts

Artifact name: `shared-service-<environment>-<run-id>`.

| File | Requirement |
|---|---|
| `shared-validation.json` | Always retained after Azure authentication |
| `shared-what-if.json` | Retained before mutation |
| `shared-deployment.json` | Retained when deployment is attempted |
| `shared-route-verification.json` | Retained when route verification is attempted |
| `shared-inventory-before.json` | Retained before mutation |
| `shared-inventory-after.json` | Retained after mutation or best-effort after failure |
| `shared-publication-result.json` | Always initialized and retained |

All artifacts exclude credentials, deployment tokens, SAS values, account keys, and bearer tokens.

## Success Gate

The workflow reports success only when:

- application upload succeeded;
- one shared public HTTPS URL is present;
- route verification is `Succeeded`;
- inventory proves exactly one shared SWA and shared endpoint/route;
- the shared SWA is Standard and direct-origin bypass is denied after bootstrap hardening;
- no legacy inventory ID changed;
- the publication result is schema-valid.
