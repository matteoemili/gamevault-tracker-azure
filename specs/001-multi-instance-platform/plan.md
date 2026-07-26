# Implementation Plan: Multi-Instance Entry Platform

**Branch**: `full-infra` | **Date**: 2026-07-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-multi-instance-platform/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Build an independently deployed shared Azure entry platform that assigns each isolated GameVault instance its own Azure-provided HTTPS hostname. Azure Front Door Premium provides one endpoint, route, origin group, and origin per instance; each origin group contains only that instance plus an optional shared maintenance origin, so no request can reach another instance. Bicep modules and Bash wrappers expose the same `validate`, `what-if`, `deploy`, `register`, `verify`, and `unregister` operations for interactive local use and later CI/CD composition.

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Bicep supported by the current Azure CLI; Bash 3.2+ for macOS compatibility; JSON for machine-readable command results

**Primary Dependencies**: Azure CLI with Bicep, `jq`, Azure Front Door Premium, Azure Monitor, Log Analytics, Storage static website for the maintenance origin, existing Azure Static Web Apps

**Storage**: Existing per-instance Table Storage remains unchanged; one shared StorageV2 account hosts a static maintenance response; Azure control-plane resources are the registration source of truth

**Testing**: Bicep build/lint, ARM validation and what-if, ShellCheck when available, contract checks over JSON output, Azure resource assertions, `curl` routing/isolation probes, repeat deployment tests

**Target Platform**: Azure public cloud; local runners on macOS or Linux; GitHub-hosted Linux runners after local validation

**Project Type**: Infrastructure as code with command-line lifecycle automation integrated into an existing web application repository

**Performance Goals**: Register a healthy instance in under 10 minutes; 95% of representative requests complete or return a controlled unavailable response within 3 seconds; health alerts fire within 5 minutes

**Constraints**: No owned domain; no cross-instance failover; one Azure-provided endpoint hostname per instance; Front Door Premium limit of 25 endpoints per profile exactly meets v1 capacity; Azure Static Web Apps do not support Front Door Private Link; scripts must be non-interactive, idempotent, fail-fast, and emit masked machine-readable outputs

**Scale/Scope**: One shared platform resource group and Front Door Premium profile; up to 25 registered instances per profile; each instance retains its own resource group, Static Web App, and storage account

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- The constitution file contains only unratified template placeholders, so it defines no enforceable project gates.
- Baseline gate: all infrastructure is declarative, repeatable, and independently validated before deployment. **PASS**
- Security gate: no credentials are stored in templates, parameters, logs, or command output; local use relies on Azure CLI identity and CI/CD later uses workload identity federation. **PASS**
- Isolation gate: every endpoint route references an origin group that contains no other application instance. **PASS**
- Lifecycle gate: registration, update, verification, and deregistration have explicit contracts and idempotency behavior. **PASS**
- Operability gate: diagnostics, retention, alerts, tags, and failure-preserving behavior are designed before pipeline integration. **PASS**
- Post-design re-check: Phase 1 artifacts preserve all gates; no exception is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-multi-instance-platform/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
infra/
├── main.bicep                         # Existing isolated instance resources
├── modules/
│   └── static-web-app.bicep           # Existing instance application module
└── platform/
  ├── main.bicep                     # Shared resource group deployment entry
  ├── main.dev.bicepparam
  ├── main.prod.bicepparam
  └── modules/
    ├── front-door.bicep            # Profile, WAF, endpoint-independent base
    ├── monitoring.bicep            # Logs, diagnostics, alerts, retention
    ├── maintenance-origin.bicep     # Non-tenant unavailable response
    └── instance-route.bicep         # One endpoint/group/origin/route per instance

scripts/
├── platform.sh                        # validate, what-if, deploy, outputs
└── instance-route.sh                  # register, verify, unregister, status

tests/
└── infrastructure/
  ├── contracts/                     # JSON schema and naming assertions
  └── integration/                   # Azure routing, isolation, idempotency checks

.github/workflows/
└── ci-cd.yml                          # Later composes the already-proven commands
```

**Structure Decision**: Keep instance resources under the existing `infra/` entry point and add a sibling `infra/platform/` deployment boundary. Shared base resources and per-instance route resources are separate Bicep modules so lifecycle operations cannot accidentally redeploy or delete unrelated instances. Thin Bash wrappers provide stable command and JSON contracts shared by local and CI/CD execution.

## Incremental Delivery

Each increment is independently runnable and must pass its exit criteria before the next begins.

1. **Offline foundation**: split reusable instance resources only where required; add platform module skeletons, parameter validation, naming functions, and local command dispatch. Exit when all Bicep builds and shell contract tests pass without Azure mutation.
2. **Azure preflight**: implement login/subscription checks, provider checks, deployment validation, and what-if for an empty shared platform. Exit when validation succeeds and what-if shows only the expected shared resource group contents.
3. **Shared entry platform**: deploy Front Door Premium, WAF in detection mode, maintenance origin, Log Analytics, diagnostics, and outputs. Exit when redeployment is idempotent and the default endpoint/maintenance response is observable.
4. **Single-instance lifecycle**: register one existing Static Web App as one endpoint, one route, one origin group, and one origin; emit its Azure-provided hostname. Exit when HTTPS routing works, the origin host header is correct, and a second registration is a no-op.
5. **Isolation and scale proof**: register two distinguishable instances, simulate one failure, run repeatability tests, and generate a 25-instance what-if fixture. Exit when no request crosses instance boundaries and profile limits are enforced before mutation.
6. **Origin hardening**: add `staticwebapp.config.json` forwarding-gateway restrictions using the shared Front Door ID and each generated endpoint hostname; keep rollout reversible until every instance is verified through Front Door. Exit when direct-origin access is denied and routed access remains healthy.
7. **Operations and protection**: move WAF to prevention after log review, enable alerts and 90-day retention, add budget/capacity checks, and verify the shared maintenance behavior. Exit when synthetic failures produce actionable alerts within target time.
8. **Deregistration and recovery**: implement guarded unregister, orphan detection, and last-known-working preservation on failed updates. Exit when removing one instance leaves all others unchanged and interrupted operations can be safely retried.
9. **CI/CD composition**: call the exact validated scripts from the existing workflow using workload identity federation, serialized per-instance concurrency, artifacts for JSON results, and environment approvals for shared-platform changes. Exit when manual dispatch and pipeline runs produce equivalent plans and outcomes.

## Deployment Safety

- `validate` and `what-if` are mandatory before every mutating command.
- Shared platform deployment and instance route lifecycle use different deployment names and modules.
- Registration validates instance ID, resource group, subscription, origin HTTPS reachability, and endpoint-name availability before mutation.
- Complete-mode deployments are prohibited; unregister deletes only resources whose deterministic names and tags match the requested instance.
- Every mutating command writes a redacted JSON result and returns nonzero on partial or failed completion.
- Endpoint creation is serialized per instance ID to prevent concurrent route conflicts.
- The direct Static Web App origin remains available until Front Door verification passes; origin restriction is a later, reversible increment.
- Front Door endpoint capacity is checked before registration. The 25th endpoint is allowed; the 26th is rejected with guidance to create a second profile in a future scaling feature.
