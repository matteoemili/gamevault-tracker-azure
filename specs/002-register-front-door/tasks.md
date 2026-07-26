# Tasks: Automatic Front Door Registration

**Input**: Design documents from `/specs/002-register-front-door/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/registration-workflow.md](contracts/registration-workflow.md), [quickstart.md](quickstart.md)

**Tests**: The specification requires measurable publication, idempotency, isolation, and diagnostic outcomes. Add focused offline contract tests first; reuse the existing opt-in Azure integration suite rather than duplicate route lifecycle coverage.

**Organization**: Tasks are grouped by user story so each story is independently implementable and testable after the shared workflow contract foundation is complete.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it touches a different file and has no unfinished task dependency.
- **[Story]**: Maps a task to a user story in [spec.md](spec.md).
- Every task includes its exact repository path.

## Phase 1: Setup

**Purpose**: Establish the focused validation entry points and ensure workflow changes trigger infrastructure validation.

- [ ] T001 Add `.github/workflows/ci-cd.yml` to the pull-request and push path filters in `.github/workflows/validate-infrastructure.yml` so delivery orchestration changes run the infrastructure contract suite.
- [ ] T002 [P] Create the read-only workflow contract test scaffold in `tests/infrastructure/contracts/front-door-registration-workflow.sh` using Bash 3.2-compatible helpers and a repository-root path resolver.

---

## Phase 2: Foundational

**Purpose**: Make the existing offline runner execute the new workflow and CORS contracts before user-story implementation begins.

**Critical**: Complete this phase before claiming any automated publication behavior.

- [ ] T003 Add the workflow contract and CORS contract test entry points to `tests/infrastructure/contracts/offline-validation.sh` while preserving the existing no-Azure-mutation behavior.
- [ ] T004 Create a mocked Azure CLI CORS idempotency contract test in `tests/infrastructure/contracts/cors-add-origin.sh` that covers both `allowedOrigins` and legacy `AllowedOrigins` response shapes.

**Checkpoint**: `bash tests/infrastructure/run-all.sh` has a single fast offline entry point for all new wiring checks.

---

## Phase 3: User Story 1 - Publish Every New Instance Automatically (Priority: P1) MVP

**Goal**: After an application upload succeeds, publish the instance through the existing Front Door lifecycle, align browser storage access, verify it with bounded propagation polling, and report the verified URL.

**Independent Test**: Run `bash tests/infrastructure/run-all.sh`, then execute one approved workflow deployment of a healthy new instance and verify its summary, result artifact, and Front Door URL before running `secure-routing.sh` against that URL.

### Tests for User Story 1

- [ ] T005 [US1] Implement ordering and input-mapping assertions in `tests/infrastructure/contracts/front-door-registration-workflow.sh` for application upload, explicit platform inputs, registration, CORS, and verification.
- [ ] T006 [US1] Extend `tests/infrastructure/contracts/front-door-registration-workflow.sh` to require profile-scoped non-cancelling publication concurrency, only `Succeeded` verification acceptance, published URL output/summary, and `if: always()` retention of all required result files.
- [ ] T007 [US1] Extend `tests/infrastructure/contracts/cors-add-origin.sh` with duplicate-origin and wildcard-origin cases that must fail before the CORS helper correction.

### Implementation for User Story 1

- [ ] T008 [US1] Update `scripts/cors-add-origin.sh` to recognize Azure CLI CORS response casing reliably and skip existing or wildcard Front Door origins without adding duplicate rules.
- [ ] T009 [US1] Update `.github/workflows/ci-cd.yml` infrastructure outputs and build-job inputs to pass the deployed Static Web App default hostname and explicit environment-specific platform resource-group/profile configuration into publication.
- [ ] T010 [US1] Refactor `.github/workflows/ci-cd.yml` so post-upload route registration, CORS alignment, verification, and artifact retention run in a profile-scoped serialized publication job while infrastructure and application deployments remain independently parallel.
- [ ] T011 [US1] Implement `publication-result.json`, bounded verification polling, final Front Door URL job output, and workflow summary reporting in `.github/workflows/ci-cd.yml` according to `specs/002-register-front-door/contracts/registration-workflow.md`.
- [ ] T012 [US1] Update `scripts/instance-route.sh` verification to compare the registered origin host header against the deployed Static Web App hostname supplied by CI and retain the existing structured output envelope.

**Checkpoint**: A healthy new instance deployment produces exactly one verified HTTPS Front Door URL, exposes it in the workflow result, aligns Table Storage CORS, and passes secure-routing validation.

---

## Phase 4: User Story 2 - Redeploy Without Duplicate Routes (Priority: P2)

**Goal**: Preserve a stable published address through repeat deployment, safely update only the target instance origin, and protect shared Front Door mutations from concurrent workflows.

**Independent Test**: With approved test instances, run the existing idempotency and origin-update scenarios and verify a sibling route snapshot remains unchanged after target updates.

### Tests for User Story 2

- [ ] T013 [P] [US2] Extend `tests/infrastructure/integration/origin-update-preservation.sh` to snapshot normalized sibling endpoint, route, origin-group, origin, and WAF association properties before and after target registration/update.
- [ ] T014 [P] [US2] Extend `tests/infrastructure/integration/registration-idempotency.sh` to assert unchanged published hostname and a single tagged endpoint after repeated registration through the workflow inputs.

### Implementation for User Story 2

- [ ] T015 [US2] Add existing-endpoint ownership-tag validation for instance resource group and Static Web App name in the registration path of `scripts/instance-route.sh` before allowing an update.
- [ ] T016 [US2] Correct the route-update failure message and result handling in `scripts/instance-route.sh` so it does not claim transactional preservation after a failed incremental Azure deployment, while preserving actionable sanitized diagnostics.
- [ ] T017 [US2] Validate profile-level publication serialization and redeploy behavior through `.github/workflows/ci-cd.yml` and the extended Azure integration scenarios without changing the Front Door resource model.

**Checkpoint**: Repeated deployment retains one hostname and one route, a valid origin change updates only its owner, and rejected/conflicting changes leave a sibling instance unchanged.

---

## Phase 5: User Story 3 - Diagnose Registration Failures (Priority: P3)

**Goal**: Make preflight, registration, CORS, and verification failures visibly incomplete deployments with sanitized, retrievable, instance-specific diagnostics.

**Independent Test**: Force one preflight failure and one verification failure in an approved environment, then confirm the final workflow status is failed and the expected publication/route result files are retained without secrets.

### Tests for User Story 3

- [ ] T018 [US3] Extend `tests/infrastructure/contracts/front-door-registration-workflow.sh` to assert preflight manifest initialization, per-stage result updates, partial-result artifact retention, and rejection of `Degraded`, `Failed`, malformed, or empty verification output.
- [ ] T019 [US3] Extend `tests/infrastructure/contracts/instance-route-cli.sh` with expected-origin mismatch and ownership-tag mismatch failure cases that validate redacted schema-valid output.

### Implementation for User Story 3

- [ ] T020 [US3] Finalize failure branches in `.github/workflows/ci-cd.yml` so missing platform configuration, registration errors, CORS errors, and verification timeout all update `publication-result.json`, fail the deployment, and retain available artifacts without credentials.
- [ ] T021 [US3] Update `specs/001-multi-instance-platform/contracts/instance-route-cli.md` with the supplied expected-origin verification behavior, ownership validation, statuses, and non-transactional failure semantics.

**Checkpoint**: Every attempted publication has an instance-specific sanitized result; no failure is reported as a successful published deployment; operators can distinguish the failed stage and safely retry.

---

## Phase 6: Polish and Cross-Cutting Validation

**Purpose**: Document the operational contract and run the complete validation path without expanding the feature scope.

- [ ] T022 [P] Update `DEPLOYMENT.md` and `docs/INFRASTRUCTURE.md` with environment-specific platform configuration, publication ordering, verified URL reporting, artifact locations, current identity permissions, and the intentionally deferred direct-origin hardening.
- [ ] T023 Run the offline and approved live validation commands from `specs/002-register-front-door/quickstart.md`, record results in `specs/002-register-front-door/quickstart.md`, and resolve only failures caused by this feature.

---

## Dependencies and Execution Order

### Phase Dependencies

- **Phase 1 - Setup**: Starts immediately.
- **Phase 2 - Foundational**: Depends on T001 and T002; blocks all story completion because it makes the new tests runnable.
- **Phase 3 - US1**: Depends on Phase 2. T005-T007 are written before T008-T012.
- **Phase 4 - US2**: Depends on the US1 publication implementation because it validates the deployed route lifecycle and workflow concurrency.
- **Phase 5 - US3**: Depends on US1 result-file structure and may proceed alongside late US2 live-test work.
- **Phase 6 - Polish**: Depends on all desired story phases.

### User Story Dependencies

- **US1 (P1)**: Requires only the foundational offline test harness. It is the MVP.
- **US2 (P2)**: Builds on US1's publication path to prove repeatability and sibling-route preservation.
- **US3 (P3)**: Builds on US1's publication result manifest to make all publication failures diagnosable.

### Parallel Opportunities

- T001 and T002 can run in parallel.
- T013 and T014 can run in parallel because they modify different integration tests.
- T022 can begin after publication behavior stabilizes and can proceed in parallel with final live validation.

## Parallel Example: User Story 1

```text
Task: "Implement workflow ordering/input contract tests in tests/infrastructure/contracts/front-door-registration-workflow.sh"
Task: "Implement CORS casing/idempotency tests in tests/infrastructure/contracts/cors-add-origin.sh"
```

After both tests are in place, implement the helper correction in `scripts/cors-add-origin.sh` before the ordered workflow changes in `.github/workflows/ci-cd.yml`.

## Parallel Example: User Story 2

```text
Task: "Snapshot sibling route and WAF state in tests/infrastructure/integration/origin-update-preservation.sh"
Task: "Extend repeated registration assertions in tests/infrastructure/integration/registration-idempotency.sh"
```

## Implementation Strategy

### MVP First

1. Complete T001-T004 to make workflow and CORS behavior testable offline.
2. Complete T005-T012 to publish and verify a new instance.
3. Run the US1 checkpoint and one approved deployment before adding redeploy or diagnostics refinements.

### Incremental Delivery

1. **US1**: Reliable automatic post-upload publication with a reported URL.
2. **US2**: Safe repeated deployment and target-only route updates.
3. **US3**: Complete sanitized failure evidence and retry guidance.
4. **Polish**: Documentation and full quickstart validation.

## Notes

- All implementation remains in the existing workflow, lifecycle scripts, Bicep-owned instance configuration, and infrastructure test directories.
- Do not create a new Azure service, composite GitHub Action, route schema, or direct-origin hardening rollout for this feature.
- Keep all shell changes Bash 3.2 compatible and preserve the existing JSON-only stdout contract for lifecycle scripts.