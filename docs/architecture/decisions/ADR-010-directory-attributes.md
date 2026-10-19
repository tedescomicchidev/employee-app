# ADR-010: Directory attributes source

Status: proposed. Requirements: FR-ANN-002, FR-VAC-004, FR-VAC-006. Open: A-12, U-07.

## Context
Audience targeting, approver routing and holiday counting need canton, store or HQ, region, role, manager and
language per employee. Entra may or may not hold these for the 11 seeded users (U-07 is unanswered).
A Graph sync job needs an application permission such as `User.Read.All`, which is an extra app-only consent.

## Decision
Revised after the human confirmed the tenant already holds the users: nobody is added to a seed, and
no identities are assumed.
- Identity facts (oid, name, roles) come from the token. The HR attributes (work canton, store, region) and the
  manager come from Microsoft Graph, read **user-delegated** by `api/` with an on-behalf-of exchange of the
  caller's own token (`GET /me`, `GET /me/manager`, delegated `User.Read`). No app-only permission, no secret.
- `api/` authenticates the exchange with the container app's user-assigned managed identity, trusted by a
  federated identity credential on the `employee-api` app registration (no client secret).
- Each user's own record is written on first sign-in and refreshed after a TTL (default 12 h). A manager is
  stored as a stub (oid + name) until they sign in, so approver routing works without them having signed in.
- Which Graph properties hold canton, store and region is tenant specific and configured, not assumed
  (`GRAPH_CANTON_ATTRIBUTE` default `state`, `GRAPH_STORE_ATTRIBUTE` default `officeLocation`,
  `GRAPH_REGION_ATTRIBUTE` default `preferredLanguage`). A value that is not one of the 26 canton codes is
  treated as unknown: the app shows "Ask HR to set your canton" and never guesses.
- Roles stay in the token (ADR-003). The synthetic seed file remains for tests and the 11 demo users.
- A user whose lookup fails (no consent, Graph unreachable) has no record and gets `NOT_PROVISIONED`.
- Feature flag `GRAPH_DIRECTORY` (off by default) until the Entra steps in docs/architecture/auth-flows.md are done.

## Consequences
- No seed export and no standing directory permission; each lookup runs with the signed-in user's rights.
- The directory only knows people who have signed in (and managers named by them). Audience targeting
  (FR-ANN-002) therefore reaches only users who have opened the app at least once, until a directory
  export or Graph sync is approved (U-07). This is a known PoC limit.
- Records live in memory like the other stores until Cosmos lands (ADR-007); a restart refills them on next sign-in.
- Needs a Graph `User.Read` consent for `employee-api` (human-only) and the managed identity federated credential.

## Alternatives
- Live Graph sync with `User.Read.All`: fresher data, one more consent and a long-lived privileged credential.
- Delegated Graph at sign-in: chosen (see Decision). Gives only the user's own attributes and manager, not their reports or audiences.

## Sources
- docs/product/open-questions.md (A-12, U-07)
