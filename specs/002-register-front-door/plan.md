# Implementation Plan: Automatic Front Door Registration

**Branch**: `full-infra` | **Date**: 2026-07-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-register-front-door/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Complete the existing CI/CD publication path so every successfully deployed GameVault instance is registered and verified through the existing Azure Front Door lifecycle without manual work. Keep the implementation simple: orchestrate `instance-route.sh` and `cors-add-origin.sh` after application deployment, use explicit environment-specific platform inputs, perform one deterministic Azure control-plane property validation, retain structured results on every path, and surface the verified endpoint URL. Add only focused workflow/CORS contract tests; reuse the existing route schemas and Azure integration suite rather than introducing a service, action, or second registration implementation.

## Technical Context

**Language/Version**: GitHub Actions YAML; Bash 3.2+ for repository scripts and tests; Bicep supported by Azure CLI 0.39.26; JSON for machine-readable results

**Primary Dependencies**: Existing `azure/login`, `Azure/static-web-apps-deploy`, Azure CLI, `jq`, `curl`, `scripts/instance-route.sh`, `scripts/cors-add-origin.sh`, Azure Front Door, Azure Static Web Apps, Azure Table Storage

**Storage**: No new persistent store; Azure control-plane resources remain the route source of truth, Table Storage CORS remains instance-owned configuration, and sanitized JSON workflow artifacts retain operation results

**Testing**: Bash syntax checks, existing offline Bicep/CLI/schema suite, a new static workflow contract test, mocked CORS idempotency checks, and existing opt-in Azure routing, rejection, idempotency, origin-update, and isolation tests

**Target Platform**: GitHub-hosted Ubuntu runners deploying to Azure public cloud; local validation remains compatible with macOS Bash 3.2

**Project Type**: Existing web application repository with infrastructure-as-code, shell lifecycle automation, and GitHub Actions delivery orchestration

**Performance Goals**: A healthy instance becomes verified through its Front Door address within 10 minutes of application deployment in at least 95% of runs; independent instance builds remain parallel

**Constraints**: Reuse the existing route lifecycle and output schema; no new Azure resources; no registration before application upload; profile-level registration serialization while shared WAF association updates remain read-modify-write; fail closed on verification; preserve sanitized diagnostics; no secrets in artifacts; do not apply direct-origin hardening in this feature

**Scale/Scope**: One existing workflow, up to 25 registered instances per Front Door profile, dev/staging/prod mappings, one focused workflow contract, and small adjacent corrections to registration verification and CORS idempotency where required

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- The constitution contains only unratified template placeholders, so it defines no enforceable project gates.
- **Simplicity gate**: compose existing scripts and schemas; introduce no service, reusable action, or parallel registration implementation. **PASS**
- **Ordering gate**: registration begins only after infrastructure and application deployment succeed. **PASS**
- **Isolation gate**: one-to-one route ownership and sibling-route preservation remain delegated to the existing lifecycle and integration tests. **PASS**
- **Security gate**: use the current auditable identity for this increment, require explicit platform scope, mask secrets, and retain only sanitized outputs; OIDC migration is a separate hardening change. **PASS**
- **Validation gate**: fast offline workflow contracts cover orchestration; existing opt-in Azure tests cover live control-plane and routing behavior. **PASS**
- **Post-design re-check**: Phase 1 artifacts preserve every gate and require no exception. **PASS**

## Project Structure

### Documentation (this feature)

```text
specs/002-register-front-door/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
.github/workflows/
├── ci-cd.yml                         # Instance deployment and publication ordering
└── validate-infrastructure.yml       # Offline contract trigger coverage

infra/
└── main.bicep                        # Existing instance outputs and Table CORS owner

scripts/
├── instance-route.sh                 # Existing register/verify lifecycle owner
└── cors-add-origin.sh                # Existing idempotent published-origin alignment

tests/infrastructure/
├── contracts/
│   ├── front-door-registration-workflow.sh
│   ├── cors-add-origin.sh
│   ├── instance-route-cli.sh
│   └── offline-validation.sh
└── integration/
  ├── registration-idempotency.sh
  ├── registration-rejection.sh
  ├── origin-update-preservation.sh
  ├── routing-isolation.sh
  └── secure-routing.sh
```

**Structure Decision**: Keep the change inside the repository's current delivery and infrastructure boundaries. GitHub Actions owns ordering and reporting; `instance-route.sh` owns Front Door lifecycle behavior; `cors-add-origin.sh` owns the small post-registration CORS adjustment; existing Bicep remains the instance resource owner. New tests inspect those contracts instead of creating a workflow wrapper or application-layer component.
