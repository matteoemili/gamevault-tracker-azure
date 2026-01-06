# Multi-Instance Quick Reference

## 🚀 Deploy New Instance

```bash
# Automatic (push to main)
git push origin main

# Manual (GitHub Actions UI)
Actions → Run workflow → Leave instance_id empty → Run
```

## ♻️ Redeploy to Existing Instance

```bash
# GitHub Actions UI
Actions → Run workflow → Enter instance_id → Run
```

## 🔍 Find Instance ID

```bash
# From deployment logs
Check GitHub Actions logs for "Instance ID: abc12345"

# From Azure Portal
Resource Groups → Tags → instanceId

# From Azure CLI
az group show --name rg-gamevault-{id} --query tags.instanceId -o tsv
```

## 📋 List All Instances

```bash
# Azure CLI
az group list \
  --query "[?starts_with(name, 'rg-gamevault-')].{Name:name, InstanceId:tags.instanceId, Env:tags.environment}" \
  --output table
```

## 🧹 Delete Instance

```bash
# Azure CLI
az group delete --name "rg-gamevault-{instanceId}" --yes

# Azure Portal
Resource Groups → Select group → Delete resource group
```

## 🏷️ Resource Naming

For instance ID `abc12345`:

| Resource | Name |
|----------|------|
| Resource Group | `rg-gamevault-abc12345` |
| Storage Account | `stgamevaultabc12345` |
| Static Web App | `swa-gamevault-prod-abc12345` |
| Web URL | `https://swa-gamevault-prod-abc12345.azurestaticapps.net` |

## 🎯 Common Use Cases

### Create Dev Instance
```bash
Actions → Run workflow
Environment: dev
Instance ID: (empty)
```

### Update Production
```bash
Actions → Run workflow
Environment: prod
Instance ID: prod1234 (your production instance)
```

### Create Feature Test
```bash
Actions → Run workflow
Environment: dev
Instance ID: (empty - generates new)
```

## 💰 Cost Per Instance

- Storage Account: ~$0.01-0.10/month
- Static Web App: Free tier
- Table Storage: ~$0.05/10k transactions
- **Total**: < $1/month typical usage

## 📊 Monitor Instance

```bash
# Get instance details
INSTANCE_ID="abc12345"
az staticwebapp show \
  --name "swa-gamevault-prod-$INSTANCE_ID" \
  --resource-group "rg-gamevault-$INSTANCE_ID" \
  --query "{Name:name, Status:sku.name, URL:defaultHostname}"

# Check storage
az storage account show \
  --name "stgamevault$INSTANCE_ID" \
  --resource-group "rg-gamevault-$INSTANCE_ID"
```

## 🐛 Troubleshooting

### Can't find instance ID
```bash
# List all instances
az group list --query "[?starts_with(name, 'rg-gamevault-')]"
```

### Deployment fails
- Check GitHub Actions logs
- Verify Azure credentials
- Ensure resource group doesn't exist (if new deployment)

### CORS issues
```bash
# Already configured automatically, but to verify:
INSTANCE_ID="abc12345"
az storage cors list \
  --account-name "stgamevault$INSTANCE_ID" \
  --services t
```

## 📚 Full Documentation

- **Quick Start**: [README.md](README.md)
- **Complete Guide**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Technical Details**: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)

---

**Need Help?**
- Check deployment logs in GitHub Actions
- Review DEPLOYMENT.md for detailed instructions
- Inspect resource tags in Azure Portal
