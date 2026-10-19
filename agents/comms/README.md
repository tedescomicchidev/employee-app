# agents/comms
Announcements agent (FR-ANN-001..005 AGENT, FR-AUTH-003). Microsoft Agent Framework, Responses protocol.

- `prompts/vN.md`: versioned instructions. Never edit a released version; add `v(N+1).md` and
  select it with `COMMS_INSTRUCTIONS_VERSION`. `evals/comms` must pass before a version is deployed.
- `schemas.py`: the structured reply (`kind`, `text`, `proposal_id`) shared with `api/`.
- `main.py`: per-request agent + MCP tool to `api/` (`API_MCP_URL`, the six comms tools only) + `ResponsesHostServer`.
  `comms_context.py` moves the forwarded `x-client-api-access-token` into the request context; `comms_instructions.py`, `comms_schemas.py`.
- Tools come only from `api/`'s MCP server, called as the user with the token `api/` forwards. No toolbox (ADR-002, S-3).
  The agent holds no rules and never puts the token in a prompt.

Run locally (agent-allowed): `azd ai agent run comms` and, in another shell,
`azd ai agent invoke --local "what's new?"`. Deploying is human-only.

Layout is flat on purpose: azd code mode zips this folder (`main.py` at the root) and Foundry installs
`requirements.txt` on Python 3.13 (`dependencyResolution: remote_build`). No Docker or registry is involved.
Modules import each other by plain name; tests put this folder on `pythonpath`. Keep `requirements.txt` in step
with `../pyproject.toml`.
