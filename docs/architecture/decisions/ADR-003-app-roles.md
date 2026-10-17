# ADR-003: App roles

Status: proposed. Requirements: FR-AUTH-002, FR-ANN-001, FR-VAC-004, FR-VAC-005.

## Context
Phase 1 proposed `Announcement.Publish`, `Vacation.Approve` and `Employee`. The Phase 2 request names the roles
`Communicator`, `Manager`, `Employee`. Approver routing (R10) is a data relationship, not a role.

## Decision
- Three Entra app roles on `employee-api`, allowed member type Users: `Communicator`, `Manager`, `Employee`.
  Role value strings equal the names. `requirements.md` section 1 is updated to match.
- Roles grant capabilities only:
  - `Communicator`: propose and publish announcements, resolve audiences.
  - `Manager`: approvals inbox, decide requests, team coverage. Whether *this* manager may decide *this* request is
    checked from `manager_oid` (R10), never from the role alone.
  - `Employee`: everything an employee does. Every seeded user holds it.
- The enterprise app has **Assignment required = Yes**, so unassigned and non-tenant accounts cannot get a token (FR-AUTH-001).
- One authorization module in `api/` serves REST and MCP. The UI hides actions by role, `api/` denies them (`FORBIDDEN`).
- Demo assignments: CEO = Communicator + Manager + Employee (the CEO approves managers' requests); 2 managers =
  Manager + Employee; 8 employees = Employee.

## Consequences
- Roles arrive in the access token `roles` claim; a role change applies after the next token refresh.
- A-11 (more than one Communicator) is supported by assignment, with only the CEO in the demo.
- If roles are removed in Entra mid-session, a still-valid token keeps working until expiry; acceptable for the PoC.

## Alternatives
- Groups claim: token size and overage handling, no benefit at 11 users.
- Keeping the Phase 1 names: rejected, the request names override.

## Sources
- docs/product/requirements.md sections 1 and 4
