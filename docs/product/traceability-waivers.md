# Traceability waivers

`scripts/check-traceability.sh` (run by `scripts/ci-check.sh`) fails when a requirement ID in
`requirements.md` is named by no test. An ID may be listed here instead, with the reason it has no test
yet. The script also fails on a stale waiver (the ID now has a test), so entries leave this file as the
tests land. Format: `- ID: reason`. Reviewed at the close of the CLASSIC build (phase 5).

## Not built yet (feature or process does not exist)

- FR-ANN-004: withdraw an announcement (Could); not implemented in CLASSIC or AGENT.
- FR-BRF-001: briefing opt-in; the briefing feature is not built (phase 8).
- FR-BRF-002: briefing content; not built (phase 8).
- FR-BRF-003: briefing screen; not built (phase 8).
- FR-BRF-004: briefing settings; not built (phase 8).
- FR-BRF-005: briefing failure states; not built (phase 8).
- EXP-004: mode assignment and counterbalancing are not built; `ModeStore` fixes `.classic` in Release and the setter is DEBUG-only.
- EXP-006: satisfaction items (Should); not built.
- EXP-007: participant withdrawal and event deletion; needs the durable events store (ADR-009), not built.
- NFR-011: rate and payload limits; only the agent turn endpoint has them (per-user rate limit, message count and size, tested in `api/tests/test_agent_turn.py`). REST endpoints and the MCP endpoint have no rate limit (the MCP body is capped at 64 KiB); edge limits are infra.
- PRIV-004: retention TTLs and deletion job; not built, values are HUMAN_CONFIRMATION_REQUIRED (U-05).
- PRIV-006: export and delete of one user's data; process owner open, not built.
- PRIV-009: `PrivacyInfo.xcprivacy` derived from the data inventory; release phase (11).
- PRIV-010: crash-report exclusions and app-switcher blanking; not built.

## AGENT mode or Work IQ only (no CLASSIC surface)

- FR-AUTH-004: on-behalf-of Work IQ consent; needs the agents (phase 6).
- PRIV-003: Work IQ handling; phase 6/8.

## Verified by a check that does not name the ID, or by a human

- NFR-001: `ci-check.sh` rejects literal `location: '...'` values other than switzerlandnorth in Bicep. Narrow: a parameter default or variable is not checked; Foundry exceptions need an ADR.
- NFR-002: whole-system `azd` deployment; human-only action, verified in the release runbook.
- NFR-003: iOS 17+ and Swift 6 strict concurrency are enforced by `project.yml` (`SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete`, deployment target) and the build; MSAL is the only external package (`project.yml`).
- NFR-004: Custom App distribution; App Store Connect, human-only.
- NFR-005: latency targets will be measured from EXP-005 `api_call` records, which now exist per task run; no threshold test or dev measurement yet.
- NFR-006: cost per task needs the EXP-005 records (CLASSIC call count and latency exist per task run) plus a computation that is not built.
- A11Y-004: Reduce Motion, Bold Text, Increase Contrast and Reduce Transparency are not asserted by an automated test and have not been checked by hand in this phase; the high-contrast colour sets exist and are covered by the DesignSystem colour test.
- A11Y-006: chat accessibility; AGENT mode only (phase 6).
- A11Y-007: localised labels come from the same catalogs as NFR-009 (tested); the release-metadata claims half is phase 11.
- NFR-014: `ci-check.sh` greps Bicep for four key-based-access patterns (`listKeys`, `listSecrets`, `adminUserEnabled: true`, `disableLocalAuth: false`). Not a general secret check; there is no secret scanner on code, plist or logs yet.
- PRIV-001: `docs/privacy/data-inventory.yml` is maintained by hand in each PR; no automated diff check yet.
