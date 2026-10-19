# Metrics and events

Requirements: EXP-001..EXP-007, NFR-005, NFR-006, PRIV-007. Hypotheses: `hypotheses.md`.
All events are pseudonymous and content-free. Timestamps are UTC ISO-8601; business dates Europe/Zurich.

## Common fields (every event)
| Field | Type | Notes |
|---|---|---|
| `event` | string | name below |
| `participant_id` | uuid | random, per participant; mapping stored separately and deletable (EXP-007) |
| `session_id` | uuid | app session |
| `task_run_id` | uuid | one attempt of one task; joins device and server records |
| `task_id` | enum | `T-ANN-PUB`, `T-ANN-READ`, `T-VAC-BAL`, `T-VAC-REQ`, `T-VAC-REJ`, `T-VAC-APR`, `T-VAC-COV`, `T-BRF-VIEW` |
| `feature` | enum | `ann`, `vac`, `brf` |
| `mode` | enum | `classic`, `agent` |
| `order_index` | int | position of this mode for this participant/task (counterbalancing) |
| `app_version`, `os_version`, `locale` | string | no device identifiers |
| `ts` | datetime | event time |

## Events
| Event | When | Extra fields | Req |
|---|---|---|---|
| `task_started` | the participant begins the task (prompt shown / entry screen opened) | | EXP-001 |
| `task_completed` | the task's persisted outcome is achieved | `elapsed_ms`, `tap_count`, `message_count` (agent only), `outcome_valid` (bool, server-verified against Outcome AC) | EXP-001/002 |
| `task_abandoned` | user leaves the flow without outcome | `elapsed_ms`, `tap_count`, `last_state` | EXP-001 |
| `task_error` | domain or system error visible to the user | `code` (e.g. `INSUFFICIENT_BALANCE`, `OVERLAP`, `BLACKOUT`, `FORBIDDEN`, `WORKIQ_UNAVAILABLE`, `AGENT_TOOL_FAILURE`), `recovered` (bool) | EXP-003 |
| `confirm_shown` | review screen (classic) or confirm card (agent) displayed | `action` (publish/request/cancel/decide/opt_in) | FR-AUTH-006 |
| `confirm_accepted` / `confirm_rejected` | user taps confirm / dismisses | `action`, `latency_ms` since shown | FR-AUTH-006 |
| `agent_turn` | each agent response completed (client) | `latency_first_token_ms`, `latency_total_ms`, `tool_calls` (count) | EXP-002/005 |
| `satisfaction` | after task, optional | `score` 1-5 | EXP-006 |
| `session_comparison` | end of session, optional | `preferred_mode` (`classic`/`agent`/`same`), `score_ease_classic`, `score_ease_agent` | EXP-006 |
| `withdrawal` | participant withdraws | none (triggers deletion job) | EXP-007 |

## Server-side records (joined by `task_run_id`)
| Record | Fields | Req |
|---|---|---|
| `api_call` | `endpoint`, `status`, `latency_ms`, count per task | EXP-005 |
| `agent_run` | `model_id`, `input_tokens`, `output_tokens`, `tool_call_count`, `latency_ms`, `estimated_cost` | EXP-005, NFR-006 |
| `safety_counter` | `unconfirmed_write_blocked`, `cross_user_block`, `injection_detected` (counts only, never content) | H9 |
| `outcome_check` | `task_run_id`, `outcome_valid`, `reason` | H3, H4 |

**Implemented (CLASSIC, EXP-005):** `api_call` only. The iOS services send `X-Task-Run-Id` (the flow's
`task_run_id`) on REST calls made for a task (`TaskRun` in `Packages/Core`); `api/app/telemetry.py` records
method, route template (never ids or query), status and latency per run in an in-memory `ApiCallLog`, with
count and summed latency per run. Calls without the header, with an invalid one, or to `/v1/events` are not
recorded; neither are calls answered 401, and the log keeps the newest 50000 records. The run id is a client-supplied uuid and is not bound to the caller, so an authenticated participant could add calls to another run (accepted for the PoC, same trust as the events themselves). The app tags calls only while a flow is running, so a badge refresh after a finished run is not attributed to it. **Implemented (AGENT, comms slice):** `agent_run` (`api/app/agents/turns.py::AgentRun`: model id, input/output tokens,
tool-call count, latency, joined by `X-Task-Run-Id`; `estimated_cost` is not computed yet) and `safety_counter`
(`api/app/mcp/audit.py`: `unconfirmed_write_blocked`, `cross_user_block` per correlation id; `injection_detected` is not
detected server-side), both in memory like the other records. Not implemented: durable storage (same gap as the event sink, ADR-009), and a separate `outcome_check` record (`outcome_valid` already travels
on `task_completed`, and nothing verifies it server-side yet).

Never recorded: announcement text, calendar content, user prompts/agent replies, rejection reasons,
names, emails, tokens.

## Derived metrics
| Metric | Definition | Unit of analysis |
|---|---|---|
| Time on task | `elapsed_ms` of `task_completed` | per participant x task x mode |
| Taps | `tap_count` | same |
| Errors | count of `task_error` per run; wrong-outcome rate = share of completed runs with `outcome_valid = false` | same |
| Completion | completed with `outcome_valid=true` / (completed + abandoned) | per task x mode |
| Satisfaction | mean `score` | per task x mode |
| Cost per task | agent: `estimated_cost` from `agent_run`; classic: infra cost apportioned per API call (method in `analysis.md`) | per task x mode |
| Confirm friction | median `confirm_shown -> confirm_accepted` latency | per action x mode |
| Safety | any `unconfirmed_write_blocked` that was NOT blocked (should be 0), cross-user disclosures (should be 0) | per session |
| Work IQ success | briefing runs ending in content or defined empty state / all runs | per user |

## Collection rules
- Emit from the shared task-flow wrapper in `Packages/Core` so every flow gets events by construction;
  each slice adds its flow to the task table above (CLAUDE.md invariant).
- Events are batched and sent to `api/` (`POST /v1/events`), validated against this schema; unknown fields rejected.
- Retention of events is configurable and unset (U-05, PRIV-004).
- Participants are informed what is collected and can withdraw (EXP-007, U-14).

## Flows implemented
| Task | Mode | Where | Notes |
|---|---|---|---|
| `T-ANN-PUB` | classic | `Packages/Features/.../PublishModel` via `TaskFlow` (FR-ANN-001) | `confirm_*` fire on Review. Taps count explicit button and picker actions, not text-field focus. `participant_id` is a per-install random uuid until `GET /v1/me/participant` exists. `POST /v1/events` validates and accepts but has no durable sink yet. |
| `T-ANN-READ` | classic | `Packages/Features/.../FeedModel` via `TaskFlow` (FR-ANN-003) | `task_started` when the feed opens; `task_completed` when the API confirmed the read mark of an opened announcement; a failed or offline open emits `task_error` (`recovered: true`) and no completion. `task_abandoned` is not emitted yet (the feed is a tab, so there is no reliable leave signal). `confirm_*` do not apply. |
| `T-VAC-BAL` | classic | `Packages/Features/.../VacationOverviewModel` via `TaskFlow` (FR-VAC-001) | `task_started` when the overview opens; `task_completed` when the five numbers came from the API in that load. Offline (cached numbers with an as-of time) emits `task_error` `OFFLINE` with `recovered: true` and no completion. `confirm_*` do not apply. `task_abandoned` is not emitted (the overview is a tab, so there is no reliable leave signal). |
| `T-VAC-REQ` | classic | `Packages/Features/.../VacationRequestModel` via `TaskFlow(confirmAction: .request)` (FR-VAC-002) | `task_started` when the request sheet opens; `confirm_shown` with `action=request` when Review is shown for an accepted dry run (a blocked review never shows a confirm); `confirm_accepted` on "Request"; `confirm_rejected` on back; `task_completed` after the API created the request; `task_error` carries only the first reason code (`INVALID_RANGE`, `PAST_DATE`, `ZERO_DAYS`, `BLACKOUT`, `OVERLAP`, `INSUFFICIENT_BALANCE`, `CANTON_MISSING`, `OFFLINE`, ...), never dates or reasons. Taps count day taps, the entry toggle, Continue, Request and back. Closing the sheet before success emits `task_abandoned` with `last_state` `dates` or `review`. |
| `T-VAC-REJ` | classic | same screens as `T-VAC-REQ` | Not emitted separately yet: the app cannot know that a participant was assigned the "fix a rejected request" task. The `task_error` + later `task_completed` sequence of a `T-VAC-REQ` run carries the signal; the session protocol has to relabel those runs (open item for the experiment protocol). |
| `T-VAC-APR` | classic | `Packages/Features/.../ManagerInboxModel` + `RequestDetailModel` via `TaskFlow(confirmAction: .decide)` (FR-VAC-004) | `task_started` when the Freigaben tab (inbox) opens, and again for the next decision once the previous run finished. `confirm_shown` with `action=decide` when the approve dialog or the reject sheet opens; `confirm_accepted` on Approve / Reject; `confirm_rejected` on Cancel or sheet swipe-down (once). `task_completed` after the API decided. `task_error` carries only the first code (`BLACKOUT`, `OVERLAP`, `INSUFFICIENT_BALANCE`, `INVALID_STATE`, `FORBIDDEN`, `OFFLINE`, ...) and never the reason text, names or dates. Taps count Approve, Reject and refresh. `task_abandoned` is not emitted (the inbox is a tab). The badge refresh does not touch the flow. |
| `T-VAC-COV` | classic | `Packages/Features/.../TeamCoverageModel` via `TaskFlow` (FR-VAC-005) | `task_started` when the Team segment of Freigaben opens; `task_completed` once the API's per-day numbers are on screen (a range change loads again but the flow is already finished). Range changes and refresh count as taps. `FORBIDDEN` and `OFFLINE` emit `task_error` (`OFFLINE` with `recovered: true` when the last result stays visible). `confirm_*` do not apply; `task_abandoned` is not emitted (segment of a tab). The overlap strip in the approval detail uses the same endpoint but is part of `T-VAC-APR`, not a separate run. |
| (none) | classic | `HolidaysModel` (FR-VAC-006), sign-in and sign-out (FR-AUTH-001, FR-AUTH-005) | Not tasks of the protocol, so they emit no events. Holidays are loaded by the request flow for its calendar under `T-VAC-REQ`. |
| (none) | classic | `RequestDetailModel` (FR-VAC-003, FR-VAC-007) | Cancel and "My requests" are not tasks of the protocol (no `task_id` in the table above), so they emit no events. `My requests` loads through the `T-VAC-BAL` overview flow. If the protocol adds a cancel task, wrap `confirmCancel` in `TaskFlow(confirmAction: .cancel)`; `action=cancel` already exists in the schema. |
