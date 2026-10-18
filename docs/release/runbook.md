# Runbook

## Phase 3: provision dev (human runs, agent never does)

Prerequisites: `az login`, `azd auth login`, Contributor + User Access Administrator on the subscription
(the template creates role assignments for the api managed identity).

```
azd env new dev
azd env set AZURE_LOCATION switzerlandnorth
# optional: azd env set AZURE_MODEL_CAPACITY 10   (if gpt-4.1 quota is lower)
azd provision --preview        # check S-4: services + gpt-4.1 Standard available in switzerlandnorth
azd up                         # provisions rg-employee-dev, builds api in ACR, deploys /health
azd env get-values             # expect AZURE_API_URL, AZURE_AI_PROJECT_ENDPOINT, AZURE_RESOURCE_GROUP
curl -s "$(azd env get-value AZURE_API_URL)/health"
```

Expected: `{"status":"ok"}`;
`AZURE_AI_PROJECT_ENDPOINT=https://aif-<token>.services.ai.azure.com/api/projects/employee-dev`.
If it fails, put the (non-secret) log in `/Users/Shared/handoff/`.

### Likely failures
- Quota for `gpt-4.1` Standard in switzerlandnorth: lower `AZURE_MODEL_CAPACITY` or set `AZURE_MODEL_NAME/VERSION`.
- A resource type unavailable in switzerlandnorth (spike S-4): report which one; do not change the region silently.
- Re-running after `azd down`: Key Vault purge protection keeps the name; the name is derived from the env, so use a new env name or purge manually.
- Role assignment errors: the deploying user needs User Access Administrator.

### Still human-only after `azd up`
Custom role `Foundry Agent User Identity Impersonation` + Foundry Agent Consumer for the api identity,
Entra app registrations, federated credential on the api identity, APNs key upload to the Notification Hub,
toolbox connections, Cosmos `participants` role.

### Known trade-off
The api container listens on port 80 so the placeholder image used at provision time passes ingress checks.
Revisit (non-root, 8000) once the placeholder is gone.
