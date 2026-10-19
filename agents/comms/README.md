# agents/comms
Announcements agent (FR-ANN-001..005 AGENT, FR-AUTH-003). Microsoft Agent Framework, Responses protocol.

- `prompts/vN.md`: versioned instructions. Never edit a released version; add `v(N+1).md` and
  select it with `COMMS_INSTRUCTIONS_VERSION`. `evals/comms` must pass before a version is deployed.
- `schemas.py`: the structured reply (`kind`, `text`, `proposal_id`) shared with `api/`.
- `main.py`: agent + `FoundryToolbox` (`core-tools`) + `ResponsesHostServer`. `comms_instructions.py`, `comms_schemas.py`.
- Tools come only from the toolbox (api/ MCP server). The agent holds no tools, tokens or rules.

Run locally (agent-allowed): `azd ai agent run comms` and, in another shell,
`azd ai agent invoke --local "what's new?"`. Deploying is human-only.

Layout is flat on purpose: azd code mode zips this folder (`main.py` at the root) and Foundry installs
`requirements.txt` on Python 3.13 (`dependencyResolution: remote_build`). No Docker or registry is involved.
Modules import each other by plain name; tests put this folder on `pythonpath`. Keep `requirements.txt` in step
with `../pyproject.toml`.
