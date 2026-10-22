# agents/briefing
Weekly briefing agent (FR-BRF-001, 002, 004, 005 AGENT, FR-AUTH-004). Microsoft Agent Framework, Responses protocol.
Same shape as `agents/vacation`; see `agents/comms/README.md` for the layout and the code-deploy rules.

- `prompts/vN.md`: versioned instructions. Never edit a released version; add `v(N+1).md` and
  select it with `BRIEFING_INSTRUCTIONS_VERSION`. `evals/briefing` must pass before a version is deployed.
- `briefing_schemas.py`: the structured reply (`kind`, `text`, `proposal_id`, `omitted_count`, `reason`) shared with `api/`.
- `main.py`: per-request agent + MCP tool to `api/` (`API_MCP_URL`, the four briefing tools only) + `ResponsesHostServer`.
  `briefing_context.py` is a copy of `comms_context.py` (flat deploy); a test keeps them identical.
- **No Work IQ connection and no toolbox** (ADR-004 U-03, ADR-002 S-3): `api/` reads Work IQ on behalf of the user
  inside `get_my_week`. The tools take no user argument, so another person's calendar cannot be requested.
- The opt-in toggle (`set_briefing_optin`) is a write and needs the `confirmation_token` from the app's confirm card.

Run locally (agent-allowed): `azd ai agent run briefing` and, in another shell,
`azd ai agent invoke --local "brief me on my week"`. Deploying is human-only.
