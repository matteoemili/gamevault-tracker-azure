# Feature Specification: Multi-Instance Entry Platform

**Feature Branch**: `full-infra`

**Created**: 2026-07-21

**Status**: Draft

**Input**: User description: "Build proper Azure infrastructure for this application so multiple self-contained instances can be deployed in their own resource groups through the existing automations, supported by overarching infrastructure that provides global traffic entry and any other justified shared services."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reach the Correct Instance (Priority: P1)

As an application user, I can open the published address for a specific GameVault instance and reliably reach that instance without being routed to another instance or exposed to its data.

**Why this priority**: Correct, isolated routing is the core value of the shared platform. Without it, multiple independently owned instances cannot safely share an entry layer.

**Independent Test**: Deploy two instances with distinguishable content, register both, and verify that each published address consistently serves only its assigned instance over a secure connection.

**Acceptance Scenarios**:

1. **Given** two healthy registered instances, **When** a user opens either instance's published address, **Then** the request reaches the matching instance and never the other instance.
2. **Given** a registered instance with a healthy origin, **When** a user connects using an insecure protocol, **Then** the user is redirected to a secure connection without losing the requested instance address.
3. **Given** one instance is unavailable, **When** a user opens that instance's address, **Then** the user receives a controlled unavailable response and is not sent to an instance containing different data.

---

### User Story 2 - Register Instances Through Automation (Priority: P2)

As a platform operator, I can deploy or redeploy an isolated instance through the existing automation and have its public route created or updated without manually changing shared infrastructure.

**Why this priority**: A shared entry layer only remains operable at scale if instance lifecycle changes are repeatable and do not require portal-based configuration.

**Independent Test**: Run the existing instance deployment automation with a new instance identifier and endpoint, then verify that the resulting route becomes available and a rerun updates it without creating a duplicate.

**Acceptance Scenarios**:

1. **Given** the shared platform is available, **When** automation deploys a new valid instance, **Then** the instance receives one unique published address and registration metadata records the association.
2. **Given** an instance is already registered, **When** automation redeploys it with the same instance identifier, **Then** the existing route is updated idempotently and no duplicate route is created.
3. **Given** registration inputs are missing, invalid, or conflict with another instance, **When** automation attempts registration, **Then** the operation fails before changing active routing and reports an actionable reason.

---

### User Story 3 - Operate the Shared Platform (Priority: P3)

As a platform operator, I can determine whether the shared entry layer and each registered route are healthy, identify failures, and remove retired instances without affecting active instances.

**Why this priority**: Operational visibility and lifecycle cleanup are necessary to keep a growing set of instances reliable, secure, and cost controlled.

**Independent Test**: Simulate an unhealthy origin, inspect the resulting health signal and alert, then deregister that origin and confirm other routes continue to work.

**Acceptance Scenarios**:

1. **Given** a registered origin becomes unhealthy, **When** health evaluation detects the failure, **Then** operators can identify the affected instance, failure time, and current status from shared operational records.
2. **Given** an instance is retired, **When** automation deregisters it, **Then** its public route and instance-specific shared configuration are removed without changing another instance's route.
3. **Given** an unauthorized identity attempts to add or modify a route, **When** the request is evaluated, **Then** it is denied and the attempt is recorded for audit.

### Edge Cases

- Two deployment runs attempt to register the same instance identifier or hostname concurrently.
- An instance deployment succeeds but registration with the shared entry layer fails.
- Registration succeeds but the instance origin is not yet healthy or is still propagating.
- A previously registered instance endpoint changes during redeployment.
- A certificate cannot be issued or renewed for an instance address.
- The shared entry layer is unavailable while existing instance origins remain available.
- An instance resource group is deleted without first running deregistration.
- An instance identifier contains unsupported characters or exceeds naming limits.
- A request uses an unknown, retired, or malformed hostname.
- Shared service quotas or configured cost thresholds are approached.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The platform MUST provide a shared, globally reachable entry point for all registered application instances.
- **FR-002**: The platform MUST map each published instance address to exactly one isolated instance origin using a stable instance identifier.
- **FR-003**: The platform MUST preserve isolation by preventing requests for one instance from being routed to another instance, including when the requested origin is unhealthy.
- **FR-004**: The platform MUST provide a unique secure hostname for every registered instance and MUST redirect insecure requests to secure connections.
- **FR-005**: The platform MUST provision and renew trusted certificates for published instance hostnames without routine operator intervention.
- **FR-006**: Existing deployment automation MUST be able to register a newly deployed instance using its identifier, resource-group identity, environment, and public origin endpoint.
- **FR-007**: Registration and update operations MUST be idempotent for the same instance identifier and MUST reject identifier or hostname conflicts before active routing changes.
- **FR-008**: The platform MUST validate that a proposed origin belongs to the expected Azure scope and uses an approved secure endpoint before registration.
- **FR-009**: The platform MUST support deregistration through automation and remove the retired instance's route, hostname association, and instance-specific shared configuration without impacting other instances.
- **FR-010**: The platform MUST detect unhealthy origins and expose health status per instance while returning a controlled unavailable response rather than failing over to another isolated instance.
- **FR-011**: The platform MUST retain operational records for registration, update, deregistration, routing-health changes, and denied management attempts for at least 90 days.
- **FR-012**: The platform MUST provide actionable alerts for shared entry-point failure, certificate failure, repeated origin-health failure, and capacity or quota risk.
- **FR-013**: The platform MUST restrict shared platform management to explicitly authorized deployment and operator identities using least-privilege access.
- **FR-014**: The platform MUST protect public instance entry points against common web threats and abusive traffic using centrally managed controls that can be applied consistently across instances.
- **FR-015**: The shared platform MUST be deployed and updated through repeatable automation, with configuration differences supplied as environment-specific inputs rather than manual changes.
- **FR-016**: The shared platform MUST reside outside every instance resource group so an instance can be created or deleted without creating or deleting the shared platform.
- **FR-017**: Shared resources and instance associations MUST carry ownership, environment, application, and management tags sufficient for inventory and cost allocation.
- **FR-018**: The platform MUST expose deployment outputs needed by instance automation, including the shared entry identity, hostname suffix or equivalent address rule, and registration status.
- **FR-019**: Failed registration or update operations MUST preserve the last known working route and provide enough diagnostic information for an operator to retry safely.
- **FR-020**: The first release MUST support at least 25 simultaneously registered instances without requiring a redesign of the routing or naming model.

### Scope Boundaries

**In scope**:

- A separately managed shared Azure platform for secure global entry, routing, health visibility, protection, and lifecycle integration.
- Automated onboarding, idempotent updates, and deregistration of instances deployed by the existing workflow.
- Shared domain and certificate lifecycle, operational monitoring, alerts, access control, tagging, and cost visibility.
- Updates to existing automation contracts needed to exchange instance identifiers, endpoints, and registration results.

**Out of scope**:

- Moving instance-owned application or data resources out of their individual resource groups.
- Sharing or replicating game and category data between instances.
- Routing users from an unavailable instance to a different instance.
- Building an end-user instance directory, sign-up experience, or tenant administration portal.
- Selecting the final Azure routing product or detailed resource topology; that decision belongs to planning and must be justified against these requirements.

### Key Entities

- **Shared Entry Platform**: The independently managed global access layer, including its public address rules, protection policy, health visibility, and ownership metadata.
- **Application Instance**: A self-contained deployment identified by a stable instance identifier, environment, resource group, origin endpoint, lifecycle state, and ownership metadata.
- **Instance Route**: The one-to-one association between a published hostname and an application instance origin, including health and activation status.
- **Registration Record**: The auditable result of onboarding, updating, or removing an instance, including the requesting identity, timestamps, validation outcome, and failure details.
- **Health Event**: A time-stamped change in reachability or certificate state associated with the shared platform or a specific instance route.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In routing-isolation tests across at least 25 registered instances, 100% of requests using a valid instance address reach only the assigned instance.
- **SC-002**: A newly deployed healthy instance becomes securely reachable at its published address within 10 minutes of its origin endpoint becoming available, without manual shared-platform changes.
- **SC-003**: Redeploying an existing instance 20 consecutive times produces no duplicate route or hostname association and preserves the same public address.
- **SC-004**: Removing one instance leaves all other tested instance addresses available, with zero unintended routing changes.
- **SC-005**: At least 95% of representative user requests receive a successful response or controlled instance-specific unavailable response within 3 seconds from each target geography under expected load.
- **SC-006**: Operators receive an actionable health or certificate alert within 5 minutes of a sustained failure condition and can identify the affected instance from the alert alone.
- **SC-007**: 100% of published instance addresses use trusted, current certificates, and no routine certificate renewal requires manual action during a 90-day observation period.
- **SC-008**: At least 90% of platform operators can identify an unhealthy instance and its latest lifecycle action within 5 minutes using the provided operational records.
- **SC-009**: All registration, update, and deregistration test runs either complete successfully or preserve the last known working route with an actionable failure reason.
- **SC-010**: Monthly shared-platform cost can be attributed to the application and environment, and operators are warned before configured budget or capacity thresholds are exceeded.

## Assumptions

- Each application instance remains a self-contained security and data boundary in its own resource group and exposes one stable, secure public origin endpoint.
- The platform owner does not own a public domain. Each instance is addressed by a unique Azure-provided Front Door endpoint hostname; custom domains and path-based tenancy are not required for the first release.
- Instances are distinct destinations rather than interchangeable replicas. An unhealthy instance therefore returns an unavailable response instead of failing over to another instance with different data.
- The shared platform is deployed once per chosen platform environment or subscription scope and has a lifecycle independent from all instance resource groups.
- The existing deployment automation remains the system that creates and redeploys instances and can consume shared-platform outputs and submit instance deployment outputs.
- The existing instance identifier is stable across redeployments and is suitable as the primary correlation key after syntax validation.
- A platform-owned identity is available, and operators can grant the minimum permissions needed for automated shared-platform and route management.
- The detailed choice among Azure Front Door, Azure Traffic Manager, or other justified Azure services will be made during planning based on secure HTTP routing, certificate lifecycle, protection, observability, cost, and operational complexity.
- Standard Azure regional and service availability constraints apply; disaster recovery for instance-owned data is outside this feature.

## Dependencies

- An Azure subscription scope in which shared resources can be deployed separately from instance resource groups.
- Existing instance automation outputs for instance identifier, resource group, environment, and public application endpoint.
- Authorized automation and operator identities with auditable, least-privilege access.
- Agreed expected-load profile, budget thresholds, and target geographies before production rollout.