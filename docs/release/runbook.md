# Runbook

## Phase 3: provision dev (human runs, agent never does)

Prerequisites: `az login`, `azd auth login`, Contributor + User Access Administrator on the subscription
(the template creates role assignments for the api managed identity).

```
azd env new dev
azd env set AZURE_LOCATION switzerlandnorth
azd env set AZURE_MODEL_NAME gpt-4o   # defaults already gpt-4o 2024-11-20 GlobalStandard, capacity 30
azd provision --preview        # check S-4: services + gpt-4.1 Standard available in switzerlandnorth
azd up                         # provisions rg-employee-dev, builds api locally (needs Docker or Podman), deploys /health
azd env get-values             # expect AZURE_API_URL, AZURE_AI_PROJECT_ENDPOINT, AZURE_RESOURCE_GROUP
curl -s "$(azd env get-value AZURE_API_URL)/health"
```

Expected: `{"status":"ok"}`;
`AZURE_AI_PROJECT_ENDPOINT=https://aif-<token>.services.ai.azure.com/api/projects/employee-dev`.
If it fails, put the (non-secret) log in `/Users/Shared/handoff/`.

### Likely failures
- Quota: a limit of 0 cannot be fixed by lowering capacity. List quota with `az cognitiveservices usage list --location switzerlandnorth`, then set `AZURE_MODEL_NAME/VERSION/SKU`. Dev uses `gpt-4o` GlobalStandard (see ADR-001 dev exception).
- `TasksOperationsNotAllowed`: the subscription cannot use ACR Tasks, so azd builds the image locally. Install Docker Desktop, Colima or Podman, then run `azd deploy`.
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
