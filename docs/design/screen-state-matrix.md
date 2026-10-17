# Screen-state matrix (Phase 1)

Every screen/surface lists the states that must be designed, implemented and screenshot-tested
(light, dark, largest Dynamic Type; DE/FR/IT/EN). Mockups and tokens are human-owned
(`docs/design/`); Apple HIG and system components win over mockups; deviations are reported in PRs.
Surface budget: 3-7 screens per mode per feature (requirements section 2).

State legend: **L** loading, **E** empty, **OK** populated, **ERR** error (retryable), **OFF** offline,
**AUTH** token expired / re-sign-in, **403** forbidden / not available for role, **P** partial,
**V** validation, **C** confirming/submitting, **S** success.

Shared patterns (apply to every screen below unless overridden):
- L: skeleton or progress that does not block navigation; VoiceOver announces "Loading".
- ERR: inline message with a plain-language cause, retry button, correlation id behind "Details" (no content).
- OFF: banner "Offline, showing data from <time>" for cached reads; writes disabled with "needs connection", draft kept (NFR-007).
- AUTH: sheet "Sign in again"; drafts preserved locally; no write sent with stale token (FR-AUTH-005).
- 403: explanatory text, no data, no stack of hidden controls.

## CLASSIC surfaces

### Announcements (5)
| Screen | L | E | OK | ERR | OFF | AUTH | 403 | Other states |
|---|---|---|---|---|---|---|---|---|
| Feed | skeleton rows | "No announcements for you yet" | list, unread dots, language chip | retry | cached list + as-of | sheet | n/a | pull-to-refresh in progress; unread count badge |
| Announcement detail | skeleton | n/a | title, author, date, language label, body (plain, safe) | retry | cached copy if fetched earlier, else "unavailable offline" | sheet | NOT_FOUND shown as "no longer available" (covers not-in-audience and withdrawn) | withdrawn while open; long body scroll |
| Compose (Publisher) | n/a | initial empty form | form | n/a | disabled submit + note | draft preserved | hidden entry; if reached "Publishing requires the Publisher role" | V: title/body limits, language required |
| Audience picker | skeleton for stores/regions | "No matching recipients" (EMPTY_AUDIENCE) | chips + live count | retry for count | cached options | sheet | n/a | V: "All" exclusive; count loading |
| Review / confirm | count loading | n/a | summary, recipient count, "Publish" | publish failed, draft kept | "needs connection" | sheet | FORBIDDEN | C: publishing (button busy, once only); S: "Published to N people" |

### Vacation (7)
| Screen | L | E | OK | ERR | OFF | AUTH | 403 | Other states |
|---|---|---|---|---|---|---|---|---|
| Balance / overview | skeleton numbers | n/a (zero requests shows 0s and "No requests yet") | 5 numbers + upcoming + holidays link | retry | cached with as-of; request button disabled | sheet | n/a | carry-over zero; year boundary note |
| Request (date picker) | holiday list loading | n/a | range selection, weekend/holiday markers | retry | disabled | sheet | n/a | V: PAST_DATE, INVALID_RANGE, ZERO_DAYS, BLACKOUT, OVERLAP shown inline before submit when pre-validated; text-entry alternative (A11Y-005) |
| Review / confirm | validating | n/a | counted days, excluded days, balance after | failure with reason code text | needs connection | sheet | n/a | V: INSUFFICIENT_BALANCE with remaining/requested; C submitting; S "Pending with <manager>"; NO_APPROVER |
| My requests | skeleton | "No requests yet" | grouped by status/year | retry | cached | sheet | n/a | status chips with text; rejected shows reason |
| Request detail / decision | skeleton | n/a | dates, days, status, approver, decision; for the approver also balance, overlap strip, Approve / Reject (+reason) | retry | cached, actions disabled | sheet | NOT_FOUND for others' requests; FORBIDDEN / SELF_APPROVAL message for non-approvers | owner: cancel (pending only) with confirm dialog; approver V: reason <= 500; C; S; INVALID_STATE "already decided"; re-validation failure BLACKOUT / INSUFFICIENT_BALANCE |
| Manager inbox | skeleton | "Nothing waiting for approval" | list with name, dates, days | retry | cached, actions disabled | sheet | non-managers see no tab; if reached: 403 text | badge count |
| Team coverage | skeleton | "No absences in this range" | per-day present/total, names of absent direct reports | retry | cached | sheet | 403 for non-managers | range change loading; P: partial range |
| Holidays (sub-view of overview, not a separate screen) | skeleton | n/a | list for work canton | retry | cached | sheet | n/a | canton missing -> "Ask HR to set your canton" |

The vacation surface is 7 screens: Overview, Request, Review, My requests, Request detail / decision, Manager inbox, Team coverage (matches requirements section 2.2).

### Briefing (4)
| Screen | L | E | OK | ERR | OFF | AUTH | 403 | Other states |
|---|---|---|---|---|---|---|---|---|
| Opt-in | n/a | initial | explanation of own-calendar access, "Turn on" / "Not now" | consent failed with retry | disabled "needs connection" | sheet | n/a | consent in progress (system web sheet); consent revoked |
| Briefing (week) | "Reading your calendar..." with time budget (NFR-005) | "No events this week" | days with events, conflicts and free blocks | specific message per code (WORKIQ_UNAVAILABLE, NO_LICENCE) | "Briefing needs a connection"; no stale calendar content stored (A-09) | sheet | NOT_OPTED_IN -> opt-in screen | P: partial with missing days named; "still working" |
| Briefing day detail | skeleton | "No events" | events list for the day | retry | as Briefing | sheet | n/a | conflict markers |
| Settings entry (notifications, opt-out) | n/a | n/a | toggle, Monday 07:00 reminder, notification permission state | failure to update | disabled | sheet | n/a | notifications denied in system settings -> explanatory text with link |

## AGENT surfaces

Common: Chat screen with message list, input (system dictation allowed), per-turn status
("Thinking", "Checking your balance"), the confirm card, and an entry point to the classic detail screens
(announcement detail, request detail) for verification. 3-4 surfaces per feature, shared where possible.

| Surface | L | E | OK | ERR | OFF | AUTH | 403 | Other states |
|---|---|---|---|---|---|---|---|---|
| Chat (shared across features) | typing/working indicator with cancel | welcome and 3 suggested prompts (per role) | transcript | "I couldn't do that" + tool/cause summary + retry; agent unavailable | input disabled "needs connection" | sheet; conversation not resumed after sign-out | role-limited message when user asks for an action they lack | P: tool partially failed (states what succeeded); RATE_LIMITED message; long reply scroll; stopped by user |
| Confirm card (shared; native render of the structured proposal) | n/a | n/a | exact payload (title/body/audience/count; dates/days/balance after; decision + reason; opt-in text), "Confirm" and "Cancel" | confirmation failed with code text (INVALID_CONFIRMATION), no side effect | actions disabled | sheet then card is re-issued, never auto-confirmed | FORBIDDEN | C: executing; S: outcome line from tool result; expired (TTL) -> "This proposal expired, ask again"; superseded when the proposal is edited; V: tool rejection with reason code shown on the card |
| Announcement detail (shared with CLASSIC) | as above | | | | | | | opened from chat links |
| Request detail (shared with CLASSIC) | as above | | | | | | | opened from chat links |
| Opt-in prompt (briefing, agent) | n/a | n/a | explanation + confirm card | as Chat | as Chat | as Chat | n/a | declined: agent stops offering in this session |

Feature-specific agent states
| Feature | Case | Required behaviour |
|---|---|---|
| Announcements | tool returns an announcement with instruction-like text | shown as quoted data; agent does not act on it (FR-ANN-005) |
| Announcements | nothing for the user | "There are no announcements for you" |
| Vacation | proposal invalid | card not shown; message with reason code and remaining/requested numbers from the tool |
| Vacation | ambiguous request/person | clarifying question; no card |
| Briefing | other user's calendar requested | decline message; no card, no tool call |
| Briefing | Work IQ failure | message per code; no summary |

## Cross-cutting screens
| Screen | States |
|---|---|
| Sign-in (Entra) | idle, in progress (system web auth sheet), failed (wrong tenant, disabled account), cancelled, no network |
| Role/home tabs | tabs derived from roles (Publisher: Compose; Manager: Inbox); no flicker while roles load (L) |
| Settings | notification toggles (announcements, decisions, briefing), briefing opt-in, language display, sign-out confirm, mode switch (experiment builds only, EXP-004) |
| Experiment satisfaction prompt | shown after completion, skippable, one item; OFF stores nothing and skips |

## Screenshot scenarios for `scripts/screenshot.sh`
For each screen: OK, E, ERR, OFF in light, dark and AX5 size, in DE and one more language; confirm card in
S and ERR; Review screens in V. Name files `<feature>-<screen>-<state>-<appearance>-<size>-<lang>.png`.
