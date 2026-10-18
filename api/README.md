# api

FastAPI service for Azure Container Apps.

- `GET /health` is open.
- `GET /v1/me` returns the caller's identity and roles. Every non-health route validates the
  Entra access token (signature, issuer, audience, expiry, tenant, `access_as_user` scope).
- Roles come from the token `roles` claim (`Communicator`, `Manager`, `Employee`); use
  `app.auth.principal.authorize` / `require_roles` so REST and the Phase 6 MCP tools share checks.

Config (non-secret): `ENTRA_TENANT_ID`, `API_CLIENT_ID`, optional `API_AUDIENCE`
(default `api://<API_CLIENT_ID>`).

The MCP tool server lands in Phase 6 (see CLAUDE.md invariants).
