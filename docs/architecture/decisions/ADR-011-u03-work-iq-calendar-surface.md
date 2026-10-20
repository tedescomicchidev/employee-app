# ADR-011: Work IQ calendar surface (U-03 spike)

Status: proposed, **live result pending**. Resolves open question U-03; follows up ADR-004 (spike S-2).
Requirements: FR-BRF-001..005, FR-AUTH-004, PRIV-003.

## Context
ADR-004 assumes `api/` can read a user's calendar window from Work IQ as structured events, so the briefing equals the
returned set (FR-BRF-002). U-03 asks which surface a custom app can use, which scopes it needs, whether the tenant
`m365cpi55218196.onmicrosoft.com` is enabled and licensed, and whether a time window works.

## Findings from documentation (retrieved 2026-10-20)
- Delegated scope `api://workiq.svc.cloud.microsoft/WorkIQAgent.Ask`; Application permission: none; AdminConsentRequired: Yes.
  It covers read and write on resources scoped to the signed-in user.
- Surfaces: A2A, local MCP, remote MCP (`https://workiq.svc.cloud.microsoft/mcp`), REST (conversational).
- Remote MCP tools are path-based (`fetch`, `create_entity`, `do_action`, `call_function`, `ask`, `retrieve`); the
  entity model lists `fetch /me/events` as "read calendar events". Tool schemas come from `tools/list`.
- Mutations are blocked by default by tenant policy; the default policy also bounds collection reads.
- Prerequisites: tenant enabled for Work IQ; usage-based billing (Copilot Credits) with the user in a spending policy
  for Work IQ API.
- Not documented: time-window parameters for `fetch /me/events`, page size limits, handling of recurring/cancelled
  events. **Unverified until the probe runs.**

## Spike
`docs/architecture/spikes/u03/probe.py`, run by the human (the agent has no identity, consent or licences).
Compares `fetch` variants and `ask` against Graph `calendarView` for the same user and window.

## Result
Pending: `/Users/Shared/handoff/u03-result.json` has not been provided. Licence/enablement in the tenant: unknown.

## Decision
Pending the result. Default stays as ADR-004 (no change) only if `fetch` returns the complete windowed set.
Otherwise the proposal is Graph Calendar delegated (`Calendars.Read`) for the event set, with Work IQ kept for
synthesis, which changes the PoC claim and needs the human's decision.

## Consequences
FR-BRF-002 stays blocked until the result is in. No production code depends on this ADR yet.

## Sources
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/permissions
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/mcp/overview
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/mcp/entity-model
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/mcp/policy-governance-mcp
- learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/mcp/retrieve
