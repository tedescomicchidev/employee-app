# ADR-007: Cosmos data model

Status: proposed. Requirements: FR-ANN-002, FR-VAC-002, PRIV-004, PRIV-006, PRIV-008, NFR-012. Retention: U-05 (unset).

## Context
About 100 employees, 11 in the demo. Rules: no existence leaks, atomic overlap and balance checks, deletion by user,
configurable TTL per data class, no content in logs.

## Decision
One database, **serverless**, single region (Switzerland North), zone redundancy enabled at creation (it cannot be
added later for serverless). Entra-only data-plane auth with RBAC; no keys.

| Container (partition key) | Notes |
|---|---|
| `employees` (/oid) | seed-file attributes (ADR-010): canton, store/HQ, region, role, manager_oid, language |
| `user_settings` (/oid) | `briefing_optin`, notification prefs |
| `vacation` (/oid) | `request` docs and one `balance_guard` doc per user. Create and decide use an etag-guarded transactional batch on the owner's partition, so overlap (R6) and balance (R5) checks cannot race. Balance is computed from requests (R3), not stored. `day_fraction` field present for A-03. |
| `vacation_params` (/oid) | entitlement, carry-over, `carry_over_cap` nullable |
| `config` (/type) | holidays by canton, blackout ranges |
| `announcements` (/id) | content, language, audience rule, recipient-count snapshot, status |
| `announcement_inbox` (/oid) | one doc per recipient: announcement id, read_at, mirrored status. Fan-out at publish. |
| `confirmations` (/oid, TTL) | proposals and tokens (ADR-005) |
| `participants` (/participant_id) | oid mapping, own RBAC role, deletable |
| `events` (/participant_id, TTL) | experiment events and server records (ADR-009) |

- Feed reads are single-partition on `announcement_inbox`, so a user can only ever see their own recipients (FR-ANN-002.3).
- Withdraw (FR-ANN-004) updates the mirrored status on the inbox docs.
- Manager inbox is a cross-partition query on `approver_oid` + `status`; at this size it is cheap. If it grows, add a change-feed projection.
- Idempotency: document ids derive deterministically from the confirmation token; a create conflict returns the existing result.
- TTL per container is a config parameter with no default period asserted. Deletion by user id covers `employees`,
  `user_settings`, `vacation*`, `announcement_inbox` and `participants`/`events`.
- Audit goes to Log Analytics (content-free), not Cosmos.

## Consequences
- Fan-out writes up to about 100 docs per publish; fine at this size.
- Serverless has a single-region limit and cost less predictable than provisioned; acceptable for a PoC.
- `data-inventory.yml` gains `announcement-inbox`, `participants-mapping`, `proposals` entries (PRIV-001).

## Alternatives
- Store `recipient_oids` inside the announcement: one doc, but feed queries become cross-partition and visibility depends on query filters.
- Provisioned autoscale: waives the zone-redundancy premium but costs more at idle.
- Separate account for experiment data: stronger isolation, more infra; revisit if the DPIA asks.

## Sources
- learn.microsoft.com/azure/cosmos-db/serverless
- learn.microsoft.com/azure/reliability/reliability-cosmos-db
- learn.microsoft.com/azure/cosmos-db/data-residency
