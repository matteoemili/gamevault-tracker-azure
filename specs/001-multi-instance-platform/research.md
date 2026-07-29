# Research: Multi-Instance Entry Platform

## Global Entry Service

**Decision**: Use Azure Front Door rather than Azure Traffic Manager.

**Rationale**: Front Door is an application-layer global entry service with HTTPS endpoints, host-aware routing, WAF policies, health probes, access/WAF/health logs, redirects, and explicit origin host headers. Traffic Manager is DNS-only and primarily selects among endpoints for performance or failover; it cannot provide the central HTTP protection and request routing required here.

**Alternatives considered**: Traffic Manager was rejected because the instances are not replicas and must never fail over to each other. Application Gateway was rejected because it is regional and adds networking complexity without improving this global public-origin scenario. Direct Static Web App hostnames remain useful as origins and break-glass endpoints during rollout, but do not provide shared protection and operations.

## Entry Service Tier

**Decision**: Default to `Standard_AzureFrontDoor`, with `Premium_AzureFrontDoor` selectable through the `frontDoorSku` parameter on the shared platform template.

**Rationale**: Premium carries a fixed monthly base fee roughly ten times Standard's, and it dominates the entire shared-platform bill. The Premium-only capabilities are managed WAF rule sets, bot protection, and Private Link origins. Private Link is unusable here because Static Web Apps do not support it (see "Origin Security"), so the only real loss is the managed rule sets. The workload is a static SPA served from Static Web Apps with no server-side execution at the origin, so a rate-limit custom rule plus the staged origin lockdown covers the realistic threat model. Because the SKU is a single parameter and the routing and naming model is identical on both tiers, promoting to Premium is a one-line change if managed rules or 25 endpoints become necessary.

**Alternatives considered**: Staying on Premium was rejected as unjustifiable cost for a demonstration platform whose only consumed Premium feature is a managed rule set. Removing the WAF policy entirely was rejected because central protection is a stated requirement (FR-014) and Standard still supports custom and rate-limit rules. Dropping Front Door altogether was rejected because the shared entry point is the architecture being demonstrated.

## Domain-Free Addressing

**Decision**: Create one Front Door endpoint per instance and publish its Azure-provided deterministic hostname in the form `<endpoint>-<hash>.z01.azurefd.net`.

**Rationale**: The owner has no public domain. Every Front Door endpoint receives a unique Azure-managed HTTPS hostname without DNS records or certificate issuance. The endpoints-per-profile limit is SKU-dependent - 10 on Standard, 25 on Premium - so the default Standard profile carries 10 instances and the target scale of 25 is reached by switching SKUs, not by redesign. One endpoint per instance also keeps root-relative SPA assets and browser refreshes unambiguous.

**Alternatives considered**: A custom wildcard domain was rejected because no domain is owned. Path-based routing through one endpoint was rejected because the current SPA uses root-relative assets and would require application changes; it also weakens the one-address-per-instance boundary. Direct `azurestaticapps.net` addresses were rejected as the primary entry because they bypass shared WAF and observability.

## Instance Routing Boundary

**Decision**: Give every instance its own Front Door endpoint, route, origin group, and single application origin. Set the origin host header to the instance's `azurestaticapps.net` hostname and forward over HTTPS only.

**Rationale**: The resource graph makes the isolation invariant inspectable: an instance route can reference only its matching origin group, and that group contains no other instance. Static Web Apps require the origin host header to match their generated hostname. Deterministic child-resource names make updates idempotent.

**Alternatives considered**: A shared origin group plus rules-engine overrides was rejected because it increases coupling and makes accidental cross-instance routing possible. Multiple application origins in one group were rejected because Front Door can send traffic to unhealthy origins when all origins are unhealthy and because the applications hold different data.

## Controlled Unavailability

**Decision**: Use a shared static maintenance origin containing no tenant data as the only optional lower-priority origin in each instance group; initially keep it disabled until failure behavior is validated.

**Rationale**: Front Door health semantics can still attempt a sole unhealthy origin. A generic maintenance origin provides a controlled response without exposing another instance. It must be static, read-only, contain no instance information beyond a correlation ID, and be excluded from normal routing by priority.

**Alternatives considered**: Returning Front Door's native 503 is the simplest initial behavior and remains the first rollout stage. Another application instance is explicitly forbidden as fallback. A serverless maintenance API was rejected as unnecessary runtime complexity.

## Origin Security

**Decision**: Start with public Static Web App origins, then restrict each origin to the `AzureFrontDoor.Backend` service tag, the shared Front Door ID header, and its generated endpoint hostname after routing verification.

**Rationale**: Azure Static Web Apps do not support Front Door Private Link. Static Web Apps provide forwarding-gateway controls designed for Front Door, but applying them before endpoint verification risks locking out a working deployment. A staged rollout is reversible and supports local testing.

**Alternatives considered**: Front Door Premium Private Link is unsupported for Static Web Apps. Leaving origins permanently public would permit WAF bypass. Requiring a custom domain on each Static Web App is incompatible with the domain-free requirement.

## Infrastructure Lifecycle

**Decision**: Use Bicep for shared base resources and a separately invocable per-instance route module. Wrap deployments with non-interactive Bash commands that always run compile, validation, and what-if before mutation and emit JSON results.

**Rationale**: Bicep gives declarative, idempotent control-plane state. Separate deployment boundaries keep one instance lifecycle operation from replacing siblings. The same shell commands can be run locally and called unchanged from CI/CD, eliminating two automation paths.

**Alternatives considered**: Imperative `az afd` creation was rejected because partial failures and drift are harder to recover. One monolithic array of all instances was rejected because registering one instance would require a complete central inventory and could remove omitted siblings. Deployment Stacks are deferred until their deletion behavior is proven for child resources.

## Registration State

**Decision**: Treat tagged Azure Front Door child resources and deployment history as the source of truth; return a normalized registration record as command output rather than adding a registry database.

**Rationale**: The control plane already persists the endpoint, route, group, origin, tags, provisioning state, and deployment operations. A separate store creates consistency and recovery problems without a user-facing registry requirement.

**Alternatives considered**: App Configuration and Table Storage registries were rejected for v1. A generated local inventory file is allowed only as a disposable test fixture, never as authoritative state.

## Monitoring and Security

**Decision**: Centralize Front Door access, health probe, and WAF logs in Log Analytics with 90-day retention and a daily ingestion cap; deploy metric/log alerts and one shared WAF policy, beginning in detection mode and moving to prevention after validation.

**Rationale**: Central logs provide per-endpoint correlation and meet audit retention. Detection-first rollout prevents rules from unexpectedly blocking the application. Platform metrics are already retained and queryable for free in Azure Monitor, so they are not duplicated into the workspace; only log categories are forwarded, and a daily quota bounds worst-case ingestion spend. Health probes run on a four-minute interval because Front Door probes from every edge location, which multiplies both probe traffic and `FrontDoorHealthProbeLog` volume by the PoP count and again by the instance count.

**Alternatives considered**: Exporting `AllMetrics` to the workspace was rejected because nothing queries it there and it is billed per GB. A capacity alert on `RequestCount > 0` was rejected because it is permanently in an alert state, bills per time series, and carries no signal. One-minute alert evaluation with per-origin-group dimension splitting was rejected in favour of five-minute evaluation, which still satisfies SC-006 at lower cost and without flapping on single probe failures. Per-instance workspaces and WAF policies were rejected as costly and operationally fragmented. Premium managed WAF rule sets are covered under "Entry Service Tier".

## Authentication and CI/CD

**Decision**: Local commands use the signed-in Azure CLI identity. CI/CD later uses GitHub OpenID Connect workload identity federation with least-privilege roles scoped separately for shared-platform deployment and instance registration.

**Rationale**: This avoids long-lived client secrets and lets local and automated execution share commands while retaining distinct authorization boundaries.

**Alternatives considered**: The current serialized service-principal secret is retained only until migration. Account keys, deployment tokens in logs, and credentials in parameter files are prohibited.

## References

- [Azure Front Door overview](https://learn.microsoft.com/azure/frontdoor/front-door-overview)
- [Front Door endpoints](https://learn.microsoft.com/azure/frontdoor/how-to-configure-endpoints)
- [Front Door origins and host headers](https://learn.microsoft.com/azure/frontdoor/origin)
- [Front Door health probes](https://learn.microsoft.com/azure/frontdoor/health-probes)
- [Front Door service limits](https://learn.microsoft.com/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-front-door-standard-and-premium-service-limits)
- [Static Web Apps with Front Door](https://learn.microsoft.com/azure/static-web-apps/front-door-manual)
- [Traffic Manager overview](https://learn.microsoft.com/azure/traffic-manager/traffic-manager-overview)