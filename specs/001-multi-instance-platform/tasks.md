# Tasks: Multi-Instance Entry Platform

**Input**: Design documents from `/specs/001-multi-instance-platform/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Included because the specification defines explicit routing-isolation, idempotency, capacity, health, authorization, and deregistration acceptance tests.

**Organization**: Tasks are grouped by user story and deliberately scoped to a single owning file so another LLM can implement one task without rediscovering the architecture or modifying unrelated work.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel after its phase prerequisites because it owns a different file and does not depend on an incomplete task in the same phase
- **[Story]**: Maps implementation work to User Story 1, 2, or 3 from `spec.md`
- Every task names the exact file it owns; dependencies inside a phase are stated explicitly

## Phase 1: Setup (Project Structure)

**Purpose**: Establish the platform deployment and test entry points without changing Azure resources

- [x] T001 Create the shared-platform Bicep entry point with target scope, typed environment inputs, required tags, and placeholder module composition in infra/platform/main.bicep
- [x] T002 [P] Create safe development defaults for subscription-selected local deployment in infra/platform/main.dev.bicepparam
- [x] T003 [P] Create production parameters with explicit owner, cost-center, budget, alert-recipient, and WAF-mode inputs in infra/platform/main.prod.bicepparam
- [x] T004 [P] Add Bicep analyzer settings that fail on secret outputs and enforce current resource API validation in bicepconfig.json
- [x] T005 Add platform-specific validation, test, and ShellCheck commands without changing the existing application commands in package.json

**Checkpoint**: The repository has stable entry points and parameters, but no shared Azure resources are deployable yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Provide the contracts, common shell behavior, and offline validation required by every story

**Critical**: Complete this phase before any user-story phase begins.

- [x] T006 [P] Define the non-secret platform command result schema for `validate`, `what-if`, `deploy`, `outputs`, and `status` in tests/infrastructure/contracts/platform-output.schema.json
- [x] T007 [P] Define the instance lifecycle result schema for `register`, `verify`, `status`, and `unregister` in tests/infrastructure/contracts/instance-route-output.schema.json
- [x] T008 [P] Implement schema validation for representative success, failure, and `NoChange` command results in tests/infrastructure/contracts/output-schema.sh
- [x] T009 Implement Bash 3.2-compatible argument parsing, Azure login/subscription checks, stderr logging, JSON result creation, secret redaction, and fail-fast helpers in scripts/lib/azure-common.sh
- [x] T010 Implement local Bicep build/lint, shell syntax, optional ShellCheck, and JSON-schema checks with no Azure mutation in tests/infrastructure/contracts/offline-validation.sh
- [x] T011 Implement `validate`, `what-if`, `deploy`, `outputs`, and `status` command dispatch with usage errors delegated to the shared helpers in scripts/platform.sh
- [x] T012 [P] Implement `register`, `verify`, `status`, and `unregister` command dispatch with usage errors delegated to the shared helpers in scripts/instance-route.sh
- [x] T013 Add stable platform outputs for profile identity, Front Door ID, maintenance host, endpoint capacity, registered endpoint count, WAF mode, and workspace ID in infra/platform/main.bicep

**Checkpoint**: Offline validation passes, command envelopes conform to both schemas, and mutating commands still refuse to run until story modules exist.

---

## Phase 3: User Story 1 - Reach the Correct Instance (Priority: P1) MVP

**Goal**: Publish one Azure-managed HTTPS address per instance and guarantee that requests cannot reach another instance, including during origin failure.

**Independent Test**: Deploy two instances with distinguishable fixture markers, register their route modules directly, and verify HTTPS redirect, one-to-one routing, controlled unavailability, and zero cross-instance responses.

### Tests for User Story 1

- [x] T014 [P] [US1] Add static assertions that every route references its matching origin group, every application group has one application origin, and no group contains another instance origin in tests/infrastructure/contracts/route-isolation.sh
- [x] T015 [P] [US1] Add HTTP/HTTPS redirect, TLS hostname, origin host-header, and root-relative SPA asset checks in tests/infrastructure/integration/secure-routing.sh
- [x] T016 [P] [US1] Add two-instance marker verification and repeated-request cross-instance detection in tests/infrastructure/integration/routing-isolation.sh
- [x] T017 [P] [US1] Add unhealthy-origin verification that accepts only the generic maintenance response or Front Door 503 and rejects another instance marker in tests/infrastructure/integration/controlled-unavailability.sh
- [x] T018 [P] [US1] Add a 25-instance generated deployment fixture and assert every instance has a unique endpoint, route, group, origin, and deterministic name in tests/infrastructure/fixtures/generate-capacity-parameters.sh

### Implementation for User Story 1

- [x] T019 [P] [US1] Provision a shared HTTPS StorageV2 static website containing no tenant data, disable unnecessary services, and expose only its maintenance hostname in infra/platform/modules/maintenance-origin.bicep
- [x] T020 [P] [US1] Add the generic cache-disabled unavailable page with a correlation identifier placeholder in infra/platform/assets/maintenance/index.html
- [x] T021 [US1] Provision the Premium Front Door profile with deterministic naming, required ownership tags, TLS defaults, and endpoint-capacity metadata in infra/platform/modules/front-door.bicep
- [x] T022 [US1] Provision one deterministic endpoint, one route, one origin group, and one HTTPS-only Static Web App origin with the exact origin host header in infra/platform/modules/instance-route.bicep
- [x] T023 [US1] Add the optional lower-priority maintenance origin without adding any other application origin to the instance group in infra/platform/modules/instance-route.bicep
- [x] T024 [US1] Compose Front Door and maintenance modules while keeping all per-instance route deployments outside the base deployment in infra/platform/main.bicep
- [x] T025 [US1] Add a direct per-instance Bicep deployment harness that resolves an existing Static Web App and emits the Azure-managed endpoint URL in infra/platform/instance-route.bicep
- [x] T026 [US1] Document the repeatable two-instance deployment, direct route-module invocation, failure simulation, and US1 acceptance commands in tests/infrastructure/integration/README.md

**Checkpoint**: User Story 1 is independently deployable and passes secure routing, isolation, capacity, and controlled-unavailability checks without lifecycle automation.

---

## Phase 4: User Story 2 - Register Instances Through Automation (Priority: P2)

**Goal**: Let local commands and the existing deployment workflow create or update exactly one instance route idempotently, with validation and machine-readable results.

**Independent Test**: Deploy a new instance through automation, register it, rerun registration 20 times, and confirm one stable endpoint URL; invalid and conflicting inputs must leave the active route unchanged.

### Tests for User Story 2

- [x] T027 [P] [US2] Add platform CLI contract tests for local-only validation, Azure validation, what-if, confirmation, non-interactive mode, JSON-only stdout, and nonzero failures in tests/infrastructure/contracts/platform-cli.sh
- [x] T028 [P] [US2] Add instance CLI contract tests for required options, identifier syntax, origin resolution, JSON-only stdout, and secret-free diagnostics in tests/infrastructure/contracts/instance-route-cli.sh
- [x] T029 [P] [US2] Add a 20-rerun registration test that asserts one endpoint resource and an unchanged Azure-managed hostname in tests/infrastructure/integration/registration-idempotency.sh
- [x] T030 [P] [US2] Add invalid scope, malformed ID, hostname conflict, unreachable origin, and exhausted-capacity tests that assert an empty what-if or preserved route in tests/infrastructure/integration/registration-rejection.sh
- [x] T031 [P] [US2] Add an origin-change test that verifies the current route remains active until the replacement origin passes validation in tests/infrastructure/integration/origin-update-preservation.sh

### Implementation for User Story 2

- [x] T032 [US2] Implement local-only build plus Azure `validate`, `what-if`, incremental `deploy`, normalized outputs, idempotent `NoChange`, and mandatory confirmation behavior in scripts/platform.sh
- [x] T033 [US2] Implement instance ID, subscription, resource-group ownership, Static Web App type, HTTPS hostname, reachability, conflict, and 25-endpoint capacity preflight checks in scripts/instance-route.sh
- [x] T034 [US2] Implement deterministic incremental registration and origin update through infra/platform/instance-route.bicep with instance-scoped deployment names in scripts/instance-route.sh
- [x] T035 [US2] Implement route `status` and `verify` checks for resource associations, HTTPS redirect, origin host header, endpoint response, provisioning state, and stable URL in scripts/instance-route.sh
- [x] T036 [US2] Add the Static Web App resource ID and stable registration inputs to the existing instance deployment outputs in infra/main.bicep
- [x] T037 [US2] Generate the per-instance forwarding-gateway configuration only after route verification, allowing the Front Door backend service tag, required Front Door ID, and generated endpoint host in scripts/instance-route.sh
- [x] T038 [US2] Update instance deployment to consume shared-platform outputs, call the local registration command, retain its JSON artifact, and verify the published URL in .github/workflows/ci-cd.yml
- [x] T039 [US2] Replace secret-based Azure login with GitHub OIDC, separate shared-platform and instance-route permissions, and environment/instance concurrency keys in .github/workflows/ci-cd.yml
- [x] T040 [US2] Document local registration, rerun, invalid-input recovery, origin-update, and CI-equivalence acceptance commands in specs/001-multi-instance-platform/quickstart.md

**Checkpoint**: User Story 2 can be executed locally or by CI/CD through the same scripts, and all reruns, rejections, and origin updates preserve one stable public address.

---

## Phase 5: User Story 3 - Operate the Shared Platform (Priority: P3)

**Goal**: Give operators health, audit, protection, budget visibility, least-privilege control, and safe instance retirement without affecting active routes.

**Independent Test**: Simulate one unhealthy origin, locate the instance-specific signal and alert, attempt an unauthorized route change, then deregister that instance and prove every other route is unchanged.

### Tests for User Story 3

- [x] T041 [P] [US3] Add assertions for Front Door access, health-probe, WAF, and activity records with at least 90-day workspace retention in tests/infrastructure/integration/observability.sh
- [x] T042 [P] [US3] Add a sustained origin-failure test that asserts the alert identifies the instance and fires within five minutes in tests/infrastructure/integration/health-alert.sh
- [x] T043 [P] [US3] Add an unauthorized-principal test that expects route mutation denial and locates the denied operation in activity records in tests/infrastructure/integration/authorization-audit.sh
- [x] T044 [P] [US3] Add deregistration and repeated-deregistration tests that snapshot all sibling route resource IDs before and after removal in tests/infrastructure/integration/deregistration-isolation.sh
- [x] T045 [P] [US3] Add orphan detection for endpoint resources whose tagged instance resource group or Static Web App no longer exists in tests/infrastructure/integration/orphan-detection.sh

### Implementation for User Story 3

- [x] T046 [P] [US3] Provision a 90-day Log Analytics workspace and Front Door access, health-probe, and WAF diagnostic settings in infra/platform/modules/monitoring.bicep
- [x] T047 [US3] Provision action groups plus shared-entry, repeated-origin-health, certificate, deployment-failure, and endpoint-capacity alerts with instance-identifying dimensions in infra/platform/modules/monitoring.bicep
- [x] T048 [P] [US3] Provision least-privilege operator, shared-platform deployment, and instance-route deployment role assignments from principal IDs in infra/platform/modules/rbac.bicep
- [x] T049 [P] [US3] Provision environment budget alerts and tag-based application cost attribution using configurable thresholds in infra/platform/modules/cost-management.bicep
- [x] T050 [US3] Provision a centrally associated Front Door WAF policy with managed rules and bot protection, parameterized for detection-to-prevention promotion in infra/platform/modules/front-door.bicep
- [x] T051 [US3] Compose monitoring, RBAC, cost management, and WAF outputs without introducing instance-resource-group dependencies in infra/platform/main.bicep
- [x] T052 [US3] Implement guarded deregistration that validates deterministic names and ownership tags, deletes only the matching endpoint graph, and returns `NoChange` when absent in scripts/instance-route.sh
- [x] T053 [US3] Implement orphan reporting, per-instance health status, last lifecycle operation, capacity status, and actionable diagnostics in scripts/instance-route.sh
- [x] T054 [US3] Document health investigation, WAF promotion, denied-operation audit, orphan cleanup, and safe retirement acceptance commands in specs/001-multi-instance-platform/quickstart.md

**Checkpoint**: User Story 3 passes health, alerting, authorization, audit, orphan, and retirement tests while all unaffected routes remain available.

---

## Phase 6: Polish & Cross-Cutting Validation

**Purpose**: Prove the complete platform against the measurable outcomes and make the local-first workflow maintainable.

- [x] T055 [P] Add a single ordered runner for contract, deployment, routing, lifecycle, security, and observability checks in tests/infrastructure/run-all.sh
- [x] T056 [P] Add shell linting and Bicep build validation for every infrastructure and lifecycle script change in .github/workflows/validate-infrastructure.yml
- [x] T057 Add a 25-instance acceptance runner covering routing isolation, 20 idempotent reruns, controlled failures, and capacity rejection in tests/infrastructure/integration/platform-acceptance.sh
- [x] T058 Add operator-facing deployment stages, rollback boundaries, expected JSON outputs, and troubleshooting links in DEPLOYMENT.md
- [x] T059 Add the shared platform topology, no-domain URL model, security boundaries, service limits, and future profile-sharding trigger in docs/INFRASTRUCTURE.md
- [x] T060 Run every command in the implemented operator workflow and record verified prerequisites, durations, and expected outcomes in specs/001-multi-instance-platform/quickstart.md

**Checkpoint**: All feature outcomes have an executable check, documentation matches implemented commands, and CI invokes rather than duplicates local lifecycle logic.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 - Setup**: Starts immediately; T001 precedes T013 and T024, while T002-T005 can run in parallel.
- **Phase 2 - Foundational**: Depends on Phase 1; blocks all user stories. T006-T008 can run in parallel, T009 precedes T011-T012, and T013 completes the command/output foundation.
- **Phase 3 - US1**: Depends on Phase 2. Tests T014-T018 are authored first and must fail for the missing behavior; T019-T020 can run in parallel, then T021-T025 implement the routing graph before T026 validates it.
- **Phase 4 - US2**: Depends on the US1 route module and Phase 2 CLI foundation. Tests T027-T031 are authored first; T032-T037 implement lifecycle behavior before workflow tasks T038-T039 and validation task T040.
- **Phase 5 - US3**: Depends on the US1 resource graph and US2 lifecycle identity. Tests T041-T045 are authored first; T046, T048, and T049 can run in parallel, then T047 and T050-T053 complete operations before T054.
- **Phase 6 - Polish**: Depends on all stories selected for release; T055-T059 can be divided by file before final end-to-end execution in T060.

### User Story Dependency Graph

```text
Setup -> Foundation -> US1 (isolated routing MVP)
                          |
                          v
                    US2 (automation)
                          |
                          v
                    US3 (operations)
                          |
                          v
                    Cross-cutting validation
```

- **US1 is the MVP** and can be demonstrated independently through direct Bicep route deployments.
- **US2 depends on US1's route module**, but its CLI and workflow behavior remains independently testable with a single instance.
- **US3 depends on stable route identity from US1 and lifecycle metadata from US2**, but monitoring and authorization modules have separate file ownership.

### Parallel Opportunities

- Setup tasks T002-T004 can run concurrently after T001 defines parameter names.
- Foundation schema tasks T006-T008 and the instance dispatcher T012 can be delegated separately.
- US1 test tasks T014-T018 can run concurrently; maintenance tasks T019-T020 can run concurrently.
- US2 test tasks T027-T031 can run concurrently because each owns a separate script.
- US3 test tasks T041-T045 can run concurrently; module tasks T046, T048, and T049 can run concurrently.
- Cross-cutting tasks T055-T059 own separate files and can run concurrently after story completion.

## Parallel Execution Examples

### User Story 1

```text
LLM A: T014 in tests/infrastructure/contracts/route-isolation.sh
LLM B: T015 in tests/infrastructure/integration/secure-routing.sh
LLM C: T016 in tests/infrastructure/integration/routing-isolation.sh
LLM D: T017 in tests/infrastructure/integration/controlled-unavailability.sh
LLM E: T018 in tests/infrastructure/fixtures/generate-capacity-parameters.sh
```

After those tests are reviewed, T019 and T020 can run concurrently; T021-T025 then proceed in dependency order.

### User Story 2

```text
LLM A: T027 in tests/infrastructure/contracts/platform-cli.sh
LLM B: T028 in tests/infrastructure/contracts/instance-route-cli.sh
LLM C: T029 in tests/infrastructure/integration/registration-idempotency.sh
LLM D: T030 in tests/infrastructure/integration/registration-rejection.sh
LLM E: T031 in tests/infrastructure/integration/origin-update-preservation.sh
```

After the tests fail for the expected missing behavior, assign T032 and T033 to the script owners sequentially; Bicep output task T036 can proceed separately.

### User Story 3

```text
LLM A: T041 in tests/infrastructure/integration/observability.sh
LLM B: T042 in tests/infrastructure/integration/health-alert.sh
LLM C: T043 in tests/infrastructure/integration/authorization-audit.sh
LLM D: T044 in tests/infrastructure/integration/deregistration-isolation.sh
LLM E: T045 in tests/infrastructure/integration/orphan-detection.sh
```

After test review, T046, T048, and T049 can be implemented concurrently by separate LLMs.

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases.
2. Complete US1 tests before implementation and verify they initially fail for missing resources.
3. Implement T019-T025 and run T014-T018 until all pass.
4. Stop and demonstrate two isolated Azure-managed instance addresses plus controlled unavailable behavior.

### Incremental Delivery

1. **Foundation**: Offline validation and stable command contracts, with no Azure mutation.
2. **US1 MVP**: Domain-free secure routing and hard isolation through direct Bicep deployments.
3. **US2**: Local lifecycle automation, idempotent registration, and CI/CD composition.
4. **US3**: Monitoring, protection, least privilege, cost controls, and safe retirement.
5. **Release proof**: Full 25-instance and failure-path acceptance run.

### Individual LLM Handoff Protocol

For each task, the implementing LLM must:

1. Read the task's owning file if it exists plus the linked contract or test named by the task.
2. Modify only the owning file unless a concrete compile error requires a dependency edit; report that dependency instead of broad refactoring.
3. Run the narrowest test named by the task, followed by offline validation from tests/infrastructure/contracts/offline-validation.sh.
4. Record the command and result when marking the task complete; never mark dependent tasks complete automatically.
5. Preserve existing user changes and leave Azure mutation behind explicit `validate`, `what-if`, and confirmation gates.

## Notes

- `[P]` means file ownership and dependencies permit concurrent work; it does not permit concurrent mutations of the same Azure profile.
- Tests in each story are authored before implementation and must demonstrate the expected missing behavior before the story is built.
- No task introduces custom DNS, custom certificates, cross-instance failover, Front Door Private Link for Static Web Apps, or a separate registration database.
- Every mutating operation must preserve the last known working route on validation or deployment failure.