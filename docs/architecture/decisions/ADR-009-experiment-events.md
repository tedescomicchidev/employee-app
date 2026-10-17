# ADR-009: Experiment event capture

Status: proposed. Requirements: EXP-001..007, PRIV-006, PRIV-007, NFR-006, NFR-012. Schema: `docs/experiment/metrics.md`.

## Context
Events must be pseudonymous and content-free, joined across device and server by `task_run_id`, deletable per
participant, and give a cost per task.

## Decision
- **Device:** a shared task-flow wrapper in `Packages/Core` emits `task_started` and exactly one of
  `task_completed` / `task_abandoned`, plus `task_error`, `confirm_*`, `agent_turn`, `satisfaction`,
  `session_comparison`, `withdrawal`. Events are batched and sent to `POST /v1/events`.
- **Ingest:** strict schema validation, unknown fields rejected. `participant_id` is a random uuid the app gets once from
  `GET /v1/me/participant`. Ingest checks the id belongs to the caller via `participants`, then writes the event
  **without the oid**. Request headers carry `X-Task-Run-Id` so the server can join its own records.
- **Server records** (same `events` container): `api_call` (middleware), `agent_run` (gateway: model id, input/output
  tokens from the Responses `usage`, tool-call count, latency, cost from a configurable price table),
  `outcome_check` (write handlers record whether the persisted state satisfies the Outcome AC),
  `safety_counter` (counts only).
- **Separation:** audit logs use a request correlation id that is not the `task_run_id` and carry no participant id, so
  logs cannot be joined to participants.
- **Withdrawal (EXP-007):** `withdrawal` triggers a job that deletes the participant's `events` partition and mapping row.
- **Mode assignment (EXP-004):** counterbalanced order is computed from the participant id; a forced-mode setting is compiled out of Release.
- Never recorded: announcement text, calendar content, prompts or replies, rejection reasons, names, emails, tokens.

## Consequences
- Offline event queueing holds only content-free events, so it is allowed on device; it clears at withdrawal and sign-out.
- `outcome_valid` for read-only tasks (T-VAC-BAL, T-ANN-READ, T-BRF-VIEW) has no server persisted outcome. Open item O-1 for the Phase 9 protocol.
- Cost per task for CLASSIC is infra apportioned by API call count (method in `analysis.md`); the price table needs a human-supplied rate.
- Retention is a config value, unset (U-05).

## Alternatives
- Application Insights custom events: easy, but deletion by participant is awkward and Log Analytics is shared with audit logs.
- Third-party analytics SDK: excluded by NFR-003.

## Sources
- docs/experiment/metrics.md, docs/experiment/hypotheses.md
- learn.microsoft.com/azure/cosmos-db/data-residency
