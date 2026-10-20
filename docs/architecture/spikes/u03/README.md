# Spike U-03: Work IQ calendar surface

Spike code, not production. `probe.py` checks whether Work IQ returns a complete, structured set of calendar
events for a time window under the delegated `WorkIQAgent.Ask` scope. Outcome and decision: ADR-011.

The agent cannot run this (no identity, no consent, no licences). Everything below is human-only.

## Human steps
1. Tenant: confirm Work IQ is enabled and its service principal exists
   (learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/enable-work-iq).
2. Billing: confirm Copilot Credits usage-based billing is set up and the test user is in a spending policy that
   includes Work IQ API. Note whether the test user also needs a Microsoft 365 Copilot licence (ADR-004 flags a conflict).
3. Test client: a public-client app registration (device code flow enabled, no secret) with delegated
   `api://workiq.svc.cloud.microsoft/WorkIQAgent.Ask` and Graph `Calendars.Read`. Grant admin consent for
   `WorkIQAgent.Ask`. If Work IQ MCP policy is configured, confirm the calendar path is allowed.
4. Seed 5-8 events in one week for a test user: normal, all-day, recurring series, one cancelled, one declined,
   one on another time zone. Write down the expected count (do not paste titles anywhere).
5. Run, as the test user, in your own account:
   `python3 -m pip install msal && python3 -I docs/architecture/spikes/u03/probe.py --tenant <tenant-id> --client-id <client-id>`
   It prints two device-code prompts (Work IQ, then Graph) to stderr. No token or event content is printed or stored.
6. Re-run once with a user who has no consent/licence to record the failure codes (maps to FR-BRF-005).
7. Result file: `/Users/Shared/handoff/u03-result.json` (statuses, tool names, key names, counts, salted hashes).
   Tell the agent when it is there.

## What the result decides
| Result | ADR-011 decision |
|---|---|
| `fetch` returns JSON for the window, `vs_graph` missing=0/extra=0, no paging gap | Keep ADR-004 |
| Only `ask` works or `fetch` is incomplete/bounded | Graph Calendar delegated for the event set, or relax FR-BRF-002; human decides |
| 401/403/licence/policy errors | Record blockers; Graph fallback until resolved |
