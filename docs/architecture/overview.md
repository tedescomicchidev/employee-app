# Architecture overview (Phase 2, proposal)

Status: proposal for human review. Facts below come from Microsoft Learn (retrieved 2026-10-17); Foundry,
toolbox and Work IQ pages are marked preview, so re-check them before writing integration code.
Anything marked **VERIFY** was not confirmed in this session. Decisions live in `decisions/ADR-*.md`;
sign-in and token flows are in `auth-flows.md`.

## 1. Deviations from the Phase 2 request

1. **"OBO to https://ai.azure.com" is not how Foundry documents hosted agents.** `api/` gets its own *workload*
   token for `https://ai.azure.com/.default` (managed identity) and names the user with `x-ms-user-identity`.
   OBO is used only for the *downstream* token (agent tools), forwarded in an `x-client-*` header. See ADR-002.
2. **"Work IQ OAuth connection with per-user consent"** becomes: `api/` is the only Work IQ caller (human decision),
   `WorkIQAgent.Ask` needs one tenant-wide admin consent, and the per-user consent is the in-app opt-in (FR-BRF-001). See ADR-004.
3. **Role names** are `Communicator`, `Manager`, `Employee` (the request), replacing the Phase 1 proposals
   `Announcement.Publish` and `Vacation.Approve`. The CEO also holds `Manager` (R10). See ADR-003.
4. **Models**: EU Data Zone models are allowed (human decision). That is a recorded deviation from NFR-001. See ADR-001.

## 2. Components

```
iOS app (SwiftUI, MSAL)
   |  HTTPS, Entra access token (scope access_as_user)
   v
api/  FastAPI on Container Apps (Switzerland North)
   |-- REST /v1/*            app-facing, scope access_as_user
   |-- MCP  /mcp             agent-facing, scope Tools.Invoke
   |-- agent gateway         /v1/agent/{agent}/turns (SSE), calls Foundry
   |-- domain services       the only place business rules live
   |-- Work IQ client        OBO, after opt-in only
   v
Cosmos DB (serverless, single region)      Notification Hubs --> APNs
Key Vault (managed identity)               Log Analytics / App Insights

Foundry project (Switzerland North)
   |-- hosted agents: comms, vacation, briefing (Agent Framework, Python)
   |-- toolboxes: core-tools, briefing-tools  --> api/ MCP
```

Rules that shape everything: business rules live in `api/` only; agents act only through MCP tools; every write needs
a confirmation token minted by the app; Work IQ is user-delegated and never cached across users.

## 3. Region and residency (NFR-001, U-09)

Verified on Learn:

| Service | Switzerland North | Source |
|---|---|---|
| Foundry hosted agents | available (also Switzerland West) | agents/concepts/hosted-agents |
| Agent Service / Responses API | available | agents/concepts/limits-quotas-regions |
| Foundry guardrails (content harms, prompt shields, PII) | available; *Groundedness* not available | ai-services/content-safety/region-availability |
| Notification Hubs | available; zone redundancy forced on (extra cost) | reliability/reliability-notification-hubs |
| Availability zones | 3 zones | reliability/availability-zones-overview |
| Models, Standard regional (CH-resident) | `gpt-4.1`, `gpt-4.1-mini`, `gpt-4o` 2024-11-20 only | foundry-models/concepts/models-sold-directly-by-azure-region-availability |
| Models, Data Zone Standard (EU processing) | `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.5`, `gpt-5.6-*`, `gpt-6*` | same page |

**Runs outside Switzerland or outside Azure's compliance boundary:**

| What | Where | Why it matters |
|---|---|---|
| Inference for Data Zone models | EU data zone, not CH-resident | Only if a Data Zone model is deployed. Needs a privacy-statement update. |
| Work IQ (`workiq.svc.cloud.microsoft`) | Microsoft 365 service, outside the Azure compliance boundary (Learn warning) | Calendar content is processed there. Residency follows the tenant and Copilot billing config. |
| Entra ID, Microsoft 365 | tenant geography | Identity and calendar source. |
| APNs | Apple | Push payloads are content-free (ADR-008). |

**VERIFY (not confirmed this session):** Cosmos DB, Container Apps, Key Vault, Log Analytics and ACR in Switzerland North;
per-subscription model quota; model retirement dates for `gpt-4.1` family. Check with `azd provision --preview`
or Azure MCP quota before Phase 3 (spike S-4). Cosmos uses continuous backup and no geo-replication; an Azure Policy
blocks other regions.

## 4. API and MCP surface

One domain layer, two thin adapters (NFR-008 runs every scenario through both). Roles: P = Communicator, M = Manager, E = Employee.
Write = needs `confirmation_token` (FR-AUTH-006).

| MCP tool | REST route | Role | R/W | FR |
|---|---|---|---|---|
| `list_announcements` | `GET /v1/announcements` | E | R | ANN-003 |
| `get_announcement` | `GET /v1/announcements/{id}` | E (audience) | R | ANN-003 |
| `resolve_audience` | `POST /v1/audiences:resolve` | P | R | ANN-002 |
| `propose_announcement` | `POST /v1/proposals` (type=announcement) | P | R (stores proposal) | ANN-001 |
| `publish_announcement(token)` | `POST /v1/announcements` | P | W | ANN-001 |
| `get_balance` | `GET /v1/vacation/balance` | E | R | VAC-001 |
| `get_holidays` | `GET /v1/vacation/holidays` | E | R | VAC-006 |
| `list_vacation_requests` | `GET /v1/vacation/requests` | E | R | VAC-007 |
| `propose_vacation_request` | `POST /v1/proposals` (type=vacation) | E | R | VAC-002 |
| `create_vacation_request(token)` | `POST /v1/vacation/requests` | E | W | VAC-002 |
| `propose_cancel` / `cancel_vacation_request(token)` | `POST /v1/proposals`, `DELETE /v1/vacation/requests/{id}` | E | R / W | VAC-003 |
| `list_pending_approvals` | `GET /v1/vacation/approvals` | M | R | VAC-004 |
| `propose_decision` / `decide_vacation_request(token)` | `POST /v1/proposals`, `POST /v1/vacation/requests/{id}:decide` | M | R / W | VAC-004 |
| `get_team_coverage` | `GET /v1/vacation/coverage` | M | R | VAC-005 |
| `get_briefing_status` | `GET /v1/briefing/settings` | E | R | BRF-001 |
| `propose_briefing_optin` / `set_briefing_optin(token)` | `POST /v1/proposals`, `PUT /v1/briefing/settings` | E | R / W | BRF-001 |
| `get_my_week` | `GET /v1/briefing/week` | E + opt-in | R | BRF-002/004 |

REST-only (no tool, so agents cannot reach them): `POST /v1/confirmations` (mints tokens; rejects `Tools.Invoke` tokens),
`GET /v1/proposals/{id}` (the app renders the confirm card from this, not from model text), `POST /v1/events`,
`GET /v1/me`, device registration, `POST /v1/agent/{agent}/turns`.
`get_my_week` has no user parameter (FR-BRF-004). Tool results carry third-party text, so they are marked untrusted.

## 5. Agent topology (ADR-006)

Three hosted agents, chosen by the app from the feature entry point; no router model.

| Agent | Toolbox | Can reach |
|---|---|---|
| `comms` | `core-tools` | announcement tools |
| `vacation` | `core-tools` | vacation tools |
| `briefing` | `briefing-tools` | `get_my_week`, opt-in tools |

Conversation state: Responses calls use `store:false`; the app holds history on device and resends it through the
gateway (A-09, PRIV-004). A router agent is documented as the alternative.

## 6. Data model (ADR-007)

Cosmos DB serverless, one database. Partition key in brackets.

| Container | Holds |
|---|---|
| `employees` (/oid) | directory attributes from the seed file (ADR-010) |
| `user_settings` (/oid) | briefing opt-in, notification prefs |
| `vacation` (/oid) | request docs and a `balance_guard` doc (etag mutex, transactional batch) |
| `vacation_params` (/oid) | entitlement, carry-over, cap |
| `config` (/type) | holidays by canton, blackouts |
| `announcements` (/id) | announcement, audience rule, recipient-count snapshot |
| `announcement_inbox` (/oid) | one doc per recipient: read state, mirrored status |
| `confirmations` (/oid, TTL) | proposals and single-use tokens |
| `participants` (/participant_id) | oid to participant mapping, separate RBAC, deletable |
| `events` (/participant_id, TTL configurable) | experiment events and server records |

Audit logs go to Log Analytics, content-free, with a correlation id that is not the `task_run_id`.

## 7. Push (ADR-008)

Notification Hubs in Switzerland North, APNs token auth. Payloads are generic and carry no audience hint.
Installations are tagged with an HMAC of the oid. Opt-in only. Monday 07:00 briefing stays a local notification.
If push slips, polling on app open still meets every Must (A-15).

## 8. Experiment capture (ADR-009)

The task-flow wrapper in `Packages/Core` emits the events in `docs/experiment/metrics.md`. The app batches them to
`POST /v1/events` (strict schema, unknown fields rejected). The gateway and middleware write `api_call`, `agent_run`,
`outcome_check` and `safety_counter`, joined by `task_run_id`. Withdrawal deletes the participant partition and mapping.

## 9. Spikes and open items

| ID | Question | Blocks |
|---|---|---|
| S-1 | Is OBO to a separate resource app needed (self-OBO likely unsupported)? | agent tool auth |
| S-2 | Does Work IQ (MCP or REST) return structured calendar events for a window under the delegated scope? Which billing applies: Copilot Credits or a per-user M365 Copilot licence (Learn pages disagree)? | FR-BRF-* (U-03) |
| S-3 | Can the confirmation token be passed to a hosted agent as a structured input and on to the tool? | FR-AUTH-006 in AGENT mode |
| S-4 | Cosmos, Container Apps, Key Vault, quota and model retirement in Switzerland North | Phase 3 |
| O-1 | How is `outcome_valid` verified for read-only tasks (T-VAC-BAL, T-ANN-READ, T-BRF-VIEW)? | Phase 9 protocol |

## 10. Traceability

| Requirement | Where |
|---|---|
| FR-AUTH-001, 005 | auth-flows.md flow 1; ADR-002 |
| FR-AUTH-002 | ADR-003, section 4 |
| FR-AUTH-003 | ADR-002 (OBO, `x-ms-user-identity`), ADR-005 |
| FR-AUTH-004 | ADR-004, auth-flows.md flow 4 |
| FR-AUTH-006 | ADR-005, auth-flows.md flow 3 |
| NFR-001 | ADR-001, section 3 |
| NFR-008 | ADR-005 |
| NFR-011 | ADR-002 (gateway rate limits; values set in Phase 3) |
| NFR-012 | ADR-007, ADR-009 (content-free logs) |
| PRIV-006, 007 | ADR-007, ADR-009 |
| EXP-001..007 | ADR-009 |

> **Update (phase 6, comms):** the shared `core-tools` toolbox was not built. A toolbox `UserEntraToken` connection cannot carry the user (needs a user token for Foundry; `api/` holds only its own identity), so agents call `api/` `/mcp` directly with the forwarded OBO token and are limited with `allowed_tools`. See ADR-002 status update.
