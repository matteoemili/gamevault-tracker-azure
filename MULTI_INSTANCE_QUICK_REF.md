# Shared Entry Quick Reference

New GameVault instances are logical records in the shared service. Each
environment has one shared Static Web App, one shared storage account, and one
protected Front Door public address.

## 🚀 Deploy or Validate the Shared Service

```bash
# Offline validation; no Azure mutation
./scripts/shared-service.sh validate --environment dev --local-only

# Preview Azure changes
./scripts/shared-service.sh what-if \
  --environment dev \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group rg-gamevault-shared-dev \
  --platform-resource-group rg-gamevault-platform-dev \
  --front-door-profile gvt-afd-dev

# Deploy the one shared service for an environment
./scripts/shared-service.sh deploy \
  --environment dev \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group rg-gamevault-shared-dev \
  --platform-resource-group rg-gamevault-platform-dev \
  --front-door-profile gvt-afd-dev \
  --location westeurope \
  --confirm
```

## 🌐 Find the Single Public Address

```bash
./scripts/shared-service.sh status \
  --environment dev \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group rg-gamevault-shared-dev \
  --platform-resource-group rg-gamevault-platform-dev \
  --front-door-profile gvt-afd-dev | jq .
```

Use the `sharedService.publicUrl` value. New logical instances do not receive
dedicated public hostnames.

## 🧾 Manage Logical Instances

```bash
./scripts/logical-instance.sh <create|list|show|retire> [options]
```

The current usage block lists:

- `--environment <dev|staging|prod>`
- `--subscription-id <uuid>`
- `--storage-account-name <name>`
- `--table-name <name>` (default: `logicalinstances`)
- `--logical-instance-id <id>` (create/show/retire)
- `--display-name <name>` (create)
- `--state <Reserved|Retired>` (list only)
- `--confirm` (retire only)
- `--non-interactive` (informational)

Logical instance actions reserve Table Storage records only. They must not
deploy Static Web Apps, storage accounts, resource groups, Front Door endpoints,
or routes.

## 📊 Constant-Resource Inventory

```bash
./scripts/shared-service.sh inventory \
  --environment dev \
  --subscription-id "$AZURE_SUBSCRIPTION_ID" \
  --shared-resource-group rg-gamevault-shared-dev \
  --platform-resource-group rg-gamevault-platform-dev \
  --front-door-profile gvt-afd-dev | jq .
```

Inventory evidence should keep shared resource counts constant as logical
instance count grows.

## 🧓 Legacy Per-Instance Path

The former model created one resource group, storage account, Static Web App,
and Front Door route per instance. That path is superseded for new work and is
retained only for existing legacy instances.

### Inspect Existing Legacy Instances

```bash
az group list \
  --query "[?starts_with(name, 'rg-gamevault-')].{Name:name, InstanceId:tags.instanceId, Env:tags.environment}" \
  --output table
```

### Legacy Resource Naming

For legacy instance ID `abc12345`:

| Resource | Name |
|----------|------|
| Resource Group | `rg-gamevault-abc12345` |
| Storage Account | `stgamevaultabc12345` |
| Static Web App | `swa-gamevault-prod-abc12345` |
| Legacy SWA URL | `https://swa-gamevault-prod-abc12345.azurestaticapps.net` |

Do not delete, unregister, or reroute legacy instances as part of shared-service
deployment or rollback. Run legacy cleanup only under a separate approved
migration/retirement task.

## 📚 Full Documentation

- **Quick Start**: [README.md](README.md)
- **Legacy Complete Guide**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Feature Validation**: [specs/003-shared-entry-scale/quickstart.md](specs/003-shared-entry-scale/quickstart.md)
