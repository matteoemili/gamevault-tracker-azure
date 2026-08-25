---

description: "Task list for Shared Entry Scale"
---

# Tasks: Shared Entry Scale

**Input**: Design documents from `/specs/003-shared-entry-scale/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Test tasks ARE included. The plan's Validation gate and Incremental Delivery step 1 require offline contracts before implementation, and every success criterion that depends on real Azure behaviour requires an opt-in live scenario.

**Organization**: Tasks are grouped by user story so each story can be implemented, validated, and demonstrated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This repository is a React static web application with Bicep infrastructure, Bash lifecycle automation, and GitHub Actions delivery. Paths follow the structure in [plan.md](plan.md):

- Shared application infrastructure: `infra/shared/`
- Shared entry platform: `infra/platform/`
- Lifecycle CLIs: `scripts/`
- Workflow adapters: `scripts/pipeline/shared-service/`
- Offline contracts: `tests/infrastructure/contracts/`
- Opt-in live scenarios: `tests/infrastructure/integration/`

**Legacy files that MUST NOT be modified or deleted by this feature**: `infra/main.bicep`, `infra/platform/modules/instance-route.bicep`, `infra/platform/instance-route.bicep`, `scripts/instance-route.sh`, `scripts/pipeline/front-door/*`.

---

## Phase 1: Setup (Shared Infrastructure Scaffolding)

**Purpose**: Create the new file boundaries and build entry points before any behaviour is written.

- [x] T001 Create the `infra/shared/` directory and an empty `infra/shared/main.bicep` with only the `targetScope = 'resourceGroup'` declaration and parameter block placeholders
- [x] T002 [P] Create `infra/shared/main.dev.bicepparam`, `infra/shared/main.staging.bicepparam`, and `infra/shared/main.prod.bicepparam` using `infra/main.dev.bicepparam` as the formatting reference, with `baseName='gamevault'`, no `instanceId` parameter, and environment-appropriate tags
- [x] T003 [P] Create the `scripts/pipeline/shared-service/` directory with a `.gitkeep` placeholder for the workflow adapters added in Phase 6
- [x] T004 [P] Add `infra:shared:build`, `infra:shared:validate`, and `infra:shared:test` npm scripts to `package.json` mirroring the existing `infra:platform:*` script conventions
- [x] T005 [P] Add `scripts/shared-service.sh` and `scripts/logical-instance.sh` as executable Bash 3.2 stubs that source `scripts/lib/azure-common.sh`, print usage to stderr, and exit 2 when invoked with no action

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared helpers, JSON schemas, and test-runner wiring that every user story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T006 Add a `normalize_logical_instance_id` helper to `scripts/lib/azure-common.sh` that lowercases input, trims whitespace, and validates `^[a-z0-9][a-z0-9-]*[a-z0-9]$` with a 3-32 character length, returning a distinct nonzero code for invalid input
- [x] T007 Add `capture_shared_inventory` and `compare_shared_inventory` helpers to `scripts/lib/azure-common.sh` that emit deterministic, sorted JSON counts and resource IDs for Static Web Apps, resource groups, Front Door endpoints, routes, origin groups, and origins in a given scope
- [x] T008 [P] Create `tests/infrastructure/contracts/shared-service-output.schema.json` as a JSON Schema draft 2020-12 document matching the Result Envelope in [contracts/shared-service-cli.md](contracts/shared-service-cli.md), using `tests/infrastructure/contracts/platform-output.schema.json` as the structural reference
- [x] T009 [P] Create `tests/infrastructure/contracts/logical-instance-output.schema.json` as a JSON Schema draft 2020-12 document matching the Result Envelope in [contracts/logical-instance-cli.md](contracts/logical-instance-cli.md), including the 3-32 character identifier pattern
- [x] T010 Register the new contract scripts and both new schemas in `tests/infrastructure/contracts/offline-validation.sh` so they run in the existing offline suite, including an `az bicep build` step for `infra/shared/main.bicep`
- [x] T011 Add the new offline contract invocations to `tests/infrastructure/run-all.sh` so `bash tests/infrastructure/run-all.sh` covers them without requiring `RUN_AZURE_INTEGRATION=1`

**Checkpoint**: Foundation ready — offline suite runs green against stubs and user story implementation can begin.

---

## Phase 3: User Story 1 - Operate One Shared Service (Priority: P1) 🎯 MVP

**Goal**: One shared application deployment behind one shared protected public entry point per environment, updated by a single publication, with a constant shared resource count across repeated deployments.

**Independent Test**: Deploy the shared service into a clean environment, publish one application update, and confirm the same protected public address serves the update with no per-instance infrastructure and no duplicate shared resources.

### Tests for User Story 1

> **NOTE: Write these tests FIRST and confirm they FAIL before implementation.**

- [x] T012 [P] [US1] Create `tests/infrastructure/contracts/shared-service-cli.sh` asserting the `validate|what-if|deploy|verify|status` action surface, required options, `--confirm` gating on `deploy`, `--local-only` restricted to `validate`, single-JSON-document stdout, and schema validation against `shared-service-output.schema.json`
- [x] T013 [P] [US1] Create `tests/infrastructure/integration/shared-route-idempotency.sh`, gated on `RUN_AZURE_INTEGRATION=1`, asserting that twenty consecutive `shared-service.sh deploy` runs preserve one public URL and one set of shared resource IDs with no duplicates (SC-002)

### Implementation for User Story 1

- [x] T014 [US1] Implement `infra/shared/main.bicep` creating exactly one StorageV2 account, its table service, the `games` and `categories` tables, and one Static Web App with a `staticWebAppSku` parameter defaulting to `Free`, using stable environment-scoped names with no instance identifier
- [x] T015 [US1] Add outputs to `infra/shared/main.bicep` for `staticWebAppName`, `staticWebAppId`, `staticWebAppDefaultHostname`, `storageAccountName`, `storageAccountId`, `tableEndpoint`, `gamesTableName`, `categoriesTableName`, and `resourceGroupName`
- [x] T016 [P] [US1] Create `infra/platform/modules/shared-route.bicep` creating one Front Door endpoint, one origin group with the existing 240 second probe interval, one application origin whose `originHostHeader` equals the shared Static Web Apps hostname with `enforceCertificateNameCheck` enabled, and one catch-all route with `httpsRedirect` enabled and `forwardingProtocol` set to `HttpsOnly`
- [x] T017 [US1] Add deterministic environment-scoped naming and outputs (`endpointName`, `endpointHostName`, `url`, `originGroupName`, `originName`, `routeName`, `routeProvisioningState`) to `infra/platform/modules/shared-route.bicep`, deriving names from `baseName` and `environment` only
- [x] T018 [US1] Implement argument parsing, environment validation, and the `validate` action in `scripts/shared-service.sh`, building both `infra/shared/main.bicep` and `infra/platform/modules/shared-route.bicep` and supporting `--local-only`
- [x] T019 [US1] Implement the `what-if` action in `scripts/shared-service.sh` running resource-group what-if for the shared application then the shared route, and failing when the preview reports any legacy resource deletion or modification
- [x] T020 [US1] Implement the `deploy` action in `scripts/shared-service.sh` following the ordered stages in [contracts/shared-service-cli.md](contracts/shared-service-cli.md): capture inventory, validate, what-if, deploy shared application, resolve the origin hostname, deploy the shared route, configure CORS, verify, capture inventory, emit the public address
- [x] T021 [US1] Implement the `verify` and `status` actions in `scripts/shared-service.sh` performing read-only control-plane property checks and returning stable resource IDs, public address, origin hostname, health, WAF mode, and shared resource counts
- [x] T022 [US1] Implement last-known-good preservation in `scripts/shared-service.sh` so a failure after a previously successful deployment leaves the working route intact and reports the failed stage in a redacted diagnostic
- [x] T023 [US1] Update `src/lib/azure-config.ts` so the shared storage account and table names resolve from the shared deployment configuration without any per-instance identifier

**Checkpoint**: One shared service deploys, redeploys idempotently, and serves one stable protected public address. This is the MVP.

---

## Phase 4: User Story 2 - Add Logical Instances Without Infrastructure Growth (Priority: P2)

**Goal**: Logical instance identities become Table Storage records with reserved, non-colliding data namespaces and no dedicated hosting, routing, or resource groups.

**Independent Test**: Add 10,000 distinct logical instance records to a test environment and confirm the public service stays available while the shared infrastructure resource count does not increase.

### Tests for User Story 2

- [ ] T024 [P] [US2] Create `tests/infrastructure/contracts/logical-instance-cli.sh` asserting the `create|show|list|retire` action surface, identifier normalization and 3-32 character validation, `--confirm` gating on `retire`, schema validation against `logical-instance-output.schema.json`, and the Constant-Resource Invariant that rejects any reference to `az deployment`, `az group create`, `az staticwebapp create`, `az afd endpoint`, or `instance-route.sh register`
- [ ] T025 [P] [US2] Create `tests/infrastructure/fixtures/generate-logical-instances.sh` emitting a deterministic JSON Lines stream of N unique logical instance reservations for use as scale-test input
- [ ] T026 [P] [US2] Create `tests/infrastructure/integration/constant-resource-scale.sh`, gated on `RUN_AZURE_INTEGRATION=1`, that applies 10,000 generated reservations in batches and asserts byte-identical before and after shared inventory documents (SC-001), plus duplicate and case-variant conflict handling (SC-009)

### Implementation for User Story 2

- [ ] T027 [US2] Add the `logicalinstances` table to `infra/shared/main.bicep` and expose a `logicalInstancesTableName` output defaulting to `logicalinstances`
- [ ] T028 [US2] Implement argument parsing, identity-based Table data-plane authentication, and the `create` action in `scripts/logical-instance.sh`, writing one `Reserved` record with `PartitionKey='instance'`, the normalized identifier as `RowKey`, an immutable `dataNamespace`, `createdAt`, `createdBy`, and `metadataVersion=1`
- [ ] T029 [US2] Implement conditional-insert conflict handling in the `create` action of `scripts/logical-instance.sh` so a `409 Conflict` re-reads the entity and returns `NoChange` for an equivalent request, `INSTANCE_CONFLICT` for incompatible immutable values, and `INSTANCE_RETIRED` for a retired identifier, never writing partial state before conflict detection
- [ ] T030 [P] [US2] Implement the `show` action in `scripts/logical-instance.sh` returning one record by normalized identifier and failing with `INSTANCE_NOT_FOUND` when absent
- [ ] T031 [US2] Implement the `list` action in `scripts/logical-instance.sh` with optional `--state` filtering, identifier-sorted output, and full continuation-token pagination so 10,000 records are never silently truncated
- [ ] T032 [US2] Implement the guarded `retire` action in `scripts/logical-instance.sh` performing a soft transition to `Retired`, setting `retiredAt`, keeping the namespace reserved, returning `NoChange` when repeated, and deleting no infrastructure or application data
- [ ] T033 [US2] Add the read-only `inventory` action to `scripts/shared-service.sh` reporting shared resource counts alongside the current logical instance count as the FR-018 constant-resource evidence

**Checkpoint**: Logical instances are pure data operations. US1 and US2 both work independently.

---

## Phase 5: User Story 3 - Preserve Shared Protection and Operations (Priority: P3)

**Goal**: Central protection, health visibility, access restrictions, diagnostics, alerting, and cost controls continue to work through the single shared route, including safe handling of reserved authentication paths.

**Independent Test**: Exercise healthy, abusive, and unavailable-origin requests through the shared address and confirm protection, controlled failure, diagnostics, alerts, and operator visibility all continue to function.

### Tests for User Story 3

- [ ] T034 [P] [US3] Create `tests/infrastructure/integration/shared-auth-cache-bypass.sh`, gated on `RUN_AZURE_INTEGRATION=1`, asserting that no `/.auth/*` response is served from cache and that no redirect leaves the shared Front Door host (SC-006)
- [ ] T035 [P] [US3] Create `tests/infrastructure/integration/shared-controlled-unavailability.sh`, gated on `RUN_AZURE_INTEGRATION=1`, asserting that an unhealthy shared origin returns the controlled maintenance response and never falls back to a legacy instance origin (FR-009)

### Implementation for User Story 3

- [ ] T036 [US3] Add the shared maintenance fallback origin at priority 2 to the origin group in `infra/platform/modules/shared-route.bicep`, reusing the existing maintenance origin hostname output from `infra/platform/main.bicep`
- [ ] T037 [US3] Add a dedicated `/.auth/*` route to `infra/platform/modules/shared-route.bicep` with caching and compression left unconfigured, `httpsRedirect` enabled, and the origin host header preserved as the Static Web Apps hostname
- [ ] T038 [US3] Add the shared endpoint to the existing shared Front Door security policy association in `infra/platform/modules/shared-route.bicep`, accepting the associated endpoint ID collection as a parameter exactly as `instance-route.bicep` does
- [ ] T039 [US3] Wire the shared endpoint into the diagnostic settings, origin health metric alert, and action group in `infra/platform/modules/monitoring.bicep` so a sustained shared failure alerts within five minutes (SC-007)
- [ ] T040 [US3] Apply the platform ownership, environment, cost centre, and `component` tags to every resource in `infra/shared/main.bicep` and `infra/platform/modules/shared-route.bicep` so the existing budget filter in `infra/platform/modules/cost-management.bicep` captures shared spend
- [ ] T041 [US3] Extend the `verify` action in `scripts/shared-service.sh` to assert HTTPS redirect, WAF association coverage of the shared endpoint, `/.auth/*` cache-bypass rule presence, correct origin host and host header, and that no legacy endpoint or origin is attached to the shared route
- [ ] T042 [US3] Add shared-origin CORS alignment for the shared public URL to `scripts/shared-service.sh`, reusing the idempotent duplicate-origin detection already proven in `scripts/cors-add-origin.sh`
- [ ] T043 [US3] Add the operator-facing shared service section to `docs/INFRASTRUCTURE.md` covering the shared address, health, alerts, diagnostics, and where to find constant-resource inventory evidence (SC-010)

**Checkpoint**: All protection and operational controls are preserved on the shared entry point.

---

## Phase 6: User Story 4 - Migrate Without Disrupting Existing Instances (Priority: P4)

**Goal**: The shared service is introduced additively and reversibly, legacy per-instance deployments remain untouched, and the delivery workflow stops creating per-instance hosting and routes.

**Independent Test**: Deploy the shared service alongside at least two legacy instances, confirm all addresses remain available, then roll back the shared deployment without changing either legacy instance.

### Tests for User Story 4

- [ ] T044 [P] [US4] Create `tests/infrastructure/contracts/shared-service-workflow.sh` statically asserting the trigger behaviour, ordering, environment-scoped concurrency with `cancel-in-progress: false`, `if: always()` artifact retention, and every Forbidden New-Path Behavior listed in [contracts/shared-service-workflow.md](contracts/shared-service-workflow.md)
- [ ] T045 [P] [US4] Create `tests/infrastructure/integration/legacy-coexistence.sh`, gated on `RUN_AZURE_INTEGRATION=1`, that snapshots two legacy instance routes and origins, deploys and rolls back the shared service, and asserts zero legacy resource or public response changes (SC-008)

### Implementation for User Story 4

- [ ] T046 [P] [US4] Create `scripts/pipeline/shared-service/initialize-shared-result.sh` writing an initial `shared-publication-result.json` with `stage=Preflight` and `status=Pending` before any Azure mutation
- [ ] T047 [P] [US4] Create `scripts/pipeline/shared-service/resolve-shared-configuration.sh` mapping the selected environment to its shared resource group, platform resource group, and Front Door profile with no instance identifier input
- [ ] T048 [US4] Create `scripts/pipeline/shared-service/deploy-shared-service.sh` invoking `scripts/shared-service.sh deploy` and retaining `shared-validation.json`, `shared-what-if.json`, `shared-deployment.json`, `shared-inventory-before.json`, and `shared-inventory-after.json`
- [ ] T049 [US4] Create `scripts/pipeline/shared-service/verify-shared-service.sh` invoking `scripts/shared-service.sh verify`, retaining `shared-route-verification.json`, and failing the job unless the status is `Succeeded`
- [ ] T050 [US4] Create `scripts/pipeline/shared-service/report-shared-service.sh` publishing the stable public URL to the job output and workflow summary and finalizing `shared-publication-result.json`
- [ ] T051 [US4] Refactor the push and manual-dispatch path in `.github/workflows/ci-cd.yml` to the shared ordering in [contracts/shared-service-workflow.md](contracts/shared-service-workflow.md), removing instance identifier derivation, `infra/main.bicep` invocation, and `instance-route.sh` invocation from the persistent path
- [ ] T052 [US4] Change the pull-request path in `.github/workflows/ci-cd.yml` to run build and offline contracts only, creating no resource group, Static Web App, storage account, Front Door endpoint, or route, and remove the per-PR resource deletion job
- [ ] T053 [US4] Set an environment-scoped concurrency group with `cancel-in-progress: false` on the shared deployment job in `.github/workflows/ci-cd.yml` and upload the `shared-service-<environment>-<run-id>` artifact under `if: always()`
- [ ] T054 [P] [US4] Add a superseded notice to the header comments of `scripts/instance-route.sh` and `infra/main.bicep` stating they are explicit legacy-only paths for existing instances, are not reachable from the shared persistent path, and are retired only by a separate approved feature
- [ ] T055 [US4] Document the coexistence, rollback, and later-retirement guidance for legacy instances in `docs/MIGRATION.md`, explicitly stating that shared rollback never runs legacy unregister or cleanup commands

**Checkpoint**: All four user stories are independently functional and legacy instances are provably unchanged.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T056 Apply forwarding-gateway origin restrictions in `scripts/shared-service.sh` only after route verification succeeds, so direct-origin access is denied while the shared public URL stays healthy
- [ ] T057 [P] Update `README.md` and `MULTI_INSTANCE_QUICK_REF.md` to describe the shared service model, the single public address per environment, and logical instance management
- [ ] T058 [P] Run `npm run infra:platform:shellcheck` extended to cover `scripts/shared-service.sh` and `scripts/logical-instance.sh`, and resolve every reported issue
- [ ] T059 Run `bash tests/infrastructure/run-all.sh` and confirm the full offline suite passes with no Azure credentials present
- [ ] T060 Execute the full [quickstart.md](quickstart.md) validation sequence against a disposable development environment and record the results

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational — no dependencies on other stories
- **User Story 2 (Phase 4)**: Depends on Foundational. T027 edits `infra/shared/main.bicep`, so it must follow T014/T015
- **User Story 3 (Phase 5)**: Depends on Foundational. T036-T038 and T041 extend files created in US1, so they must follow T016/T017 and T021
- **User Story 4 (Phase 6)**: Depends on Foundational. T048-T049 invoke the CLI actions built in US1
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### Story Independence

Each story remains independently testable once its own phase completes. US2, US3, and US4 extend files introduced in US1 rather than depending on each other, so after US1 lands they can proceed concurrently.

### Within Each User Story

- Tests are written first and MUST fail before implementation
- Bicep templates before the CLI actions that deploy them
- CLI actions before the workflow adapters that invoke them
- Core implementation before documentation

### Parallel Opportunities

- Setup: T002, T003, T004, T005 run in parallel
- Foundational: T008 and T009 run in parallel
- US1: T012 and T013 in parallel; T016 in parallel with the `infra/shared/main.bicep` work
- US2: T024, T025, T026 in parallel; T030 in parallel with T031/T032
- US3: T034 and T035 in parallel
- US4: T044 and T045 in parallel; T046, T047, and T054 in parallel
- Polish: T057 and T058 in parallel

---

## Parallel Example: User Story 2

```bash
# Launch all User Story 2 tests together:
Task: "Create tests/infrastructure/contracts/logical-instance-cli.sh"
Task: "Create tests/infrastructure/fixtures/generate-logical-instances.sh"
Task: "Create tests/infrastructure/integration/constant-resource-scale.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Deploy the shared service twice and confirm one stable public address with no duplicate resources
5. Demo the shared service before adding logical instances

### Incremental Delivery

1. Setup + Foundational → offline suite green against stubs
2. US1 → one shared service behind one protected address (MVP)
3. US2 → 10,000 logical instances with zero resource growth
4. US3 → protection, alerting, and authentication-path safety preserved
5. US4 → workflow cutover with legacy instances provably unchanged

### Deployment Safety Reminders

- `validate` and `what-if` are mandatory before any shared mutation
- Never use complete-mode deployment for the shared route
- Never delete or silently redirect legacy templates, scripts, or resources
- Every mutating command emits one schema-valid, redacted JSON envelope and returns nonzero on failure

---

## Notes

- [P] tasks touch different files and have no incomplete dependencies
- Logical instance operations are data-plane only and can never invoke ARM
- Commit after each task or logical group
- Stop at any checkpoint to validate a story independently
