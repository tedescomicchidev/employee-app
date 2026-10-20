# Architecture decisions

Phase 2 proposals, status `proposed` until the human accepts them. There was no ADR template in the repo, so
each ADR uses: Status, Context, Decision, Consequences, Alternatives, Sources (Learn URLs, retrieved 2026-10-17).

| ADR | Decision |
|---|---|
| [001](ADR-001-region-and-residency.md) | Switzerland North, with listed exceptions; EU Data Zone models allowed |
| [002](ADR-002-identity-and-token-chain.md) | MSAL, `access_as_user`, OBO for downstream, workload token for Foundry |
| [003](ADR-003-app-roles.md) | Communicator, Manager, Employee |
| [004](ADR-004-work-iq-path.md) | `api/` is the only Work IQ caller |
| [005](ADR-005-api-mcp-surface-and-confirmation.md) | One domain layer, REST and MCP adapters, native confirmation |
| [006](ADR-006-agent-topology.md) | Three hosted agents, two toolboxes, no router |
| [007](ADR-007-cosmos-data-model.md) | Cosmos containers and partition keys |
| [008](ADR-008-push-notifications.md) | Notification Hubs, content-free payloads |
| [009](ADR-009-experiment-events.md) | Event capture and pseudonymity |
| [010](ADR-010-directory-attributes.md) | Seed file instead of app-only Graph sync |
| [011](ADR-011-u03-work-iq-calendar-surface.md) | Work IQ calendar surface (U-03 spike; live result pending) |
