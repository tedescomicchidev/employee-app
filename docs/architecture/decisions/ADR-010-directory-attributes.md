# ADR-010: Directory attributes source

Status: proposed. Requirements: FR-ANN-002, FR-VAC-004, FR-VAC-006. Open: A-12, U-07.

## Context
Audience targeting, approver routing and holiday counting need canton, store or HQ, region, role, manager and
language per employee. Entra may or may not hold these for the 11 seeded users (U-07 is unanswered).
A Graph sync job needs an application permission such as `User.Read.All`, which is an extra app-only consent.

## Decision
- The source of truth for the PoC is a seed file keyed by Entra `oid`, loaded into `employees` by `scripts/seed-demo.sh`.
- No app-only Graph sync. Identity facts (oid, name, roles) still come from the token.
- If the human's U-07 export shows reliable Entra attributes, the seed file is generated from that export, not synced live.
- A user who signs in but has no `employees` record gets a clear "not provisioned" error and no data.

## Consequences
- Directory changes in Entra do not propagate automatically; acceptable for 11 users.
- Avoids a standing app-only permission on the whole directory (smaller attack surface, no extra consent).
- The seed file is personal data (names mapped to oids): keep it out of git if it holds real names; the repo uses synthetic data.

## Alternatives
- Live Graph sync with `User.Read.All`: fresher data, one more consent and a long-lived privileged credential.
- Delegated Graph at sign-in: only gives the user's own attributes, not their reports or audiences.

## Sources
- docs/product/open-questions.md (A-12, U-07)
