# api: conventions
Python 3.12, FastAPI, managed with uv. Run from `api/`.

- Setup/run: `uv sync`, `uv run uvicorn app.main:app --reload`
- Lint/test: `uv run ruff check . && uv run ruff format --check . && uv run pytest`
- Business rules live here, never in prompts or the iOS app. REST endpoints and
  MCP tools must call the same domain services and the same role checks.
- Validate Entra tokens (issuer, audience, roles) on every non-health route.
  OBO (user-delegated) is used for Graph, the tools resource app (`Tools.Invoke`) and Work IQ; never
  app-only for user data, and never cache other users' Work IQ output.
- Writes by agent tools require a `confirmation_token` issued by the app's confirm card.
- No secrets in code or logs. Key Vault + managed identity. Never log tokens or PII.
- Emit experiment events per docs/experiment/metrics.md for every task flow.
- Every requirement ID maps to at least one test in `tests/`.
- Pin dependencies via `uv.lock`; do not add packages you have not verified exist.
- Layout: `app/` (code), `tests/`. MCP tool server: `app/mcp/` (`/mcp`, `Tools.Invoke`); agent gateway: `app/agents/`, `routes/agent.py`.
