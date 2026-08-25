# Implementation Plan: Shared Entry Scale

**Branch**: `exploration` | **Date**: 2026-08-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-shared-entry-scale/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Replace new per-instance Azure deployments with one shared GameVault Standard application and storage deployment behind one dedicated shared Azure Front Door Standard profile, endpoint, route, origin group, origin, and WAF association per environment. Reuse the existing platform patterns for WAF, monitoring, maintenance, RBAC, and cost controls without consuming capacity from legacy profiles; add a shared-route deployment boundary and a Table-backed logical-instance registry managed by a Bash 3.2-compatible CLI. Refactor the GitHub Actions workflow so pushes deploy and verify the shared service once, pull requests validate without creating persistent per-instance resources, and legacy instances remain untouched until a separate cleanup feature.

## Technical Context

**Language/Version**: Bicep supported by Azure CLI 0.39.26+; Bash 3.2+ for macOS compatibility; GitHub Actions YAML; TypeScript 5.7 and React 19/Vite 6 for the unchanged application bundle; JSON for machine-readable command results

**Primary Dependencies**: Azure CLI with Bicep, `jq`, `curl`, Azure Static Web Apps, Azure Front Door Standard, Azure Table Storage, Azure Monitor, Log Analytics, existing `azure/login` and `Azure/static-web-apps-deploy` actions

**Storage**: One shared StorageV2 account per environment with existing games/categories tables plus a new logical-instance registry table sharded across deterministic metadata partitions; logical-instance rows reserve normalized data namespaces but do not yet authorize end-user data access

**Testing**: Existing Bash contract runner and JSON schema validator, Bicep build/lint, Bash syntax/ShellCheck when available, static workflow contracts, generated 10,000-record fixtures, Azure validation/what-if, idempotent deployment tests, `curl` routing and controlled-unavailability probes, Azure resource inventory snapshots

**Target Platform**: Azure public cloud in one subscription; GitHub-hosted Ubuntu runners; local validation on macOS Bash 3.2 or Linux

**Project Type**: Existing React static web application with Bicep infrastructure, Bash lifecycle automation, Azure Table Storage, Azure Front Door, and GitHub Actions delivery

**Performance Goals**: 10,000 logical-instance reservations with zero shared-resource growth; 95% of representative public requests succeed or return controlled unavailability within 3 seconds; sustained shared failures alert within 5 minutes; one application publication updates all logical instances

**Constraints**: One provider-assigned shared `azurefd.net` address per environment; shared SWA uses Standard so forwarding-gateway restrictions can deny direct-origin bypass; no per-instance hostnames; no Entra, custom domain, redirect-host guarantee, or end-user authorization in this feature; no automatic legacy deletion or data migration; reserved `/.auth/*` paths bypass edge caching and path rewriting; first deployment uses an explicit unrestricted bootstrap upload followed by route verification and a second restricted upload; all scripts remain non-interactive, idempotent, fail-fast, secret-redacting, and JSON-emitting

**Scale/Scope**: One shared service and one shared Front Door route per environment; at least 10,000 logical instances in one subscription; existing legacy deployments coexist unchanged; no subscription or Front Door profile sharding

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- The constitution contains only unratified template placeholders, so it defines no enforceable project gates.
- **Constant-resource gate**: logical-instance lifecycle performs Table data-plane operations only and cannot invoke ARM deployment or route creation. **PASS**
- **Compatibility gate**: the shared endpoint uses a dedicated profile, so saturated legacy profiles cannot block deployment; existing per-instance resource groups, profiles, routes, scripts, and templates remain available for explicit legacy operations until a later retirement feature. **PASS**
- **Security gate**: shared management uses least privilege including storage data-plane roles; command outputs and artifacts exclude keys, SAS values, deployment tokens, and credentials; direct-origin hardening is applied by a verified second application upload during bootstrap. **PASS**
- **Reliability gate**: validate and what-if precede shared mutations; failed updates preserve the last known working shared route; authentication paths explicitly bypass shared caching and rewriting without claiming redirect-host behavior that needs a custom domain. **PASS**
- **Operability gate**: existing WAF, diagnostics, alerts, RBAC, tags, cost controls, and controlled maintenance behavior remain part of the shared deployment. **PASS**
- **Validation gate**: offline contracts prove constant topology and workflow ordering; opt-in Azure integration proves routing, idempotency, coexistence, and inventory invariants. **PASS**
- **Post-design re-check**: Phase 1 artifacts preserve every gate and require no exception. **PASS**

## Project Structure

### Documentation (this feature)

```text
specs/003-shared-entry-scale/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── logical-instance-cli.md
│   ├── shared-service-cli.md
│   └── shared-service-workflow.md
└── tasks.md
```

### Source Code (repository root)

```text
.github/workflows/
├── ci-cd.yml                              # Shared deployment; PR validation only
└── validate-infrastructure.yml            # Offline contracts

infra/
├── main.bicep                             # Legacy per-instance template, retained
├── shared/
│   ├── main.bicep                         # Standard SWA, storage, tables, data RBAC
│   └── main.{dev,staging,prod}.bicepparam
└── platform/
  ├── main.bicep                           # Existing legacy profile, retained
  ├── shared-entry.bicep                   # Dedicated shared profile composition
  └── modules/
    ├── front-door.bicep                   # Reused profile and WAF module
    ├── shared-route.bicep                  # One endpoint/group/origin/route/rule set
    ├── shared-monitoring.bicep             # Diagnostics/alerts to existing workspace
    ├── maintenance-origin.bicep
    ├── monitoring.bicep
    ├── rbac.bicep
    ├── cost-management.bicep
    └── instance-route.bicep                # Legacy only, retained

scripts/
├── shared-service.sh                       # validate/what-if/deploy/verify/status
├── logical-instance.sh                     # create/show/list/retire logical records
├── platform.sh                             # Existing platform deployment
├── instance-route.sh                       # Legacy only, retained
├── lib/azure-common.sh                     # Shared JSON/redaction helpers
└── pipeline/
  ├── shared-service/                       # Thin workflow adapters
  └── application/                          # Existing build/deploy helpers, adapted

src/
├── lib/azure-config.ts                     # Shared account configuration
├── lib/azure-storage.ts                    # Existing Table REST client
└── hooks/use-azure-table.ts                 # Existing shared application hooks

tests/infrastructure/
├── contracts/
│   ├── shared-service-cli.sh
│   ├── shared-service-output.schema.json
│   ├── logical-instance-cli.sh
│   ├── logical-instance-output.schema.json
│   ├── shared-service-workflow.sh
│   └── offline-validation.sh
├── fixtures/
│   └── generate-logical-instances.sh        # 10,000 deterministic reservations
└── integration/
  ├── shared-route-idempotency.sh
  ├── constant-resource-scale.sh
  ├── legacy-coexistence.sh
  ├── shared-controlled-unavailability.sh
  └── shared-auth-cache-bypass.sh
```

**Structure Decision**: Add an explicit `infra/shared/` boundary rather than repurposing `infra/main.bicep`, because the latter is the deployed contract for existing legacy instances. Add `infra/platform/shared-entry.bicep` rather than consuming an endpoint on the existing profile: a legacy Standard profile may already hold all ten endpoints, and coexistence forbids automatic retirement. The dedicated shared profile reuses established modules and the existing monitoring workspace, maintenance origin, RBAC patterns, and platform budget. Bash CLIs remain the single lifecycle implementations for local and CI/CD use, and logical-instance lifecycle is deliberately data-plane-only.

## Incremental Delivery

Each increment is independently runnable and must pass its exit criteria before the next begins.

1. **Offline contracts**: define shared-service, logical-instance, and workflow contracts; add output schemas and failing fixtures. Exit when the new contract suite runs without Azure and proves identifiers, envelopes, command surfaces, and forbidden per-instance workflow operations.
2. **Shared application infrastructure**: add `infra/shared/` with one stable Standard SWA, shared storage account, existing application tables, logical-instance registry table, and explicit `Storage Table Data Contributor` assignments for operator/deployment principals. Exit when Bicep builds, authorized identities can perform Table data operations, and two deployments converge to an empty what-if.
3. **Dedicated shared Front Door entry**: add one shared profile plus one deterministic endpoint, origin group, application origin, optional existing maintenance origin, route, WAF association, `/.auth/*` no-cache/no-rewrite rule set, and diagnostics to the existing workspace. Exit when one HTTPS public address reaches the shared SWA even if the legacy profile is at endpoint capacity, and redeployment creates no duplicates.
4. **Shared lifecycle CLI**: add `shared-service.sh` around compile, validate, what-if, deployment, origin registration, property verification, status, and sanitized JSON results. Exit when local and CI invocation produce schema-equivalent outcomes and a failed update preserves the working route.
5. **Logical-instance registry**: add `logical-instance.sh` using Azure identity-based Table access for create/show/list/retire and operator-only batched import. Map each normalized ID deterministically to one of 256 metadata partitions. Exit when normalized IDs are idempotent, conflicts are rejected atomically, authorized CI/operator identities work, and no command invokes ARM or changes shared inventory.
6. **Scale proof**: generate and batch-apply 10,000 deterministic logical-instance reservations in groups of at most 100 entities per metadata partition, snapshot shared resources before and after, and verify zero application, endpoint, route, origin, or resource-group growth. Exit when the test completes within the CI time budget, SC-001 passes, and identifier collision tests pass.
7. **Workflow cutover**: refactor `ci-cd.yml` so push/manual deployment targets the stable shared environment, Front Door verification gates success, and pull requests run build/offline validation without persistent per-instance resource creation. Exit when static contracts prove the old instance/publication path is unreachable for new shared deployments.
8. **Hardening and operations**: configure shared storage CORS for the shared public origin and implement two deployment modes. Bootstrap uploads once without forwarding restrictions, deploys/verifies the shared entry, generates the forwarding-gateway configuration, then rebuilds and uploads a second time with restrictions; steady-state deployments include the known restriction in their single upload. Preserve WAF/diagnostics/alerts/budget/RBAC and validate controlled unavailability plus `/.auth/*` cache bypass. Exit when direct-origin bypass is denied, routed access works, and sustained failures alert within five minutes.
9. **Legacy coexistence**: snapshot two existing instance routes and origins, deploy and roll back the shared service, and prove no legacy resource or address changes. Mark legacy scripts and templates as explicit-only in operator documentation; do not delete them. Exit when SC-008 passes and rollback guidance is complete.

## Deployment Safety

- `validate` and `what-if` are mandatory before shared-service or shared-route mutation.
- The shared application and dedicated shared profile/route use stable environment-scoped deployment names and `cancel-in-progress: false` concurrency.
- `infra/main.bicep`, `instance-route.bicep`, and `instance-route.sh` are not deleted or silently redirected; they remain explicit legacy paths.
- The shared route is deployed incrementally and never by complete-mode deployment.
- The shared SWA is Standard. On first deployment, its direct origin remains reachable for the bootstrap upload until the dedicated shared route and CORS configuration pass verification.
- Bootstrap hardening is a real second application build/upload containing generated forwarding-gateway configuration; steady-state uploads include the existing verified shared endpoint hostname and Front Door ID.
- Reserved `/.auth/*` requests bypass edge caching and path rewriting before any identity provider is added; redirect-host guarantees are deferred with custom domains and recorded in [research.md](research.md).
- Logical-instance create derives a deterministic metadata partition and normalized row key, then uses insert-or-read conflict handling; it cannot overwrite a different namespace reservation.
- Logical-instance commands authenticate with Azure identity-based data-plane authorization and never print storage credentials.
- Shared infrastructure grants `Storage Table Data Contributor` only to explicit operator/deployment principals at shared storage-account scope.
- Every mutating command writes one schema-valid, redacted JSON envelope and returns nonzero on failed or partial completion.
- Shared deployment artifacts retain validate, what-if, deployment, route verification, resource inventory, and health outcomes.
- Legacy cleanup, data migration, and Entra integration require separate approved features.
