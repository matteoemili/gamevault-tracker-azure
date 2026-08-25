# Research: Shared Entry Scale

## Scaling Unit

**Decision**: Treat a logical instance as a data-plane record and namespace reservation, not as an Azure resource deployment.

**Rationale**: The current limit comes from allocating one Static Web App and one Front Door endpoint per instance. Both are bounded control-plane resources. A shared application and route make infrastructure count independent of logical-instance count, while Table rows can represent at least the required 10,000 logical instances without new resource groups, applications, or routes.

**Alternatives considered**: Front Door profile sharding was rejected because it does not raise the hard ten-Free-SWA subscription limit and multiplies WAF, monitoring, RBAC, and cost-management resources. Subscription-per-instance was rejected as an unsustainable primary tenancy model. Per-instance Standard SWAs were rejected because they merely raise the default cap and preserve per-instance deployment work.

## Public Address Model

**Decision**: Publish one Azure-provided hostname from a dedicated shared Front Door Standard profile per environment and do not provide per-instance hostnames in this feature.

**Rationale**: One endpoint removes Front Door endpoint capacity from the logical-instance scale equation and requires no owned domain. A dedicated shared profile avoids depending on spare capacity in the legacy profile, which may already contain all ten Standard endpoints. Existing WAF, logging, health probes, alerts, and stable public-entry patterns are reused while legacy profiles remain untouched.

**Alternatives considered**: Adding the endpoint to the legacy profile was rejected because a saturated profile would block migration or force legacy deletion. Direct Static Web App access was rejected because it drops the WAF and shared operational controls built in feature 001. A wildcard custom domain remains a compatible future enhancement but is not required for scale.

## Shared Application Boundary

**Decision**: Add `infra/shared/main.bicep` and keep legacy `infra/main.bicep` unchanged.

**Rationale**: Existing deployments were created through `infra/main.bicep`; changing that contract risks accidental mutation during legacy redeployment. A new shared boundary provides stable environment-scoped names and makes coexistence and rollback inspectable.

**Alternatives considered**: Converting `infra/main.bicep` in place was rejected because its instance identifier, resource naming, outputs, and workflows are consumed by existing deployments. Moving the shared SWA into the Front Door platform template was rejected because application and entry-platform lifecycles have different permissions and rollout order.

## Shared Route Boundary

**Decision**: Add `infra/platform/shared-entry.bicep` that creates a dedicated shared profile through the existing Front Door module, then invokes a separately deployable `shared-route.bicep` with one endpoint, one route, one origin group, one SWA origin, the existing optional maintenance origin, and a dedicated WAF association.

**Rationale**: The SWA hostname is not available until shared application deployment completes. A separate shared entry composition and route deployment preserve the proven origin-first, route-second, verify-before-hardening sequence, leave legacy profiles and child resources untouched, and remain deployable when a legacy profile is full.

**Alternatives considered**: Reusing `instance-route.bicep` with a special instance ID was rejected because it preserves misleading per-instance capacity, tags, lifecycle, and output semantics. Embedding the route in the platform base was rejected because it couples platform creation to an application origin that may not exist yet.

## Authentication-Path Compatibility

**Decision**: Attach a shared rule set that bypasses Front Door response caching and path rewriting for `/.auth/*` before any identity feature ships. Do not claim redirect-host preservation without a custom domain.

**Rationale**: Static Web Apps reserves `/.auth/*` for authentication. Explicit no-cache/no-rewrite behavior avoids session responses being shared or paths being altered at the edge and leaves the entry topology ready for later identity configuration.

**Alternatives considered**: Deferring all auth compatibility was rejected because retrofitting routing behavior during identity rollout creates avoidable migration risk. Disabling all edge caching was rejected because only reserved dynamic paths require bypass; static asset caching remains useful.

**Known constraint**: The origin keeps its host header set to the Static Web Apps hostname, because the Azure-provided `*.azurefd.net` address cannot be bound as a Static Web Apps custom domain and rewriting the host header would break origin host matching and certificate name checks. The entry point can guarantee cache bypass and no path rewrite, but cannot guarantee that future sign-in redirects return to the shared public address. The later identity feature must decide and validate custom-domain binding before enabling sign-in.

## Logical-Instance Registry

**Decision**: Add one `logicalinstances` table to the shared storage account. Store normalized logical-instance ID as the row key and derive a two-hex-character metadata partition from the normalized ID, yielding 256 deterministic partitions. Store an immutable reserved data namespace and lifecycle state.

**Rationale**: This is the smallest persistent source of truth that supports uniqueness, idempotent creation, inventory, retirement, and a 10,000-record scale proof without creating infrastructure. Deterministic partitioning avoids concentrating all lifecycle traffic in one hot partition while preserving atomic uniqueness because every normalized ID always maps to the same partition and row key.

**Alternatives considered**: Azure App Configuration was rejected because the project already depends on Table Storage and needs listable structured records. Git-tracked JSON was rejected because concurrent runtime creation and atomic uniqueness are required. Resource tags were rejected because they reintroduce one resource per logical instance.

## Logical-Instance Management Interface

**Decision**: Provide `scripts/logical-instance.sh` with `create`, `show`, `list`, guarded `retire`, and operator-only `bulk-create` actions, Bash 3.2 compatibility, identity-based Table access, and the existing JSON envelope convention. Grant explicit `Storage Table Data Contributor` assignments to operator and deployment principals on the shared storage account.

**Rationale**: Existing operator and CI workflows are shell-based, use Azure CLI identity, and validate normalized JSON contracts. A dedicated CLI prevents workflow YAML from becoming a second registry implementation and allows direct proof that no logical-instance action invokes ARM. Batched import groups at most 100 entities per metadata partition and makes the required 10,000-record live proof practical inside CI.

**Alternatives considered**: Ten thousand one-process-per-row Azure CLI calls were rejected because they can exceed CI time budgets. An application API was rejected because end-user registration and authentication are out of scope. Direct `az storage entity` commands in workflow YAML were rejected because validation, normalization, conflict handling, redaction, and result contracts would be duplicated.

## Direct-Origin Hardening

**Decision**: Provision the shared Static Web App on Standard and apply forwarding-gateway restrictions through generated application configuration. Bootstrap uses two uploads: first unrestricted, then a restricted rebuild/upload after the shared Front Door ID and hostname are verified. Later deployments use one restricted upload.

**Rationale**: Standard supports the required forwarding restrictions. The configuration is part of the deployed application bundle, so it cannot be applied as an independent post-deployment control-plane step. Explicitly modeling the second bootstrap upload closes the ordering gap and makes direct-origin denial testable.

**Alternatives considered**: Keeping the shared SWA on Free was rejected because it cannot meet the direct-origin denial exit criterion. Writing a local forwarding JSON artifact without redeploying the application was rejected because it does not enforce anything. Applying restrictions before route verification was rejected because a bad route could lock out the only working origin.

## Identifier and Namespace Rules

**Decision**: Normalize input to lowercase and accept 3-32 characters matching `^[a-z0-9][a-z0-9-]*[a-z0-9]$`; reserve a data namespace equal to the normalized logical-instance ID in this feature.

**Rationale**: The rule is human-readable, deterministic, case-collision-safe, and compatible with future partition-key usage. A minimum of three characters avoids ambiguous tiny identifiers while 32 characters supports meaningful names without expanding every downstream contract.

**Alternatives considered**: Reusing the legacy 1-8 character instance ID was rejected because that length was driven by Azure resource-name limits that no longer apply. Random UUID-only identifiers were rejected because operator usability and deterministic idempotency are explicit requirements. Hashing the namespace was deferred because no secret or cross-tenant exposure requirement exists yet.

## Delivery Workflow

**Decision**: Push and manual dispatch deploy one stable shared service per selected environment; pull requests run build and infrastructure contracts without creating persistent per-instance infrastructure. Bootstrap deployments perform two application uploads; steady-state deployments perform one.

**Rationale**: Persistent PR resource groups and SWAs recreate the same bounded resource-growth problem. The scale feature must make the default workflow incapable of allocating an application or endpoint per branch, run, or logical instance.

**Alternatives considered**: Static Web Apps preview environments were not selected as the required path because their count is separately bounded and preview UX is not part of this feature. Keeping the current PR-per-instance workflow was rejected because it violates constant-resource requirements.

## Legacy Coexistence

**Decision**: Retain legacy templates, scripts, routes, and instances unchanged, mark them explicit-only, and defer deletion and data migration.

**Rationale**: The feature introduces a new default without making irreversible changes. Side-by-side inventory snapshots and live probes provide measurable evidence that shared deployment and rollback do not alter existing users.

**Alternatives considered**: Immediate deletion was rejected by scope and rollback requirements. Automatically repointing legacy addresses to the shared application was rejected because data migration and end-user authorization are not yet defined.

## References

- [Azure Architecture Center: Multitenancy and tenancy models](https://learn.microsoft.com/azure/architecture/guide/multitenant/considerations/tenancy-models)
- [Azure Architecture Center: Azure Front Door in multitenant solutions](https://learn.microsoft.com/azure/architecture/guide/multitenant/service/front-door)
- [Azure Front Door service limits](https://learn.microsoft.com/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-front-door-standard-and-premium-service-limits)
- [Azure Static Web Apps with Azure Front Door](https://learn.microsoft.com/azure/static-web-apps/front-door-manual)
- [Azure Table Storage scalability targets](https://learn.microsoft.com/azure/storage/tables/scalability-targets)
