# agents/vacation
Vacation agent (FR-VAC-001..007 AGENT, FR-AUTH-003/006). Microsoft Agent Framework, Responses protocol.
Same shape as `agents/comms`; see its README for the layout and the code-deploy rules.

- `prompts/vN.md`: versioned instructions. Never edit a released version; add `v(N+1).md` and
  select it with `VACATION_INSTRUCTIONS_VERSION`. `evals/vacation` must pass before a version is deployed.
- `vacation_schemas.py`: the structured reply (`kind`, `text`, `proposal_id`, `options`) shared with `api/`.
  Ids and dates only: day counts and balances are rendered by the app from the stored proposal.
- `main.py`: per-request agent + MCP tool to `api/` (`API_MCP_URL`, the eleven vacation tools only) + `ResponsesHostServer`.
  `vacation_context.py` is a copy of `comms_context.py` (flat deploy); a test keeps them identical.
- Writes (`create_vacation_request`, `cancel_vacation_request`, `decide_vacation_request`) need the
  `confirmation_token` the app mints from the confirm card. Authorization (manager, assigned approver,
  SELF_APPROVAL) is enforced in `api/`, never here.

Run locally (agent-allowed): `azd ai agent run vacation` and, in another shell,
`azd ai agent invoke --local "what is my balance?"`. Deploying is human-only.
