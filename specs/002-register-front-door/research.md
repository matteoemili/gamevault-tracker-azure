# Research: Automatic Front Door Registration

## Existing Lifecycle Ownership

**Decision**: Keep `scripts/instance-route.sh` as the only implementation of registration, update, ownership validation, capacity checks, what-if, deployment, and route verification.

**Rationale**: The script already exposes stable structured output, deterministic naming, idempotent registration, and dedicated contract/integration coverage. CI/CD only needs to compose it after application deployment.

**Alternatives considered**: Reimplement registration with workflow-native Azure commands, create a composite action, or add a deployment service. Each duplicates proven behavior and expands the maintenance surface without adding user value.

## Publication Boundary and Ordering

**Decision**: Treat application upload, route registration, published-origin CORS alignment, verification, result publication, and artifact retention as one ordered publication phase after instance infrastructure succeeds.

**Rationale**: A route must never advertise an application that failed to deploy. A deployment is not complete until the published route is verified, and each later stage needs the prior stage's structured output.

**Alternatives considered**: Register immediately after infrastructure deployment or create a disabled route before application upload. Both add transient state and recovery paths without improving the current workflow.

## Platform Configuration

**Decision**: Resolve the platform resource group and Front Door profile from explicit environment-specific repository configuration, validate both before mutation, and pass the deployed Static Web App hostname as the expected origin.

**Rationale**: Constructing a profile name and using one unqualified resource-group variable can silently target the wrong platform. Explicit dev/staging/prod mappings are small, auditable, and fail early.

**Alternatives considered**: Discover profiles by tags or naming conventions. Discovery is flexible but ambiguous when profiles are missing, duplicated, or renamed.

## Concurrency

**Decision**: Keep infrastructure and application work parallel across instances, but serialize the short registration phase per Front Door profile while the shared WAF association remains a read-modify-write collection.

**Rationale**: Instance-scoped serialization does not prevent two instances from overwriting concurrent shared WAF association updates. Profile-scoped serialization is the smallest safe correction at the cost of only serializing the brief control-plane phase.

**Alternatives considered**: One security-policy association per endpoint would permit parallel writes but changes the shared platform resource model and is outside this feature.

## Propagation and Verification

**Decision**: Run the existing read-only verification command once against the
Azure control plane; accept only `Succeeded` as deployment success and retain
the deterministic result.

**Rationale**: Front Door data-plane propagation is asynchronous, so live
requests create false failures. Validating the deployed endpoint, route, origin
group, and origin configuration is deterministic and proves the intended
control-plane graph without arbitrary delay.

**Alternatives considered**: Live probing with retries, fixed sleep, or
accepting `Degraded`. These respectively create flaky deployments, waste time,
or report an invalid route graph as complete.

## CORS Ownership

**Decision**: For this increment, retain the existing post-registration CORS helper, make its Azure response parsing and duplicate detection reliable, and cover it with mocked contract tests. Ensure redeployment does not discard an already published origin before route registration can restore it.

**Rationale**: Browser access to Table Storage requires both the direct and Front Door origins. Fixing the focused helper is smaller than redesigning instance deployment around a multi-stage declarative feedback loop.

**Alternatives considered**: Make the initial Bicep deployment consume the not-yet-known Front Door hostname, or move all CORS management out of Bicep. Both require broader ownership changes and migration handling.

## Diagnostics and Published Result

**Decision**: Initialize a sanitized publication result before preflight, update it at each stage, always upload it with route results, and write the verified Front Door URL to the job summary and job output.

**Rationale**: Existing CLI failures produce structured JSON, but missing workflow configuration can fail before any file exists. One small stage manifest closes that gap without replacing existing envelopes.

**Alternatives considered**: Rely only on console logs or introduce a new comprehensive route schema. Logs are harder to audit; a duplicate schema would drift from the lifecycle contract.

## Identity

**Decision**: Reuse the current CI deployment identity for the nimble implementation, document and validate its required instance-read/platform-route permissions, and keep an OIDC/least-privilege identity migration as separate hardening work.

**Rationale**: Changing authentication and registration orchestration together increases rollout risk. The feature can still require an auditable identity, explicit scope, secret masking, and sanitized artifacts.

**Alternatives considered**: Migrate immediately to federated credentials and a custom role. This is preferable long term but is independently deployable and should not block publication correctness.

## Validation Strategy

**Decision**: Add fast static workflow and mocked CORS contracts to the existing offline suite, and reuse opt-in Azure integration tests for idempotency, rejected updates, origin replacement, secure routing, and isolation.

**Rationale**: Offline contracts provide deterministic pull-request feedback; live tests remain necessary only where Azure control-plane behavior or routing must be observed.

**Alternatives considered**: Mock the entire Azure CLI route lifecycle in workflow tests or run Azure deployments on every pull request. The former duplicates CLI tests; the latter is slow, costly, and mutation-heavy.

## Forwarding-Gateway Hardening

**Decision**: Retain the generated forwarding-gateway artifact but do not apply direct-origin restrictions in this feature.

**Rationale**: Applying it requires another application deployment and changes recovery behavior. The feature specification explicitly permits direct-origin access until a separate hardening rollout.

**Alternatives considered**: Apply restrictions immediately after route verification. This strengthens origin protection but substantially increases the change and rollback surface.