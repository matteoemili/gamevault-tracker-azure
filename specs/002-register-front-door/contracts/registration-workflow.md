# Contract: Automatic Registration Workflow

## Eligibility

The publication phase runs for push, pull-request, and manual-dispatch workflows that create or update a persistent instance. It MUST NOT start unless instance infrastructure and application upload have succeeded.

## Required Inputs

| Input | Source | Rule |
|---|---|---|
| Instance ID | Infrastructure deployment output | Stable lowercase alphanumeric identifier |
| Instance resource group | Infrastructure deployment output | Must identify the deployed instance scope |
| Static Web App name | Infrastructure deployment output | Must identify the deployed application |
| Origin hostname | Infrastructure deployment output | Passed as the expected verification origin |
| Storage account name | Infrastructure deployment output | Used only for published-origin CORS alignment |
| Environment | Deployment selection | Resolves explicit platform configuration |
| Subscription ID | Authenticated Azure context | Must match the intended deployment subscription |
| Platform resource group | Environment-specific repository configuration | Required before registration |
| Front Door profile | Environment-specific repository configuration | Required before registration |

Missing or inconsistent inputs fail preflight before route mutation and are recorded in the publication result.

## Ordering

The workflow MUST execute these stages in order:

1. Validate inputs and initialize `publication-result.json`.
2. Run the existing `instance-route.sh register` command and capture `route-registration.json`.
3. Accept registration statuses `Succeeded`, `NoChange`, or `Degraded` only when a non-null HTTPS route URL is present; a degraded route still requires verification.
4. Add the published URL to instance Table Storage CORS idempotently.
5. Run the existing `instance-route.sh verify` command once with the deployed
   Static Web App hostname. It deterministically validates Azure Front Door
   control-plane properties and writes `route-verification.json`.
6. Accept only verification status `Succeeded` as publication success.
7. Publish the verified URL as a job output and in the workflow summary.
8. Upload all available sanitized result files under `if: always()`.

## Concurrency

- Infrastructure and application deployment MAY run concurrently for different instances.
- The publication phase MUST use `cancel-in-progress: false`.
- The publication concurrency key MUST be stable per Front Door profile while registration updates a shared WAF association collection.
- Retrying the same instance MUST converge on its existing endpoint hostname.

## Result Files

Artifact name: `route-registration-<instance-id>`.

| File | Requirement |
|---|---|
| `publication-result.json` | Always initialized before preflight and always retained |
| `route-registration.json` | Retained when registration is invoked, including schema-valid CLI failures |
| `route-verification.json` | Retained when verification occurs; contains the deterministic control-plane result |
| `route-forwarding-gateway.json` | Retained when generated; not applied by this feature |

All files MUST exclude account keys, SAS values, deployment credentials, bearer tokens, and unmasked secret-bearing command output.

## Failure Semantics

| Failure stage | Workflow outcome | Required preservation |
|---|---|---|
| Application deployment | Failed | Registration not invoked |
| Preflight | Failed | Publication result identifies missing or invalid configuration; no route mutation |
| Registration | Failed | Registration envelope and publication result retained; sibling routes unchanged |
| CORS alignment | Failed | Registration result retained; deployment not reported as published |
| Verification failure | Failed | Verification result retained; discovered route URL retained for diagnosis |
| Artifact upload | Warning only when files are partially absent | Available diagnostic files still uploaded |

## Validation Contract

Offline workflow checks MUST assert ordering, input mapping, profile-scoped concurrency, verification gating, URL reporting, and `always()` artifact retention. Live Azure tests MUST continue to own proof of route idempotency, origin update preservation, sibling isolation, and secure endpoint behavior.