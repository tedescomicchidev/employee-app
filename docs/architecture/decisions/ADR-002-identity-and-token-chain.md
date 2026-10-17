# ADR-002: Identity and token chain

Status: proposed. Requirements: FR-AUTH-001, 002, 003, 005, NFR-011, EXP-005.

## Context
The request was: MSAL on iOS, then the API with scope `access_as_user`, then OBO to `https://ai.azure.com` for
agent calls. Foundry's hosted-agent guidance differs. The backend authenticates to Foundry as itself with a workload
token for `https://ai.azure.com/.default`; that token "doesn't represent the user's downstream permissions". The user
is named with the `x-ms-user-identity` header, which needs a custom data action not included in any built-in role.
OBO is for the downstream API token, forwarded to the agent in an `x-client-*` header. A Microsoft Q&A answer also
states `ai.azure.com` is not exposed as a consentable delegated API permission.

## Decision
1. The iOS app is a public client (MSAL). It requests `api://employee-api/access_as_user`. Tokens live in the Keychain only.
2. `api/` validates issuer, audience, signature, expiry, `scp` and `roles` on every request.
3. `api/` is the **agent gateway**: the app never calls Foundry. For an agent turn `api/`:
   - does OBO to get T-tools (scope `Tools.Invoke` on the resource app `employee-tools`),
   - gets T-foundry with its user-assigned managed identity (`https://ai.azure.com/.default`),
   - calls the hosted agent's Responses endpoint with `store:false`, `Authorization: T-foundry`,
     `x-client-api-access-token: T-tools`, `x-ms-user-identity: <oid>`.
4. The OBO client credential is a federated identity credential on the managed identity. No client secret exists.
5. REST requires scope `access_as_user`; MCP requires `Tools.Invoke`. A token for one is rejected by the other.
6. The gateway enforces rate and payload limits (values in Phase 3) and records `agent_run` cost data.

## Consequences
- This departs from the literal request in step 3 (workload token, not OBO, for `ai.azure.com`). Flagged in the PR.
- The api identity needs Foundry Agent Consumer plus the custom `UserIdentityImpersonation` role (human-only RBAC).
- Hosted agents must use container protocol 2.0.0 for `x-ms-user-identity` to resolve a trusted user id.
- Spike S-1: self-OBO (same app) is likely unsupported, so a second small resource app is the default. If the toolbox
  `user-entra-token` or `oauth2` connection types fit better than header forwarding, T-tools handling changes but
  the audience/scope split does not.
- Extra hop and latency in the gateway; measured against NFR-005.

## Alternatives
- App calls Foundry directly with a user token for `ai.azure.com`: needs Foundry roles for every user, has no consentable
  delegated scope, and bypasses server-side limits and cost capture. Rejected.
- Pass T-user itself to the agent: the agent container would hold a token valid for all REST writes. Rejected.

## Sources
- learn.microsoft.com/azure/foundry/agents/how-to/use-on-behalf-of-flow
- learn.microsoft.com/azure/foundry/agents/concepts/hosted-agent-permissions (delegate the end-user identity)
- learn.microsoft.com/azure/foundry/agents/how-to/tools/tool-authentication
- learn.microsoft.com/answers/a/12695581 (ai.azure.com is RBAC, not an API permission)
- learn.microsoft.com/entra/identity-platform/v2-oauth2-on-behalf-of-flow
