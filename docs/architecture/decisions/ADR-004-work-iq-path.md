# ADR-004: Work IQ path

Status: accepted for implementation (phase 8); spike S-2 is **still unverified against the tenant**. Requirements: FR-BRF-001..005, FR-AUTH-004, PRIV-003, NFR-008.

## Context
Goal 1 is to prove Work IQ works from a custom iOS app. Foundry offers a Work IQ tool (`work_iq_preview`) over A2A
with an `oauth2` connection and a per-user consent link. Work IQ chat returns synthesized text. FR-BRF-002 needs the
briefing to equal the set of events Work IQ returns, with none omitted or invented, in both modes. Work IQ also has a
remote MCP surface (`https://workiq.svc.cloud.microsoft/mcp`, path-based tools such as `fetch /me/...`) and REST.
`WorkIQAgent.Ask` is a delegated permission with **AdminConsentRequired: Yes**; app-only is not supported.
Learn warns data may be processed outside the Azure compliance boundary.

## Decision (confirmed by the human)
- `api/` is the only Work IQ caller. It calls Work IQ via OBO with `WorkIQAgent.Ask`, for both CLASSIC (REST) and
  AGENT (`get_my_week` MCP tool). No Foundry Work IQ connection or toolbox tool in v1.
- Gate: no Work IQ call unless `user_settings.briefing_optin` is true (FR-BRF-001).
- Output is held in memory for the request, never cached across users, never logged, not persisted (PRIV-003).
- Consent model: one tenant-wide admin consent for `employee-api` (human, once) plus the in-app opt-in as the
  per-user consent record. There is no per-user Entra consent screen on this path.
- Grouping, conflicts and free blocks are computed deterministically in `api/` from the returned events.
- Failure states map to FR-BRF-005 codes (`WORKIQ_UNAVAILABLE`, consent missing, no licence, partial, empty).

## Consequences
- **Spike S-2 blocks FR-BRF-*:** confirm that a structured calendar surface (Work IQ MCP `fetch` on a calendar path, or
  REST) returns events for a time window under the delegated scope. If only the chat/A2A surface returns calendar data,
  set-exactness cannot be guaranteed. Then ask the human: either relax FR-BRF-002 to "as returned" or use Graph Calendar delegated.
- Billing is unresolved. The Foundry page says Work IQ API uses usage-based billing (Copilot Credits); the Foundry
  quickstart says each calling user needs a Microsoft 365 Copilot licence. Human decides after S-2.
- Work IQ MCP is preview; the scope list I found names only `WorkIQAgent.Ask`.
- Parity (NFR-008) is easy: one code path. The cost is not exercising Foundry's per-user consent flow (goal 1 is still proven from the iOS app via `api/`).

## Alternatives
- Foundry Work IQ connection for the briefing agent only: matches the request literally, but CLASSIC still needs an
  `api/` path, so there are two integrations and set-exactness cannot be tested the same way. Rejected.
- Both behind a flag: possible later as an experiment arm. Needs one more human-only connection with a client secret.

## Sources
- learn.microsoft.com/azure/foundry/agents/how-to/tools/work-iq
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/permissions
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/mcp/overview
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/mcp/quickstart/foundry

## Implementation notes (phase 8)
- Built as decided: `api/app/briefing/` (`MsalWorkIQClient`, OBO only), no Foundry Work IQ connection, no toolbox, no `ASWebAuthenticationSession`. A request to use a toolbox and `WORKIQ_CONNECTION_NAME` was set aside in favour of this ADR.
- Consent: the iOS opt-in is the per-user consent record; a missing administrator consent is `CONSENT_REQUIRED` and the app tells the user to ask their administrator (no in-app consent flow exists on this path).
- Calendar read: one `call_function /me/calendarView` per Zurich day (S-2 to confirm the surface and the response shape).
