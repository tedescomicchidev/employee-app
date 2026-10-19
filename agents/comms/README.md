# agents/comms
Announcements agent (FR-ANN-001..005 AGENT, FR-AUTH-003). Microsoft Agent Framework, Responses protocol.

- `prompts/vN.md`: versioned instructions. Never edit a released version; add `v(N+1).md` and
  select it with `COMMS_INSTRUCTIONS_VERSION`. `evals/comms` must pass before a version is deployed.
- `schemas.py`: the structured reply (`kind`, `text`, `proposal_id`) shared with `api/`.
- `main.py`: agent + `FoundryToolbox` (`core-tools`) + `ResponsesHostServer`.
- Tools come only from the toolbox (api/ MCP server). The agent holds no tools, tokens or rules.

Run locally (agent-allowed): `azd ai agent run comms` and, in another shell,
`azd ai agent invoke --local "what's new?"`. Deploying is human-only.

`requirements.txt` is generated from `agents/uv.lock`; after changing dependencies run, from `agents/`:
`uv export --frozen --no-dev --no-hashes --no-emit-project --prerelease allow -o comms/requirements.txt`
