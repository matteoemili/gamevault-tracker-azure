# Data Model: Automatic Front Door Registration

This feature adds no database. The model describes workflow state, existing Azure associations, and retained JSON results.

## Deployment Run

Represents one CI/CD attempt to create or update an instance.

| Field | Description | Validation |
|---|---|---|
| `runId` | Unique workflow run identifier | Non-empty and supplied by the delivery system |
| `trigger` | Push, pull request, or manual dispatch | One supported persistent-instance trigger |
| `environment` | Target platform environment | `dev`, `staging`, or `prod` |
| `instanceId` | Stable instance correlation key | Lowercase alphanumeric, 1-8 characters |
| `instanceResourceGroup` | Instance-owned Azure scope | Must differ from the platform resource group |
| `applicationDeploymentStatus` | Outcome of application upload | `Pending`, `Succeeded`, or `Failed` |
| `publicationStatus` | Overall publication outcome | See state transitions below |
| `publishedUrl` | Verified Front Door address | HTTPS URL; present only after registration discovers a route |

## Application Instance

Represents the existing isolated deployment consumed by registration.

| Field | Description | Validation |
|---|---|---|
| `instanceId` | Stable ownership key | Matches the deployment run |
| `resourceGroupName` | Instance resource group | Exists in the selected subscription |
| `staticWebAppName` | Application resource identity | Exists in the instance resource group |
| `originHostName` | Expected application origin | Secure Azure Static Web Apps hostname |
| `storageAccountName` | Instance Table Storage owner | Exists in the instance resource group |

## Platform Target

Represents explicit environment-specific publication configuration.

| Field | Description | Validation |
|---|---|---|
| `subscriptionId` | Azure subscription scope | Matches the authenticated deployment context |
| `environment` | Configuration selection key | Matches the application instance environment |
| `platformResourceGroup` | Shared platform scope | Non-empty and distinct from the instance scope |
| `frontDoorProfileName` | Existing Front Door profile | Must exist in the platform resource group |
| `concurrencyKey` | Shared mutation lock | Stable per profile, not per workflow run |

## Route Registration

Represents the existing one-to-one Azure Front Door association. Its detailed JSON shape remains governed by the existing instance-route output schema.

| Field | Description | Validation |
|---|---|---|
| `instanceId` | Route owner | Equals the application instance identifier |
| `endpointHostName` | Stable Front Door hostname | Unique within the profile and preserved on redeploy |
| `originHostName` | Current Static Web App origin | Equals the deployed application's expected hostname |
| `provisioningState` | Azure control-plane state | Must be `Succeeded` before publication completes |
| `registrationStatus` | Lifecycle command result | `Succeeded`, `NoChange`, `Degraded`, or `Failed` |

## Publication Result

Small workflow-level manifest that references, rather than duplicates, lifecycle result files.

| Field | Description | Validation |
|---|---|---|
| `schemaVersion` | Manifest contract version | `1.0` for this feature |
| `runId` | Parent deployment run | Non-empty |
| `instanceId` | Affected instance | Same key throughout the run |
| `stage` | Last attempted publication stage | `Preflight`, `Register`, `Cors`, `Verify`, or `Complete` |
| `status` | Workflow publication result | `Pending`, `Succeeded`, or `Failed` |
| `publishedUrl` | Front Door URL when discovered | HTTPS or null |
| `registrationResultFile` | Existing registration envelope path | Relative artifact path or null |
| `verificationResultFile` | Existing verification envelope path | Relative artifact path or null |
| `diagnostics` | Sanitized stage-level issues | No credentials, keys, tokens, or raw secret-bearing commands |

## Relationships

- One Deployment Run targets exactly one Application Instance.
- One Deployment Run resolves exactly one Platform Target.
- One Application Instance owns zero or one Route Registration in a profile.
- One Deployment Run retains exactly one Publication Result and may retain registration and verification envelopes.
- Multiple Deployment Runs for the same Application Instance converge on the same Route Registration.

## State Transitions

```text
Pending
  -> ApplicationFailed              (stop; no registration)
  -> PreflightFailed                (stop; no routing mutation)
  -> Registering
       -> RegistrationFailed        (stop; retain result)
       -> CorsAligning
            -> CorsFailed           (stop; retain registration)
            -> Verifying
                 -> Verifying       (bounded retry while degraded/pending)
                 -> VerificationFailed (timeout or terminal failure)
                 -> Published       (verified URL reported)
```

Redeployment follows the same transitions. A `NoChange` registration is valid input to verification; only verification `Succeeded` reaches `Published`.