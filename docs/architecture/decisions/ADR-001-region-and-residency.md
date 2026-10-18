# ADR-001: Region and residency

Status: proposed. Requirements: NFR-001, NFR-014, U-09.

## Context
The brief asks for Azure Switzerland North where available. Foundry hosted agents, Agent Service, guardrails and
Notification Hubs are available there. Model availability is the constraint: only `gpt-4.1`, `gpt-4.1-mini` and
`gpt-4o` 2024-11-20 are Standard regional (CH-resident) in Switzerland North. Newer models (`gpt-5.4`,
`gpt-5.4-mini`, `gpt-5.5`, `gpt-5.6-*`, `gpt-6*`) are deployable from Switzerland North only as Data Zone Standard
(processed in the EU data zone) or Global.

## Decision
- Deploy every resource in `switzerlandnorth` unless this ADR lists an exception.
- Default agent model: a Standard regional `gpt-4.1` family deployment (CH-resident).
- The human allowed EU Data Zone models. A Data Zone model may be used per agent when evals show the CH-resident
  model is not good enough. Each such use is recorded in the table below before it ships, and the privacy
  statement and `docs/privacy/data-inventory.yml` (processor region for `agent-conversations`) are updated in the same PR.
- Cosmos DB uses continuous backup, no geo-replication, and an Azure Policy that denies other regions.
- IaC check (NFR-001): a Bicep/CI check fails if a resource location is not `switzerlandnorth` and not listed here.

| Exception | Where | Data in flight | Status |
|---|---|---|---|
| Data Zone model inference | EU data zone | prompts and tool results for that agent | allowed by the human, none selected yet |
| Work IQ | Microsoft 365 service, outside the Azure compliance boundary | the user's calendar request and response | required by goal 1 |
| Entra ID, Microsoft 365 | tenant geography | identity, calendar | not a hosting choice |
| APNs | Apple | content-free push payload | see ADR-008 |

## Consequences
- The `gpt-4.1` family is older; retirement dates are not verified. Spike S-4 checks them and the subscription quota.
- Notification Hubs in Switzerland North has forced zone redundancy (extra cost).
- Learn's Groundedness guardrail is not available in Switzerland North; the design does not depend on it.
- Not verified this session: Cosmos DB, Container Apps, Key Vault, Log Analytics, ACR in Switzerland North (spike S-4).
- Foundry projects created before 2026-06-25 need a publicly reachable ACR for the agent image; create a new project.
- Dev exception (2026-10-18): the dev subscription has no Standard (regional) gpt-4.x quota in Switzerland North (limit 0). Dev deploys `gpt-4o` 2024-11-20 as GlobalStandard, so prompts may be processed outside Switzerland/the EU. Demo data only. Revert to Standard once quota is granted (`AZURE_MODEL_SKU`).

## Alternatives
- Switzerland West: also lists hosted agents, but Notification Hubs/Cosmos AZ behaviour differs and nothing here requires it.
- Sweden Central for the Foundry project: more models, but moves all agent data out of Switzerland. Rejected.

## Sources
- learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents (region availability)
- learn.microsoft.com/azure/foundry/agents/concepts/limits-quotas-regions
- learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure-region-availability
- learn.microsoft.com/azure/reliability/reliability-notification-hubs
- learn.microsoft.com/azure/cosmos-db/data-residency
- learn.microsoft.com/azure/foundry/agents/how-to/tools/work-iq (data governance section)
