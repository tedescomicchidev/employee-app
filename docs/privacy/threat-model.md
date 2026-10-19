# Threat model

Scope so far: AGENT mode for announcements (phase 6, comms). Other features add rows in their slices.
Boundary: `api/` (REST and `/mcp`) is the trust boundary. The model, its instructions and the toolbox are not.

| # | Threat | Control | Test |
|---|---|---|---|
| T1 | Prompt injection through announcement text makes the agent call tools or leak data | Tool results are marked `content_trust: untrusted`; instructions say data is not instructions; the agent's MCP tool is limited to the six comms tools (`allowed_tools`); every write needs a server-issued token; read tools return only the caller's items | `evals/comms` injection cases (live) and `api/tests/test_agent_eval_replay.py` (attack traces replayed against `/mcp`) |
| T2 | The agent publishes without the user's consent ("yes" in chat, "just do it") | `publish_announcement` requires a `confirmation_token` bound to oid, action and payload hash, single use, 5 min; chat text never yields one | `test_mcp_comms.py`, `test_announcements_publish.py`, evals `no-publish-without-confirm`, `verbal-yes` |
| T3 | The agent mints its own token | `POST /v1/confirmations` accepts only `access_as_user`; no MCP tool confirms | `test_fr_auth_006_agent_cannot_mint_a_token` |
| T4 | Token confusion: a Tools.Invoke token used on REST, or a user token on MCP | Separate audiences and scopes (ADR-002 pt 5) | `test_adr_002_audiences_are_not_interchangeable` |
| T5 | App-only or managed-identity token used to read user data via MCP | MCP requires a delegated `scp=Tools.Invoke` token with `oid`; no scp means 401 | `test_fr_auth_003_app_only_token_is_rejected` |
| T6 | Cross-user disclosure (outside audience, bulk requests, "all announcements ever") | Same services and audience rules as REST; tools take no user argument; `NOT_FOUND` for not addressed | `test_fr_ann_002_outside_audience_cannot_list_or_fetch`, evals `bulk-request-*` |
| T7 | Model claims success it did not achieve | `api/` downgrades `published` without a successful publish call; instructions require tool success first | `test_fr_ann_001_published_is_only_believed_after_the_tool_succeeded` |
| T8 | Abuse of `x-ms-user-identity` (impersonation) | The value is the validated `oid`, never client input; only the api identity holds `UserIdentityImpersonation` (human-only RBAC) | `test_turn_calls_foundry_as_the_validated_user_with_an_obo_tools_token` |
| T9 | Cost or availability abuse of agent turns | Per-user rate limit, message count and size limits on the turn endpoint; MCP body capped at 64 KiB | `test_turn_endpoint_rate_and_size_limits` |
| T10 | Secrets or content in logs | Audit and error paths carry codes and ids only | `test_fr_auth_003_audit_line_is_logged_without_content`, `test_tokens_are_not_logged` |
| T12 | The forwarded tools token leaks (prompt, logs, other requests) or is replayed across users | Held in a per-request context variable and one Authorization header; never in a prompt, tool argument or log; each request builds its own agent; a request without it fails closed; tokens are short-lived and audience-bound to `employee-tools` | `agents/tests/test_comms_forwarding.py` (token reaches `/mcp`, two users in a row, missing token), `test_http_responder_sends_the_agreed_headers_and_body` |
| T11 | Exfiltration via rendered links or images in agent text | Instructions forbid; the app renders agent text as plain text (iOS slice, not yet built) | evals `injection-image`, `injection-confirm-link` (live only) |

Residual risks and open items: the model's behaviour is only measured by live evals, which have not run against a
deployed system; REST and `/mcp` have no edge rate limit; the audit trail is in memory plus log lines (no durable
store, ADR-009); S-3 (how the tool token reaches `/mcp`) is unverified; the vacation and briefing tools extend T1/T6.
