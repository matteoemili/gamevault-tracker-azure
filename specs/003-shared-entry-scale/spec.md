# Feature Specification: Shared Entry Scale

**Feature Branch**: `exploration`

**Created**: 2026-08-25

**Status**: Draft

**Input**: User description: "Use the previous scaling exploration to replace the per-instance hosting and routing model with Design 1: one shared application deployment behind one shared protected entry point, before adding Entra-linked instances."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operate One Shared Service (Priority: P1)

As a platform operator, I can deploy and update one shared GameVault service that all future logical instances use, without creating a separate application deployment or public route for each instance.

**Why this priority**: The current one-deployment-per-instance model reaches a hard capacity limit after ten free deployments in one subscription. A shared service removes that limit at its source.

**Independent Test**: Deploy the shared service in a clean environment, publish one application update, and verify that the same protected public address serves the updated application without any per-instance infrastructure.

**Acceptance Scenarios**:

1. **Given** no shared service exists in an environment, **When** an operator performs the standard deployment, **Then** exactly one application deployment and one protected public entry point become available.
2. **Given** the shared service is healthy, **When** an operator publishes an application update, **Then** the update becomes available through the existing public address without creating another application deployment or public route.
3. **Given** the shared service is redeployed repeatedly, **When** operators inspect the environment, **Then** the number of shared application and entry resources remains constant.

---

### User Story 2 - Add Logical Instances Without Infrastructure Growth (Priority: P2)

As a platform operator, I can add logical instance identities to the shared service without provisioning dedicated hosting, routing, or resource groups for those instances.

**Why this priority**: A shared deployment is only a scalable foundation if adding an instance becomes a data operation rather than an infrastructure operation.

**Independent Test**: Add 10,000 distinct logical instance records to a test environment and verify that the public service remains available while its shared infrastructure resource count does not increase.

**Acceptance Scenarios**:

1. **Given** the shared service is deployed, **When** an operator adds a logical instance, **Then** the instance receives a stable unique identity without receiving dedicated hosting or routing resources.
2. **Given** 10,000 logical instances have been added, **When** the platform inventory is compared with its initial inventory, **Then** no additional application deployments, public endpoints, routes, or instance resource groups exist.
3. **Given** two logical instances have distinct identities, **When** their records are inspected, **Then** their identities and reserved data namespaces cannot collide.

---

### User Story 3 - Preserve Shared Protection and Operations (Priority: P3)

As a platform operator, I retain the existing central protection, health visibility, access restrictions, diagnostics, and cost controls while moving from per-instance routes to one shared route.

**Why this priority**: Scaling must not require abandoning the security and operational controls already delivered by the shared entry platform.

**Independent Test**: Exercise healthy, abusive, and unavailable-origin requests through the shared address and verify that protection, controlled failure, diagnostics, alerts, and operator visibility continue to work.

**Acceptance Scenarios**:

1. **Given** the shared service is healthy, **When** representative requests arrive, **Then** they pass through the centrally managed protection policy and reach the shared application.
2. **Given** abusive traffic exceeds the configured policy, **When** it reaches the shared address, **Then** the shared protection policy applies consistently to all requests.
3. **Given** the shared application becomes unavailable for a sustained period, **When** operators inspect alerts and diagnostics, **Then** they can identify the shared-service failure and a safe recovery action.
4. **Given** a request uses a reserved authentication path, **When** it passes through the shared entry point, **Then** the response bypasses shared caching and remains available for a future identity feature to configure.

---

### User Story 4 - Migrate Without Disrupting Existing Instances (Priority: P4)

As a platform operator, I can introduce the shared service without automatically deleting or changing existing per-instance deployments, so migration and rollback remain controlled.

**Why this priority**: Existing deployments and automation represent working infrastructure. The new foundation must be introduced safely before obsolete resources are retired.

**Independent Test**: Deploy the shared service alongside at least two legacy instances, verify all addresses remain available, then roll back the shared deployment without changing either legacy instance.

**Acceptance Scenarios**:

1. **Given** legacy per-instance deployments exist, **When** the shared service is deployed, **Then** those deployments and their public addresses remain unchanged.
2. **Given** the shared deployment fails, **When** the workflow ends, **Then** no legacy instance is deleted, rerouted, or reported as successfully migrated.
3. **Given** the shared service has been validated, **When** an operator reviews the deployment result, **Then** obsolete per-instance lifecycle capabilities are clearly identified for a later controlled retirement.

### Edge Cases

- The shared service is deployed while legacy instances are still receiving traffic.
- Two operators attempt to create the same logical instance identity concurrently.
- A logical instance identifier contains unsupported characters, differs only by case, or exceeds its allowed length.
- The shared application deploys successfully but the shared public entry point is unhealthy.
- The public entry point is healthy but the shared application origin is unavailable.
- A repeated deployment attempts to create duplicate shared resources.
- A reserved authentication request is cached by an intermediary.
- Monitoring, alerting, or cost controls fail to attach while the public service itself is reachable.
- A deployment is cancelled after changing the shared application but before validating the public address.
- The test logical-instance population greatly exceeds the former ten-instance limit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST expose one stable, secure public address for the shared GameVault service in each supported environment.
- **FR-002**: The platform MUST operate one shared application deployment and one shared protected entry path per environment, independent of the number of logical instances.
- **FR-003**: Adding, updating, or removing a logical instance MUST NOT create, update, or delete dedicated application hosting, public endpoints, public routes, or resource groups.
- **FR-004**: The platform MUST support at least 10,000 logical instances in one subscription without increasing the count of shared application or entry resources.
- **FR-005**: Each logical instance MUST have a stable, unique, case-normalized identifier and a non-colliding reserved data namespace.
- **FR-006**: Logical-instance creation MUST be idempotent for the same identifier and MUST reject conflicting identities before changing persistent state.
- **FR-007**: One application publication MUST update the service used by every logical instance without requiring instance-specific deployments.
- **FR-008**: The shared public entry point MUST preserve centrally managed request protection, abusive-traffic controls, secure transport, health visibility, diagnostics, alerting, access restrictions, ownership metadata, and cost controls.
- **FR-009**: The shared service MUST return a controlled unavailable response when its application origin is unhealthy and MUST NOT route requests to a legacy instance as a fallback.
- **FR-010**: Reserved authentication paths MUST bypass shared response caching and MUST NOT be rewritten by the shared entry layer; redirect-host binding remains the responsibility of the later identity and custom-domain feature.
- **FR-011**: Deployment and validation MUST be idempotent and MUST NOT create duplicate shared resources after repeated runs.
- **FR-012**: A failed deployment or validation MUST preserve the last known working shared configuration and produce an actionable, credential-free diagnostic result.
- **FR-013**: Successful deployments MUST report the shared public address, health status, environment, and validation outcome without requiring operators to inspect platform configuration manually.
- **FR-014**: Introducing the shared service MUST NOT automatically delete, reroute, or modify existing per-instance deployments.
- **FR-015**: The standard delivery workflow MUST stop creating per-instance application and entry resources for the new shared-service path.
- **FR-016**: The platform MUST identify the legacy per-instance registration lifecycle as superseded for new logical instances while retaining an explicit operator-controlled path for later cleanup.
- **FR-017**: Shared-service management MUST remain restricted to explicitly authorized operator and deployment identities using least privilege.
- **FR-018**: The platform MUST provide inventory evidence that the shared resource count remains constant as logical-instance count grows.

### Scope Boundaries

**In scope**:

- One shared application deployment and one shared protected public entry point per environment.
- Logical instance identities and reserved, non-colliding data namespaces.
- Constant-resource validation at a scale of at least 10,000 logical instances.
- Preservation of the current central protection, monitoring, alerting, access, ownership, and cost controls.
- Delivery-workflow changes needed to stop per-instance hosting and route creation.
- Safe coexistence with legacy per-instance deployments.
- Future authentication-path compatibility at the shared public entry point.

**Out of scope**:

- Microsoft Entra directory creation, user registration, sign-in, or linking users to logical instances.
- End-user authorization and enforcement of access to a logical instance's data namespace.
- Per-user or per-instance public hostnames, custom domains, or tenant branding.
- Automatic migration of existing instance data into shared storage.
- Automatic deletion of legacy resource groups, application deployments, storage accounts, or public routes.
- Dedicated-resource premium tiers and deployment-stamp automation.
- Multi-subscription sharding as the primary scaling mechanism.

### Key Entities

- **Shared Service**: The single application deployment used by every logical instance in one environment, including its lifecycle and health state.
- **Shared Entry Point**: The stable protected public address, central policy, route, diagnostics, and operational state through which the shared service is reached.
- **Logical Instance**: A stable identity representing a future tenant or user-owned GameVault without dedicated hosting or routing resources.
- **Data Namespace Reservation**: The unique namespace assigned to a logical instance so future data and access-control features can isolate its records without changing the hosting topology.
- **Legacy Instance**: An existing self-contained deployment created under the previous per-instance infrastructure model.
- **Deployment Result**: The auditable outcome of deploying and validating the shared service, including its address, health, environment, inventory evidence, and sanitized diagnostics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A test population of 10,000 logical instances increases the count of shared application deployments, public endpoints, routes, origin associations, and resource groups by zero.
- **SC-002**: Twenty consecutive shared-service deployments preserve one stable public address and produce no duplicate shared resources.
- **SC-003**: One successful application publication makes the same version available to 100% of tested logical instances without any instance-specific deployment.
- **SC-004**: At least 95% of representative requests receive a successful response or a controlled unavailable response within 3 seconds under expected load.
- **SC-005**: 100% of tested insecure requests are upgraded to secure transport, and 100% of tested requests pass through the shared protection policy.
- **SC-006**: Reserved authentication-path tests produce zero cached responses and zero path rewrites by the shared entry layer.
- **SC-007**: Operators receive an actionable alert within 5 minutes of a sustained shared-entry or shared-origin failure and can identify the failed stage from the alert alone.
- **SC-008**: Deploying or rolling back the shared service causes zero routing, availability, or resource changes to two or more representative legacy instances.
- **SC-009**: 100% of duplicate or conflicting logical-instance creation attempts either return the existing identity or fail without partial state.
- **SC-010**: An operator can find the shared address, current health, environment, deployment outcome, and constant-resource inventory evidence within 5 minutes using deployment results alone.

## Assumptions

- The selected scaling model is Design 1 from the prior exploration: one shared application behind one shared protected public entry point using its provider-assigned hostname.
- Distinct per-instance public addresses are not required for this feature.
- The application bundle is identical across logical instances; instance-specific behavior will come from later identity and data-context features.
- A single subscription must support the target logical-instance population; creating unbounded subscriptions is not an accepted scaling strategy.
- Existing central protection, monitoring, access, and cost controls remain valuable and should be preserved.
- Existing per-instance deployments may coexist with the shared service until a separately approved migration and cleanup feature retires them.
- Logical-instance namespace reservation prepares the data model but does not itself authorize end-user access.
- Future identity work will derive the active logical instance from trusted identity context rather than from an untrusted client-supplied identifier.
- A provider-assigned Front Door hostname is sufficient for scale and protection, but a later identity feature may require a custom domain to keep authentication redirects on the public entry host.
