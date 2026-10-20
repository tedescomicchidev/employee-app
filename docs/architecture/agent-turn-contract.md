# Agent turn contract (device <-> api)

`POST /v1/agent/{comms|vacation}/turns`. Bearer = the user's Entra token (`access_as_user`).
The device never calls Foundry. Implemented in `api/app/routes/agent.py`, `api/app/agents/stream.py`.

Foundry streaming source: Responses API server-sent events (`response.created`,
`response.output_text.delta`, `response.completed`),
https://learn.microsoft.com/azure/foundry/how-to/develop/framework-hosted-agents#responses-protocol

## Request
```
{ "messages": [{"role": "user"|"assistant", "content": str}],   // 1..20, each <= 4000 chars
  "confirmation": {"proposal_id": UUID, "confirmation_token": str} | null }
```
Header `X-Task-Run-Id: <uuid>` (EXP-005). The device keeps the history and resends it (PRIV-004).
Send `Accept: text/event-stream` for a stream; without it the same body returns one JSON object.

## Errors before the stream opens (normal JSON `{code, message}`)
401 UNAUTHENTICATED, 403 NOT_PROVISIONED | AGENT_UNAVAILABLE (consent), 404 NOT_FOUND,
413 PAYLOAD_TOO_LARGE, 429 RATE_LIMITED (with `Retry-After` seconds), 503 AGENT_NOT_CONFIGURED.

## Stream events (`text/event-stream`, one `event:` + one JSON `data:` line)
| event | data | meaning |
|---|---|---|
| `status` | `{phase: "warming"}` | no word from the agent for ~3 s: cold start |
| `status` | `{phase: "thinking"}` | the agent is working |
| `status` | `{phase: "tool", name}` | a tool call started (name only) |
| `tool` | `{name, ok}` | a tool call finished |
| `delta` | `{text}` | more of the reply text. Display only; never parsed for meaning |
| `final` | `{reply, tool_calls}` | the grounded reply. Replaces everything shown so far |
| `error` | `{code: "AGENT_UNAVAILABLE", message}` | the turn failed; nothing was written by this turn that `tool_calls` does not show |

Exactly one `final` or `error` ends a stream. A stream that ends without either is a failure.

## `reply`
Common: `kind`, `text` (<= 4000), `proposal_id`.
- comms kinds: `message | clarification | proposal | published | refusal`; extra `sources: [{announcement_id, title}]` (<= 10), `reason`.
- vacation kinds: `message | clarification | options | proposal | submitted | cancelled | decided | refusal`; extra `options: [{proposal_id, start, end}]` (<= 3), `reason`.
- `reason` (refusal only): a short code `^[a-z][a-z_]{0,39}$` (`write_without_confirmation`, `role_not_allowed`, `rule_bypass`, `out_of_scope`, `other_users_data`, `untrusted_instructions`, `unsupported_action`). The device always shows `text` (a generic line if it is empty); the code is not shown and is not logged by the device.
- Grounding (api): a claimed write is kept only if the matching tool succeeded this turn; `proposal_id` must be the caller's own unexpired proposal; vacation option dates and comms source titles come from the store; sources the caller cannot see are dropped, and sources are cleared unless `kind = message`.
- `tool_calls`: `[{name, ok}]`. Names only; the device maps them to localized labels.

## Writes
Unchanged (auth-flows.md flow 3): the card is rendered from `GET /v1/proposals/{id}`; a tap calls
`POST /v1/confirmations`; the next turn carries `confirmation`. Editing a draft is a new
proposal from the agent (the old card becomes superseded on the device). Rejecting is device-side only.

## Device behaviour (iOS)
- History: the device keeps it, sends at most the last 20 messages, each cut to 4000 characters; a longer user message is not sent.
- `delta` text is shown while it arrives and replaced by `final.reply.text`; VoiceOver is told once, when the reply is complete.
- A line of the reply that starts with `>` is shown in the quoted data block (agent quoting an announcement); nothing in a reply is rendered as markup or a link.
- Retry repeats exactly one thing, the most recent failed step: a plain turn, minting the token again, or the confirmation turn with the same `confirmation_token` (idempotent). A new message replaces it, so a retry can never repeat a confirmation the user is no longer looking at. A failed card has its own retry that does not depend on the error banner.
- Offline means the network monitor says so (the composer is disabled). A request that fails with no connection shows a recoverable notice; a timeout on a working network is `AGENT_UNAVAILABLE`, not offline.
- The confirm card states the outcome in the app's own words, from the stored proposal; the agent's sentence is in the transcript, never what the card asserts.
- A card stops offering its tap when its validity (`expires_at`) runs out; the api enforces it as well.
- `Retry-After` on 429 blocks the composer until it passes.
