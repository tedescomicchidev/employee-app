# Mockups index (Phase 1)

64 iPhone artboards (390 x 844, light, German) for the employee app, grouped by feature and by mode.
Tokens: `../tokens.md`. Requirements: `docs/product/requirements.md`. State coverage: `screen-state-matrix.md`.

- Canvas: https://claude.ai/artifact/KBSkMptueutWEYfaw6GshJ (one artboard per screen).
- Status: draft for human review. Mockups are human-owned; HIG and system components win over them.
- Example data is invented. People, dates and balances are placeholders. HR-CONFIRM values are not policy.
- Shared example, same outcome in both modes: Vacation 24 Dec 2026 to 4 Jan 2027, 6 counted days, balance 13 -> 8.
  Announcement "Früher Start am Freitag" to region Tessin, 47 people.

## Naming: one name for artboard title, PNG and this index

The artboard title on the canvas is the exported PNG name, and the "PNG" column below is the same string plus `.png`.
Pattern from the matrix: `<feature>-<screen>-<state>-<appearance>-<size>-<lang>.png`.

- `feature`: `announcements`, `vacation`, `briefing`.
- `screen`: words joined by `_`. Agent screens start with `agent_` (`agent_chat`, `agent_confirm_card`); classic
  screens have no prefix. Mode is therefore part of the name and no two screens collide.
- `state`: `ok`, `loading`, `empty`, `error`, `offline`, `forbidden`, `confirming`, `success`, `expired`, `partial`, or a
  specific case (`validation_overlap`, `invalid_state`, `error_workiq_unavailable`, ...).
- `appearance` = `light`, `size` = `default`, `lang` = `de` in this round. Dark, AX5 and other languages reuse the
  stem with the changed field (`-dark-`, `-ax5-`, `-fr`).
- Rename rule: change the artboard title on the canvas first, then this table, then export. The internal artboard
  file (last column) is not used in exports and may stay as is.

State legend (from the matrix): L loading, E empty, OK populated, ERR error, OFF offline, 403 not allowed,
P partial, V validation, C confirming, S success.

## 1. Announcements

### CLASSIC (10)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `announcements-feed-ok-light-default-de.png` | Feed | OK (unread dots, language chip, "2 neu") | FR-ANN-003 | `Main` |
| 2 | `announcements-feed-loading-light-default-de.png` | Feed | L | FR-ANN-003 | `a-feed-loading` |
| 3 | `announcements-feed-empty-light-default-de.png` | Feed | E | FR-ANN-003 | `a-feed-empty` |
| 4 | `announcements-feed-error-light-default-de.png` | Feed | ERR (retry, correlation id) | FR-ANN-003 | `a-feed-error` |
| 5 | `announcements-feed-offline-light-default-de.png` | Feed | OFF (as-of banner, compose disabled) | FR-ANN-003, NFR-007 | `a-feed-offline` |
| 6 | `announcements-detail-ok-light-default-de.png` | Announcement detail | OK (plain text, language label, link only on tap) | FR-ANN-003, FR-ANN-005 | `a-detail` |
| 7 | `announcements-compose-ok-light-default-de.png` | Compose (Publisher) | OK / V limits (title 120, body 5'000) | FR-ANN-001 | `a-compose` |
| 8 | `announcements-audience-ok-light-default-de.png` | Audience picker | OK (chips, live count, "Alle" exclusive) | FR-ANN-002 | `a-audience` |
| 9 | `announcements-review-ok-light-default-de.png` | Review / confirm | OK (exact payload, recipient count, Publish) | FR-ANN-001, FR-AUTH-006 | `a-review` |
| 10 | `announcements-review-success-light-default-de.png` | Review / confirm | S ("An 47 Personen veröffentlicht") | FR-ANN-001 | `a-published` |

### AGENT (10)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `announcements-agent_chat-empty-light-default-de.png` | Chat | E (welcome + 3 suggested prompts) | A11Y-006 | `a-ag-welcome` |
| 2 | `announcements-agent_chat-loading-light-default-de.png` | Chat | L (status line, stop) | NFR-005 | `a-ag-working` |
| 3 | `announcements-agent_chat-ok-light-default-de.png` | Chat | OK (answer from feed tool; instruction-like text shown as quoted data) | FR-ANN-003, FR-ANN-005 | `a-ag-answer` |
| 4 | `announcements-agent_confirm_card-ok-light-default-de.png` | Confirm card | OK (payload, Abbrechen / Veröffentlichen, validity) | FR-ANN-001, FR-ANN-002, FR-AUTH-006 | `a-ag-proposal` |
| 5 | `announcements-agent_confirm_card-confirming-light-default-de.png` | Confirm card | C (busy, cancel disabled) | FR-ANN-001 (idempotent) | `a-ag-executing` |
| 6 | `announcements-agent_confirm_card-success-light-default-de.png` | Confirm card | S (outcome line from tool result, link to detail) | FR-ANN-001 | `a-ag-success` |
| 7 | `announcements-agent_confirm_card-expired-light-default-de.png` | Confirm card | TTL expired, `INVALID_CONFIRMATION`, re-propose | FR-AUTH-006 | `a-ag-expired` |
| 8 | `announcements-agent_chat-offline-light-default-de.png` | Chat | OFF (input disabled "Verbindung nötig") | NFR-007 | `a-ag-offline` |
| 9 | `announcements-agent_chat-error-light-default-de.png` | Chat | ERR ("couldn't do that", retry, reference) | - | `a-ag-error` |
| 10 | `announcements-agent_chat-forbidden-light-default-de.png` | Chat | 403 (role-limited message, no card) | FR-AUTH-002, FR-ANN-001.4 | `a-ag-403` |

Announcement detail is shared with CLASSIC (#6); agent links open it.

## 2. Vacation

### CLASSIC, employee (11)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `vacation-overview-ok-light-default-de.png` | Balance / overview | OK (13 days, composition, next request, links) | FR-VAC-001 | `v-overview` |
| 2 | `vacation-overview-loading-light-default-de.png` | Overview | L (skeleton numbers) | FR-VAC-001 | `v-overview-loading` |
| 3 | `vacation-overview-offline-light-default-de.png` | Overview | OFF (as-of, request button disabled) | NFR-007 | `v-overview-offline` |
| 4 | `vacation-request-ok-light-default-de.png` | Request, date range | OK (weekend + holiday markers, text-entry alternative) | FR-VAC-002, FR-VAC-006, A11Y-005 | `v-request-dates` |
| 5 | `vacation-request-validation_overlap-light-default-de.png` | Request, date range | V `OVERLAP` inline, continue disabled | FR-VAC-002 (R6) | `v-request-overlap` |
| 6 | `vacation-review-ok-light-default-de.png` | Review / confirm | OK (6 counted days, excluded days, year split, balance after) | FR-VAC-002, FR-AUTH-006 | `v-review` |
| 7 | `vacation-review-validation_insufficient_balance-light-default-de.png` | Review / confirm | V `INSUFFICIENT_BALANCE` (14 requested, 13 available) | FR-VAC-002 (R5) | `v-review-balance` |
| 8 | `vacation-review-success-light-default-de.png` | Review / confirm | S ("Pending with Marco Rossi") | FR-VAC-002 | `v-submitted` |
| 9 | `vacation-my_requests-ok-light-default-de.png` | My requests | OK (grouped by status, rejection reason shown) | FR-VAC-007 | `v-mine` |
| 10 | `vacation-my_requests-empty-light-default-de.png` | My requests | E | FR-VAC-007 | `v-mine-empty` |
| 11 | `vacation-request_detail-cancel_dialog-light-default-de.png` | Request detail (owner) | OK + C (cancel confirm dialog) | FR-VAC-003 | `v-detail` |

Holidays are a sub-view of the overview (row "Feiertage Kanton Zürich"); the sub-view itself is not drawn.

### CLASSIC, managers (7)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `vacation-manager_inbox-ok-light-default-de.png` | Manager inbox | OK (3 waiting, badge) | FR-VAC-004 | `v-inbox` |
| 2 | `vacation-manager_inbox-empty-light-default-de.png` | Manager inbox | E ("Nothing waiting") | FR-VAC-004 | `v-inbox-empty` |
| 3 | `vacation-request_decision-ok-light-default-de.png` | Request detail / decision | OK (balance, team presence, Approve / Reject) | FR-VAC-004, FR-VAC-005 | `v-decide` |
| 4 | `vacation-request_decision-reject_reason-light-default-de.png` | Reject with reason | V (reason <= 500) | FR-VAC-004 | `v-reject` |
| 5 | `vacation-request_decision-invalid_state-light-default-de.png` | Request detail | `INVALID_STATE` already decided, actions disabled | FR-VAC-004.3 | `v-decided` |
| 6 | `vacation-team_coverage-ok-light-default-de.png` | Team coverage | OK (present of total per day, absent names, pending marked) | FR-VAC-005 | `v-team` |
| 7 | `vacation-team_coverage-forbidden-light-default-de.png` | Team coverage | 403 (non-manager) | FR-VAC-005.2 | `v-team-403` |

### AGENT (8)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `vacation-agent_chat-ok-light-default-de.png` | Chat | OK (numbers from `get_balance` only) | FR-VAC-001 | `v-ag-balance` |
| 2 | `vacation-agent_confirm_card-ok-light-default-de.png` | Confirm card | OK (same content as classic review) | FR-VAC-002, FR-AUTH-006 | `v-ag-proposal` |
| 3 | `vacation-agent_confirm_card-success-light-default-de.png` | Confirm card | S (pending with approver) | FR-VAC-002 | `v-ag-success` |
| 4 | `vacation-agent_chat-validation_insufficient_balance-light-default-de.png` | Chat | Proposal invalid: no card, reason code, alternative from tool | FR-VAC-002 (R5) | `v-ag-invalid` |
| 5 | `vacation-agent_chat-clarification-light-default-de.png` | Chat | Ambiguous person: clarifying question, no card | FR-VAC-004 | `v-ag-ask` |
| 6 | `vacation-agent_confirm_card-decision_ok-light-default-de.png` | Confirm card | OK (decision payload, team presence) | FR-VAC-004 | `v-ag-mgr-card` |
| 7 | `vacation-agent_confirm_card-validation_blackout-light-default-de.png` | Confirm card | V re-validation failure `BLACKOUT`, request stays pending | FR-VAC-004.2 | `v-ag-mgr-fail` |
| 8 | `vacation-agent_chat-team_coverage-light-default-de.png` | Chat | OK (answer from `get_team_coverage`) | FR-VAC-005 | `v-ag-team` |

Request detail is shared with CLASSIC (`v-detail`, `v-decide`).

## 3. Weekly briefing

### CLASSIC (12)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `briefing-opt_in-ok-light-default-de.png` | Opt-in | initial (names what is read, "Nicht jetzt") | FR-BRF-001 | `b-optin` |
| 2 | `briefing-opt_in-consent_in_progress-light-default-de.png` | Opt-in | consent in progress (system web sheet, neutral placeholder) | FR-AUTH-004 | `b-consent` |
| 3 | `briefing-opt_in-notification_permission-light-default-de.png` | Opt-in, reminder | notification permission asked in context (pre-prompt + system alert) | FR-BRF-003 | `b-notif` |
| 4 | `briefing-week-loading-light-default-de.png` | Briefing (week) | L ("Dein Kalender wird gelesen", still-working note) | FR-BRF-002.5 | `b-loading` |
| 5 | `briefing-week-ok-light-default-de.png` | Briefing (week) | OK (days, conflicts, free blocks) | FR-BRF-002 | `b-week` |
| 6 | `briefing-week-empty-light-default-de.png` | Briefing (week) | E ("Keine Termine diese Woche") | FR-BRF-005.2 | `b-empty` |
| 7 | `briefing-week-partial-light-default-de.png` | Briefing (week) | P (missing days named, retry per day) | FR-BRF-005.3 | `b-partial` |
| 8 | `briefing-week-error_workiq_unavailable-light-default-de.png` | Briefing (week) | ERR `WORKIQ_UNAVAILABLE` | FR-BRF-005.1 | `b-error` |
| 9 | `briefing-week-error_no_licence-light-default-de.png` | Briefing (week) | ERR `NO_LICENCE` | FR-BRF-005.1 | `b-licence` |
| 10 | `briefing-week-offline-light-default-de.png` | Briefing (week) | OFF (no stale calendar content shown) | NFR-007, PRIV-003 | `b-offline` |
| 11 | `briefing-day-ok-light-default-de.png` | Briefing day detail | OK (conflict marker, free blocks >= 60 min) | FR-BRF-002 | `b-day` |
| 12 | `briefing-settings-ok-light-default-de.png` | Settings (Mehr) | OK + notifications denied in iOS (explanation + link) | FR-BRF-001.4, FR-BRF-003 | `b-settings` |

### AGENT (6)
| # | PNG | Screen / state | Matrix state | Requirements | Artboard |
|---|---|---|---|---|---|
| 1 | `briefing-agent_chat-opt_in_offer-light-default-de.png` | Chat, opt-in prompt | OK (explanation + confirm card, opt-in is a write) | FR-BRF-001.2 | `b-ag-offer` |
| 2 | `briefing-agent_chat-loading-light-default-de.png` | Chat | L ("Lese deinen Kalender", stop) | FR-BRF-002.5 | `b-ag-working` |
| 3 | `briefing-agent_chat-ok-light-default-de.png` | Chat | OK (every day counted, link to full list) | FR-BRF-002 | `b-ag-week` |
| 4 | `briefing-agent_chat-declined_other_calendar-light-default-de.png` | Chat | Other user's calendar: decline, no card, no tool call | FR-BRF-004 | `b-ag-other` |
| 5 | `briefing-agent_chat-error_workiq_unavailable-light-default-de.png` | Chat | ERR `WORKIQ_UNAVAILABLE`, no summary | FR-BRF-005 | `b-ag-error` |
| 6 | `briefing-agent_chat-consent_required-light-default-de.png` | Chat | Consent missing `CONSENT_REQUIRED` (proposed code), consent card | FR-AUTH-004 | `b-ag-consent` |

## 4. Not drawn yet

- Cross-cutting screens: sign-in (idle, in progress, failed, cancelled, no network), role/home tabs loading state,
  experiment satisfaction prompt, mode switch in settings (EXP-004).
- AUTH state ("Sign in again" sheet) on any screen; confirm-card `INVALID_CONFIRMATION` other than expiry;
  `RATE_LIMITED`, partial tool failure and "stopped by user" chat states; withdraw announcement (FR-ANN-004, Could).
- Compose is for the Publisher role only; the 403 case is covered by the agent screen
  `announcements-agent_chat-forbidden`, the classic entry is hidden.
- Dark appearance, AX5 Dynamic Type, FR / IT / EN variants of every screen (screenshot scenarios in the matrix).
- Holidays sub-view; announcement detail "withdrawn while open"; vacation year-boundary note.

## 5. Coverage check against the matrix

| Requirement from the brief | PNG stems (without `-light-default-de.png`) |
|---|---|
| Loading | `announcements-feed-loading`, `vacation-overview-loading`, `briefing-week-loading`, `announcements-agent_chat-loading`, `briefing-agent_chat-loading` |
| Empty | `announcements-feed-empty`, `vacation-my_requests-empty`, `vacation-manager_inbox-empty`, `briefing-week-empty`, `announcements-agent_chat-empty` |
| Error | `announcements-feed-error`, `briefing-week-error_workiq_unavailable`, `briefing-week-error_no_licence`, `announcements-agent_chat-error`, `briefing-agent_chat-error_workiq_unavailable`, `vacation-review-validation_insufficient_balance`, `vacation-request-validation_overlap`, `vacation-agent_confirm_card-validation_blackout` |
| Offline | `announcements-feed-offline`, `vacation-overview-offline`, `briefing-week-offline`, `announcements-agent_chat-offline` |
| Consent | `briefing-opt_in-ok`, `briefing-opt_in-consent_in_progress`, `briefing-opt_in-notification_permission`, `briefing-agent_chat-opt_in_offer`, `briefing-agent_chat-consent_required` |
| Confirm before every write | classic review screens + agent confirm cards (`announcements-agent_confirm_card-ok`, `vacation-agent_confirm_card-ok`, `vacation-agent_confirm_card-decision_ok`, `briefing-agent_chat-opt_in_offer`) |
