# Feature Specification: Automatic Front Door Registration

**Feature Branch**: `full-infra`

**Created**: 2026-07-22

**Status**: Draft

**Input**: User description: "Amend the CI/CD pipeline to automatically register a newly deployed instance to Azure Front Door now that it is available."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Publish Every New Instance Automatically (Priority: P1)

As a platform operator, I can deploy a new GameVault instance through the existing delivery workflow and have it registered with the shared entry platform without performing a separate manual registration.

**Why this priority**: Automatic registration completes the deployment journey and ensures every successfully delivered instance has a consistent, supported public entry point.

**Independent Test**: Deploy one new healthy instance through the standard workflow and verify that the workflow reports one unique published address which reaches only that instance.

**Acceptance Scenarios**:

1. **Given** the shared entry platform is available and has capacity, **When** a new instance and its application are deployed successfully, **Then** the workflow registers that instance and reports its unique published address.
2. **Given** registration succeeds, **When** the workflow verifies the published address, **Then** the address securely serves the newly deployed instance and does not serve another instance.
3. **Given** the application deployment has not completed successfully, **When** the workflow evaluates registration eligibility, **Then** registration is not attempted and no route is created for the incomplete instance.

---

### User Story 2 - Redeploy Without Duplicate Routes (Priority: P2)

As a platform operator, I can redeploy an existing instance through the same workflow and retain its existing published address without creating duplicate shared routing resources.

**Why this priority**: Redeployment is a routine lifecycle event and must remain repeatable without route drift, address changes, or manual cleanup.

**Independent Test**: Deploy the same instance identifier repeatedly and verify that every successful run preserves one published address and one registration for that instance.

**Acceptance Scenarios**:

1. **Given** an instance is already registered, **When** it is redeployed with the same identity and origin, **Then** the workflow confirms the existing registration without creating a duplicate or changing the published address.
2. **Given** an instance is already registered and its valid origin has changed, **When** redeployment completes, **Then** only that instance's registration is updated and all other instance routes remain unchanged.
3. **Given** two workflow runs target the same instance concurrently, **When** both reach registration, **Then** their changes are serialized or one run stops safely without creating conflicting registrations.

---

### User Story 3 - Diagnose Registration Failures (Priority: P3)

As a platform operator, I can distinguish application deployment failures from shared-route registration or verification failures and obtain enough information to retry safely.

**Why this priority**: Automatic registration introduces a new deployment gate; clear outcomes prevent partially published instances from being mistaken for complete deployments.

**Independent Test**: Cause registration and verification failures independently, then confirm that each workflow run fails at the correct stage, preserves unrelated routes, and retains actionable diagnostic results.

**Acceptance Scenarios**:

1. **Given** required shared-platform configuration is missing or invalid, **When** registration begins, **Then** the workflow fails before changing active routing and identifies the missing or invalid input.
2. **Given** registration cannot complete because of a conflict, capacity limit, authorization failure, or unavailable shared platform, **When** the operation ends, **Then** the deployment is reported as incomplete and diagnostic results are retained.
3. **Given** registration completes but the published route does not pass verification, **When** the workflow ends, **Then** it reports failure, retains registration and verification results, and does not alter another instance's route.

### Edge Cases

- A new instance origin exists but is not yet ready when registration begins.
- Registration succeeds while public route propagation is still in progress.
- The shared entry platform has reached its configured instance capacity.
- The selected environment does not have a corresponding shared entry platform.
- The deployment identity can manage the instance but lacks permission to register routes in the shared platform.
- An instance identifier, resource group, or origin conflicts with an existing registration owned by another instance.
- A workflow is retried after registration succeeded but before verification completed.
- Storage access rules accept the direct instance address but not the newly published address.
- Diagnostic artifact upload runs after an earlier registration step failed and produced only partial output.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The delivery workflow MUST attempt shared-platform registration only after the target instance infrastructure and application deployment complete successfully.
- **FR-002**: The workflow MUST derive registration from the deployed instance's stable identifier, environment, resource group, application identity, origin address, subscription scope, and the matching shared-platform configuration.
- **FR-003**: The workflow MUST validate that all required registration inputs and the target shared entry platform are available before changing active routing.
- **FR-004**: A successful first deployment MUST create exactly one registration and one unique secure published address for the new instance.
- **FR-005**: Registration MUST preserve one-to-one routing so a published address can reach only its assigned instance, including when that instance is unhealthy.
- **FR-006**: Repeating the workflow for the same instance and unchanged origin MUST preserve the published address and MUST NOT create duplicate registration resources.
- **FR-007**: Redeploying an existing instance with a changed valid origin MUST update only that instance's registration without changing another instance's route.
- **FR-008**: Workflow runs that can mutate the same instance registration MUST be serialized or rejected safely, while unrelated instance deployments remain independently executable.
- **FR-009**: The workflow MUST align instance-owned access controls with the new published address before declaring the deployment complete.
- **FR-010**: The workflow MUST verify the registration association, secure published address, origin reachability, and instance isolation before reporting overall deployment success.
- **FR-011**: Registration or verification failure MUST cause the overall deployment workflow to report an incomplete outcome rather than a successful published deployment.
- **FR-012**: Validation, conflict, capacity, authorization, registration, and verification failures MUST produce actionable diagnostics that identify the affected instance and failed stage without exposing credentials.
- **FR-013**: Registration and verification results MUST be retained for every attempted registration, including failed and partially completed attempts.
- **FR-014**: A failed registration or update MUST preserve the last known working route and MUST NOT mutate routes belonging to other instances.
- **FR-015**: The workflow MUST use an auditable deployment identity with only the permissions required to inspect the instance and manage its registration in the shared platform.
- **FR-016**: Pull-request, manually dispatched, and branch-triggered instance deployments MUST follow the same registration and verification rules whenever they create or update a persistent instance.
- **FR-017**: The workflow MUST report the published address as a deployment result that operators can use without inspecting shared-platform configuration manually.

### Scope Boundaries

**In scope**:

- Automatic registration and verification after successful instance application deployment.
- Idempotent registration during redeployment of an existing instance.
- Alignment of instance access rules with the published address.
- Instance-scoped concurrency, failure handling, diagnostics, and deployment results.
- Use of the existing shared Azure Front Door platform and existing instance registration lifecycle.

**Out of scope**:

- Creating or redesigning the shared entry platform.
- Changing the public hostname model or introducing custom domains.
- Automatically deregistering retired instances or deleting pull-request infrastructure.
- Changing application data, authentication, or instance ownership boundaries.
- Routing an unavailable instance to a different instance.

### Key Entities

- **Deployment Run**: One automated attempt to create or update an instance, including its trigger, environment, target instance, stage outcomes, and final status.
- **Application Instance**: The isolated GameVault deployment identified by a stable instance identifier, environment, resource group, application identity, and origin address.
- **Route Registration**: The one-to-one association between an instance and its published address, including current origin, lifecycle status, and ownership metadata.
- **Registration Result**: The retained outcome of registration or verification, including the affected instance, operation identifier, status, published address when available, and sanitized diagnostics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 20 consecutive healthy new-instance deployments, 100% produce one verified published address without manual shared-platform changes.
- **SC-002**: A healthy newly deployed instance is reachable through its published address within 10 minutes of application deployment completion in at least 95% of workflow runs.
- **SC-003**: Twenty consecutive redeployments of the same instance preserve one registration and the same published address, with zero duplicate routes.
- **SC-004**: In isolation tests involving at least two registered instances, 100% of published-address requests reach only the assigned instance before and after redeployment.
- **SC-005**: 100% of simulated registration and verification failures cause the workflow to report an incomplete deployment and retain an instance-specific diagnostic result.
- **SC-006**: Registration failure tests produce zero unintended changes to previously working routes and zero changes to routes owned by other instances.
- **SC-007**: At least 90% of platform operators can identify the failed stage, affected instance, and safe retry action within 5 minutes using only the workflow result and retained diagnostics.
- **SC-008**: The published address is present in the final result of 100% of successful deployment runs and can be opened without additional operator lookup.

## Assumptions

- The shared Azure Front Door platform is already deployed and exposes a supported registration lifecycle for instance routes.
- The existing workflow remains responsible for deploying instance infrastructure and application content before registration.
- Each supported environment has an explicitly configured shared-platform resource group and matching Front Door profile.
- The instance deployment produces a stable instance identifier, resource group, application identity, origin address, and environment for registration.
- The existing registration lifecycle validates ownership, capacity, secure origin reachability, and conflicts before mutation, and verifies isolation afterward.
- The current limit of 25 registered instances per shared profile remains unchanged by this feature.
- A failed automatic registration leaves the instance origin deployed for diagnosis or safe retry; automatic rollback of the instance deployment is outside scope.
- Existing direct-origin access remains available unless separately restricted by an approved platform-hardening change.

## Dependencies

- A healthy shared Azure Front Door platform for each deployment environment.
- The existing instance route registration and verification contract.
- Deployment identity access to read instance resources and manage only the required shared-platform registration resources.
- Repository-level configuration that identifies the shared platform for each supported environment.
- Retained workflow artifacts or equivalent operational records for registration diagnostics.