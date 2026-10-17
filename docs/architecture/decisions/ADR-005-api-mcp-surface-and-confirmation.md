# ADR-005: API and MCP surface, and write confirmation

Status: proposed, depends on spike S-3. Requirements: FR-AUTH-002, 003, 006, NFR-008, FR-ANN-005, PRIV-005.

## Context
Both modes must have identical domain rules. Agents act only through `api/` MCP tools. Every write needs a
confirmation that the agent cannot forge (A-13).

## Decision
- One domain service layer in `api/`. Two adapters: REST `/v1/*` (app) and MCP over streamable HTTP at `/mcp`
  (agents), in the same Container App with separate auth dependencies (scope `access_as_user` vs `Tools.Invoke`).
  The tool-to-route table is in `overview.md` section 4.
- NFR-008 contract suite runs each scenario through both adapters and compares outcomes and error codes.
- **Proposals:** `propose_*` runs the same validation as the write (dry run), stores a proposal
  (oid, action, payload, hash, TTL) and returns `proposal_id` plus a summary.
- **Native confirm card:** the app loads `GET /v1/proposals/{id}` over REST and renders the card itself. Model text
  is never the source of what is confirmed.
- **Token mint:** `POST /v1/confirmations {proposal_id}` returns a single-use token bound to oid, action and payload hash,
  TTL 5 minutes (configurable). It requires `access_as_user` and rejects `Tools.Invoke` tokens, so an agent cannot mint one.
- **Execute:** `publish_/create_/cancel_/decide_/set_*(token)` verify user, action, hash, unused, unexpired, then write.
  Replays map to a deterministic document id derived from the token and return the existing result.
  Failures: `CONFIRMATION_REQUIRED`, `INVALID_CONFIRMATION`.
- The token reaches the agent as an opaque structured input on the next turn.
- Tool results that contain third-party text (announcement bodies, calendar titles) are wrapped and marked untrusted (FR-ANN-005).
- Tools are minimal-field and have no user parameter for other people's data (FR-BRF-004, PRIV-005).

## Consequences
- **Spike S-3:** verify structured inputs on hosted agents and that the token survives to the tool call. If it does not,
  the fallback is `api/` attaching the token to the MCP call itself (token never goes through the model).
- A model that hallucinates a token fails safely: the hash binds it to one payload.
- Two adapters mean contract tests are mandatory, not optional.

## Alternatives
- Agent mints tokens after the user says "yes" in chat: rejected (FR-AUTH-006.4).
- Model-generated confirm UI: rejected, spoofable (A-13).
- GraphQL or a single RPC surface for both: no benefit; MCP is the agent-facing standard.

## Sources
- learn.microsoft.com/azure/foundry/agents/concepts/toolbox-overview
- learn.microsoft.com/azure/foundry/agents/how-to/structured-inputs
- docs/product/requirements.md FR-AUTH-006
