# Requirements (Phase 1)

Source: `docs/product/brief.md` (human-owned) and the discovery answers recorded in
`docs/product/open-questions.md` (section "Decisions"). Status: draft for human review.

Conventions
- **MoSCoW**: M = must for the PoC, S = should, C = could. W = explicitly not in this PoC.
- Every `FR-*` has one shared **Outcome AC** (what is published / requested / approved / shown) that
  is identical for both modes, plus a `[CLASSIC]` and an `[AGENT]` interaction variant. A variant may
  differ in *how* the user gets there, never in *what ends up true* or in the domain rules.
- Domain rules live in `api/` only. The AGENT variant calls the same domain services through MCP
  tools, acting as the calling user. Agents never hold rules in prompts.
- Any write (publish, submit, cancel, approve, reject) needs an explicit user confirmation in the app.
  CLASSIC: the user's own submit action on a review screen. AGENT: the confirm card, which issues a
  single-use `confirmation_token` (see FR-AUTH-006).
- `HR-CONFIRM` = placeholder value or rule that HR/legal must confirm. Nothing marked HR-CONFIRM is a
  policy claim. `HUMAN_CONFIRMATION_REQUIRED` = same, for non-HR facts.
- Error codes (`INSUFFICIENT_BALANCE`, `OVERLAP`, ...) are proposed, stable identifiers; Phase 2 may
  rename them, but both modes must surface the same code/reason.
- Time zone for all business dates: Europe/Zurich. Dates are calendar dates, not instants.

## 1. Roles and personas

| Role | Entra app role (proposed) | Seeded demo users | Can do |
|---|---|---|---|
| Publisher (CEO / Comms) | `Communicator` | 1 (CEO) | publish announcements; also an employee |
| Manager | `Manager` | 2 (+ CEO, who approves managers' requests, R10) | approve/reject requests of direct reports; see team coverage; also an employee |
| Employee | `Employee` (default) | 8 (+ all above) | read announcements, see own balance, request/cancel vacation, opt in to briefing |

Reporting lines (employee -> manager; manager -> CEO) come from the seeded directory/Entra `manager`
attribute (assumption A-12). Employee attributes needed: work canton, store or HQ, region, language,
role, manager.

## 2. Feature fit

Core function / core loop (action -> reward < 30 s) / accessory / surface area (3-7 screens per mode) /
retention hook (honest, opt-in).

### 2.1 Announcements
| | CLASSIC | AGENT |
|---|---|---|
| Core function | CEO/Comms publishes a message to an audience; employees read it | same outcome, via conversation |
| Core loop | Publisher: compose -> pick audience -> confirm -> "Published to N people". Employee: open app -> see new announcement | Publisher: "Tell all HQ staff the store opens at 8 on Friday" -> draft + audience + confirm card -> published. Employee: "what's new?" -> answer from feed tool |
| Accessory | audience targeting (region/store/role), unread badge, withdraw (C) | same; summaries of long items (must not alter meaning, links back to original) |
| Surface (screens) | Feed, Announcement detail, Compose, Audience picker, Review/confirm (5) | Chat, Confirm card (embedded), Announcement detail (shared), Feed entry point (4) |
| Retention hook | opt-in push for new announcements (iOS notification permission asked in context, not at launch) | same setting |

### 2.2 Vacation
| | CLASSIC | AGENT |
|---|---|---|
| Core function | know my balance, request days, manager approves, see team coverage | same outcomes via conversation |
| Core loop | Employee: Vacation tab -> balance visible immediately -> pick dates -> review -> submit -> "Pending with <manager>". Manager: inbox -> approve in 2 taps | Employee: "Request 3 to 7 Nov" -> proposal (days counted, balance after) -> confirm -> pending. Manager: "approve Anna's request" -> card -> confirm |
| Accessory | cantonal holidays shown, request history/status, cancel pending, team coverage for managers | same through tools; agent must quote numbers returned by tools only |
| Surface | Balance/overview, Request (date pick), Review/confirm, My requests, Manager inbox, Request detail/decision, Team coverage (7) | Chat, Confirm card, Request detail (shared) (3) |
| Retention hook | opt-in notification when my request is decided | same setting |

### 2.3 Weekly briefing (optional, opt-in)
| | CLASSIC | AGENT |
|---|---|---|
| Core function | summary of *my* upcoming week from *my* calendar via Work IQ | same outcome, conversational |
| Core loop | open Briefing -> week overview in < 30 s (generation target is an NFR) | "How does my week look?" -> same facts |
| Accessory | conflicts and free blocks; public holiday / approved vacation overlay (C) | follow-up questions about *my own* items only |
| Surface | Opt-in screen, Briefing, Briefing detail (day), Settings entry (4) | Chat, Opt-in prompt (2) |
| Retention hook | the only one: opt-in Monday 07:00 Europe/Zurich local notification (honest: it says "Your week is ready", contains no calendar content) | same setting |

Work IQ feasibility constraint driving design: Work IQ is user-delegated (OBO) only, so there is no
unattended server-side generation at 07:00. The briefing is generated when the user opens it (or taps
refresh); the 07:00 item is a local notification only. See U-03.

## 3. Facts, assumptions, unknowns

Facts (from the brief and Phase 0): see `brief.md`. Stack: SwiftUI iOS 17+, FastAPI on Container Apps,
Foundry hosted agents + toolboxes, Cosmos DB, Bicep/azd. 11 seeded users. Out of scope: sick leave and
health data, payroll, Android, Teams client.

Assumptions and unknowns are tracked with risk in `docs/product/open-questions.md`. Summary, ranked by
impact (S scope, A architecture, P privacy, W Work IQ feasibility, D App Store distribution):

| Rank | ID | Unknown | Impacts | Handling in this document |
|---|---|---|---|---|
| 1 | U-03 | Work IQ API surface, licence and consent in the demo tenant; user-delegated only | W, A, P | FR-BRF-* depend on it; FR-BRF-005 defines degraded state; spike in Phase 2 |
| 2 | U-01 | HR rules: weekends/half-days, holiday counting, carry-over legality, entitlement values | S, A | placeholders flagged HR-CONFIRM; engine parameterised |
| 3 | U-05 | Retention periods and deletion duties (nDSG) | P, A | configurable TTL (PRIV-004); nothing asserted |
| 4 | U-04 | Holiday data source for 26 cantons (authoritative table, municipal holidays, half-day holidays) | S, A | seeded table, HUMAN_CONFIRMATION_REQUIRED |
| 5 | U-06 | Translation of announcement content (DE/FR/IT/EN) | S | assumed authored per language; no machine translation |
| 6 | U-07 | Org data: manager/region/store/canton attributes available in Entra? | A, S | assumption A-12; seed file fallback |
| 7 | U-08 | Custom App via ABM: review notes, reviewer account without MFA | D | Phase 11 |
| 8 | U-09 | Foundry hosted agent data residency in Switzerland North and model availability | A, P, NFR-001 | verify in Phase 2; document deviation if unavailable |
| 9 | U-02 | Whether announcements can be edited/withdrawn, and who is notified | S | FR-ANN-004 is Could |
| 10 | U-10 | Do employees see peers' absences? | S, P | assumed no; managers only |

## 4. Functional requirements

### FR-ANN: Announcements

**FR-ANN-001 (M) Publish an announcement to all employees**
- Outcome AC
  1. Given a user with role Publisher, when they confirm a draft with title (1-120 chars), body (1-5,000 chars), content language (de/fr/it/en) and audience "all", then exactly one announcement exists with status `published`, author, `published_at`, language and audience.
  2. Every active employee can see it; nobody else (no guests, no deactivated users).
  3. A draft that is not confirmed is never visible to anyone and creates no `published` record.
  4. A user without the Publisher role gets `FORBIDDEN` and no announcement is created, in either mode.
  5. Publishing the same confirmed draft twice (retry, double tap, replayed token) creates one announcement (idempotent).
- [CLASSIC] Compose screen -> Review screen showing title, body, audience and recipient count -> user taps "Publish".
- [AGENT] Agent collects missing fields in conversation, calls `propose_announcement`, the app renders a confirm card with the same review content; only the user's tap on the card yields the `confirmation_token`; the agent then calls `publish_announcement(token)`. The agent states "published" only after the tool returns success. If the user says "just publish it" without a confirm tap, nothing is published and the agent says confirmation is needed.

**FR-ANN-002 (S) Target an announcement by region, store, and role**
- Outcome AC
  1. A Publisher can set the audience to any combination (union) of regions, stores/HQ, and roles; "all" is mutually exclusive with the others.
  2. The recipient set equals the employees whose attributes match; the review step shows the exact recipient count before confirmation.
  3. An employee outside the audience cannot list, fetch by id, or be told about the announcement (no existence leak, including via the agent or push).
  4. An audience resolving to zero recipients cannot be published (`EMPTY_AUDIENCE`).
  5. Audience is evaluated at publish time and stored as the rule plus a recipient-count snapshot; whether late joiners see it is open (U-02), default: they do not.
- [CLASSIC] Audience picker with multi-select chips for region / store / role.
- [AGENT] Agent maps natural language ("Ticino stores", "all managers") to structured audience via tool; if ambiguous it asks; confirm card shows the structured audience and count.

**FR-ANN-003 (M) Read announcements addressed to me**
- Outcome AC
  1. An employee sees exactly the published announcements whose audience includes them, newest first, each with title, author, date, language, read/unread state.
  2. Opening an announcement marks it read for that user only.
  3. Empty, loading, error and offline states follow the screen-state matrix; offline shows last successfully fetched items clearly marked as possibly outdated.
  4. Content in a language other than the UI language is displayed unchanged and labelled with its language.
- [CLASSIC] Feed and detail screens.
- [AGENT] "What's new?" returns the same set via `list_announcements` (acting as the user); summaries carry the announcement id and a link to the original; counts and dates come from the tool.

**FR-ANN-004 (C) Withdraw a published announcement**
- Outcome AC
  1. Only the original author or another Publisher can withdraw; status becomes `withdrawn`; it disappears from every feed and agent result.
  2. Withdraw requires confirmation and is idempotent. Retention treatment of withdrawn items is open (U-05).
- [CLASSIC] "Withdraw" action on detail for Publishers with confirmation dialog.
- [AGENT] Agent proposes withdrawal; confirm card; same tool-side rules.

**FR-ANN-005 (M) Announcement content is inert data**
- Outcome AC
  1. Text inside an announcement (including text that looks like instructions to an assistant) never triggers a tool call, a state change, a disclosure of other users' data, or a change in agent behaviour.
  2. Rendering is plain/safe text: no script, no remote content loading, links shown and opened only on user tap.
  3. Agent summaries and answers may quote the content but do not follow it.
- [CLASSIC] Safe rendering (plain text / restricted markup), no automatic link or image fetching.
- [AGENT] Tool results are delimited as untrusted data in instructions; an injection eval set is part of CI (see test-cases).

### FR-VAC: Vacation

Domain rules (single source: `api/`; both modes consume them; parameters configurable, values marked HR-CONFIRM):
- R1 Entitlement: flat **25 days per calendar year** per employee (placeholder, HR-CONFIRM). Whole days only (half-days: assumption A-03).
- R2 Carry-over: unused remaining days carry over **without limit** (HR-CONFIRM, legal check open, U-01).
- R3 Remaining = entitlement(current year) + carried-over - approved - pending. Pending requests reserve days.
- R4 Counted days = Monday-Friday days in range that are not public/cantonal holidays of the employee's work canton (assumption A-04, HR-CONFIRM).
- R5 Reject `INSUFFICIENT_BALANCE` if counted days > remaining at the time of request and again at approval.
- R6 Reject `OVERLAP` if any date overlaps the same employee's pending or approved request.
- R7 Reject `BLACKOUT` if any date falls into an active blackout range applying to the employee (scope all/region/store). Default: no blackouts; ranges are configuration (no admin UI in PoC).
- R8 Reject `PAST_DATE` if start date is before today (Europe/Zurich); `INVALID_RANGE` if end < start; `ZERO_DAYS` if counted days = 0.
- R9 Requests crossing a calendar year are split per year for balance purposes.
- R10 Approver is the employee's direct manager; manager's own requests are approved by the CEO; nobody approves their own request (`SELF_APPROVAL`); no delegation in the PoC.
- R11 State machine: `pending -> approved | rejected | cancelled`; `approved -> cancelled` only by the employee before start date (C, open U-02). Terminal states are final.

**FR-VAC-001 (M) See my vacation balance**
- Outcome AC
  1. The user sees entitlement, carried-over, approved, pending and remaining days for the current year, computed by R1-R3 and consistent with the request list.
  2. The balance is current to the last write; after a submit/approve/reject/cancel it reflects the change on next view without manual refresh.
  3. No other user's balance is returned (managers see only direct reports' via FR-VAC-005).
- [CLASSIC] Overview screen shows the five numbers on load.
- [AGENT] "How many days do I have left?" calls `get_balance`; the agent never states a number it did not receive from a tool in this turn.

**FR-VAC-002 (M) Request vacation**
- Outcome AC
  1. After the user confirms valid dates, exactly one request exists: `pending`, owned by the user, assigned to their approver, with start, end, counted days (R4) and per-year split, and the remaining balance decreases by counted days (R3).
  2. Invalid requests create nothing and return one stable reason code (R5-R8). If several rules fail, the code precedence is `INVALID_RANGE`, `PAST_DATE`, `ZERO_DAYS`, `BLACKOUT`, `OVERLAP`, `INSUFFICIENT_BALANCE`, and all failing codes are listed.
  3. Before confirmation the user is shown: counted days, excluded holidays/weekends, remaining balance after submission.
  4. Submission is idempotent (double tap / retry creates one request).
  5. The approver sees the request in their inbox.
- [CLASSIC] Date range picker -> review screen (counted days, excluded days, balance after) -> "Submit".
- [AGENT] Agent extracts dates, calls `propose_vacation_request` (dry-run through the same validation), shows confirm card with the same review content; submission via `create_vacation_request(token)`. On a rejected proposal the agent reports the tool's reason code in plain language and offers valid alternatives only from tool results.

**FR-VAC-003 (S) Cancel my pending request**
- Outcome AC
  1. The owner can cancel a `pending` request; status `cancelled`, reserved days are released, the approver's inbox entry disappears.
  2. Cancelling a non-pending request returns `INVALID_STATE` (approved-cancellation is C, U-02).
  3. Requires confirmation; idempotent.
- [CLASSIC] "Cancel request" on detail with confirmation dialog.
- [AGENT] Propose -> confirm card -> `cancel_vacation_request(token)`.

**FR-VAC-004 (M) Approve or reject a request**
- Outcome AC
  1. Only the assigned approver (R10) can decide a `pending` request; approving sets `approved`, keeps days deducted; rejecting sets `rejected` with optional reason (<= 500 chars) and releases days.
  2. Balance is re-validated at approval (R5, R6, R7); if now invalid, approval returns the reason code and the request stays `pending`.
  3. Deciding is final and idempotent; a second decision returns `INVALID_STATE`.
  4. The employee sees the new status and reason on next view; the notification setting (retention hook) is honoured.
  5. Non-approvers get `FORBIDDEN`; self-approval returns `SELF_APPROVAL`; no data of other teams is returned.
- [CLASSIC] Manager inbox -> detail (dates, counted days, balance, coverage overlap) -> Approve / Reject.
- [AGENT] "What needs my approval?" lists via tool; "approve Anna's request" -> agent resolves a unique request (asks if ambiguous) -> confirm card -> `decide_vacation_request(token)`.

**FR-VAC-005 (S) Team coverage for managers**
- Outcome AC
  1. A manager sees, for a chosen date range (default: next 4 weeks), which direct reports have approved or pending absences per day, and the count of present vs total.
  2. Only direct reports are included; employees (non-managers) get `FORBIDDEN`. Sick leave/health data never appears (out of scope).
  3. Coverage is computed from the same request data as FR-VAC-002/004, shown in the approval detail for the requested dates.
- [CLASSIC] Team coverage screen (calendar/list) and overlap strip in request detail.
- [AGENT] "Who is out in the week of 9 Nov?" via `get_team_coverage`; answers only from the tool result.

**FR-VAC-006 (M) Cantonal and public holidays**
- Outcome AC
  1. Holidays for all 26 cantons are available as seed data (marked HUMAN_CONFIRMATION_REQUIRED) with canton, date, name per language where available, and whether the full day is a holiday.
  2. Counted days (R4) use the employee's work canton; the review step lists the excluded holiday names.
  3. A user can view the holidays of their own canton for the year.
  4. Changing an employee's canton does not alter already `approved` requests.
- [CLASSIC] Holidays list/section on the overview and a marker in the date picker.
- [AGENT] "Is 11 Nov a holiday for me?" via `get_holidays`; the agent does not answer from model memory.

**FR-VAC-007 (M) Request history and status**
- Outcome AC
  1. A user sees all own requests (current and previous year) with status, dates, counted days, decision date, rejection reason.
  2. The list ordering and statuses match what the manager sees.
- [CLASSIC] "My requests" screen.
- [AGENT] "What's the status of my November request?" via `list_vacation_requests`.

### FR-BRF: Weekly briefing (optional)

**FR-BRF-001 (M) Opt in and out**
- Outcome AC
  1. Briefing is off by default for everyone. No Work IQ call is made for a user who has not opted in.
  2. Opt-in requires an explicit action that names what is accessed ("your calendar for the coming week") and triggers the Work IQ consent flow if needed (FR-AUTH-004).
  3. Opt-out takes effect immediately: no further Work IQ calls, scheduled local notification removed, stored briefing data (if any) deleted.
  4. The current opt-in state is visible and changeable in Settings.
- [CLASSIC] Opt-in screen and settings toggle.
- [AGENT] Agent explains and offers opt-in; the toggle itself is a confirm card (a write).

**FR-BRF-002 (M) Weekly briefing from my own calendar**
- Outcome AC
  1. For an opted-in user, the briefing for the week starting on the most recent Monday 00:00 Europe/Zurich (or the coming Monday when requested on Saturday/Sunday) lists the user's calendar events for that week from Work IQ, grouped by day: title, start/end (Europe/Zurich), location/online flag, number of attendees.
  2. The set of events in the briefing equals the set Work IQ returns for the user for that window; none omitted, none invented. Conflicts (overlaps) and free blocks >= 60 minutes (proposed) are flagged from the same data.
  3. Data comes only from the signed-in user's delegated token; the briefing never contains another user's calendar content beyond what the user's own events already show (attendee names as present in the user's own events).
  4. Calendar text (titles, descriptions, attendee notes) is data; instructions inside it are never followed (see FR-ANN-005 pattern).
  5. Generated within a time budget (NFR-005) or shows an explicit "still working" state.
- [CLASSIC] Briefing screen rendered by deterministic formatting of Work IQ results through `api/` (no LLM required for correctness).
- [AGENT] "Brief me on my week" -> `get_my_week` tool -> conversational summary that includes every event or states how many were omitted for brevity with a link to the full list.

**FR-BRF-003 (S) Monday 07:00 reminder**
- Outcome AC
  1. If opted in and notifications are allowed, a local notification is scheduled for Monday 07:00 Europe/Zurich weekly (follows DST), text "Your week is ready" only, localised, no calendar content.
  2. Tapping it opens the briefing, which is generated at that moment (FR-BRF-002).
  3. Opt-out or sign-out cancels it.
- [CLASSIC] Local notification via settings.
- [AGENT] Same notification; tap opens the briefing conversation.

**FR-BRF-004 (M) Own calendar only**
- Outcome AC
  1. Any request for another person's calendar, availability, or meetings (by name, email, "my boss", "the CEO", "Anna") is declined with an explanation that the briefing covers only the user's own calendar; no tool call fetches other users' calendar data.
  2. The decline does not confirm or deny whether the named person has meetings.
  3. Questions about the user's own meetings that include other attendees may be answered from the user's own events only.
- [CLASSIC] No UI path to select another user.
- [AGENT] Tool surface has no user parameter; instructions plus eval cover natural-language attempts and injection from calendar items.

**FR-BRF-005 (M) Degraded and failure states**
- Outcome AC
  1. If Work IQ is unavailable, consent is missing/revoked, the user has no licence, or the token cannot be refreshed, the user sees a specific actionable message and no briefing content; nothing is fabricated or served from another user's data.
  2. Empty calendar produces an explicit "no events this week" briefing, not an error.
  3. Partial results are labelled as partial.
- [CLASSIC] Error states in the matrix.
- [AGENT] Agent reports the same condition using the tool's error code.

### FR-AUTH: Identity and authorisation

**FR-AUTH-001 (M) Sign in with Entra ID**
- Outcome AC: A user of the demo tenant signs in via MSAL and lands in the app with their identity; non-tenant accounts and disabled accounts cannot sign in; tokens are stored only in the Keychain.
- [CLASSIC] and [AGENT]: same sign-in; the agent surface is unreachable when signed out.

**FR-AUTH-002 (M) Role-based capabilities**
- Outcome AC: Capabilities are derived from Entra app roles validated in `api/` (issuer, audience, signature, expiry, roles). The UI hides unavailable actions, but the API denies them (`FORBIDDEN`) regardless of UI. REST endpoints and MCP tools use the same authorisation functions.
- [CLASSIC] REST authorisation; [AGENT] MCP tools authorise as the calling user, and the agent cannot perform a role action the user cannot.

**FR-AUTH-003 (M) Agent acts as the calling user**
- Outcome AC: Every tool call carries the end user's identity; no tool uses app-only credentials for user data; audit records contain user id, tool name, outcome, correlation id (no content).
- [CLASSIC] N/A for tool calls, REST uses the same identity. [AGENT] enforced at the MCP server.

**FR-AUTH-004 (M) Work IQ via user-delegated flow**
- Outcome AC: Work IQ is called only through on-behalf-of with the user's delegated token and only after the user opted in; consent missing -> interactive consent prompt; no app-only Work IQ call exists; no other user's Work IQ output is cached or reused.
- [CLASSIC] and [AGENT]: same OBO path in `api/`.

**FR-AUTH-005 (M) Session expiry and sign-out**
- Outcome AC: Expired/revoked tokens lead to silent refresh or, if impossible, a re-sign-in prompt that preserves unsent drafts locally (non-sensitive fields only) and never sends a write with a stale token; sign-out clears tokens, cached data, scheduled notifications and agent conversation state on device.
- [CLASSIC] and [AGENT]: same.

**FR-AUTH-006 (M) Explicit confirmation for every write**
- Outcome AC
  1. A write is executed only with a `confirmation_token` that is: issued only by the app after an explicit user action on a review/confirm UI, bound to user id, action type and a hash of the exact payload, single-use, and short-lived (TTL proposed 5 minutes, configurable).
  2. Missing, expired, reused, tampered (payload changed), or other-user tokens are rejected: `CONFIRMATION_REQUIRED` / `INVALID_CONFIRMATION`; no state change.
  3. What is confirmed is what is executed: the confirm card/review screen shows the payload hash source.
  4. Agents cannot mint tokens; user text such as "yes, go ahead" in chat is not a confirmation.
- [CLASSIC] The review screen's submit action requests a token from the same endpoint (uniform enforcement). [AGENT] confirm card.

## 5. Non-functional requirements

| ID | Pri | Requirement (testable) |
|---|---|---|
| NFR-001 | M | Azure resources in Switzerland North where the service is available there; each exception (e.g. a Foundry model or hosted-agent region) is recorded in an ADR with data-flow impact. Verified by IaC check. |
| NFR-002 | M | Whole system deployable with `azd` (infra via Bicep); no manual portal steps except human-only actions listed in `Claude.md`. |
| NFR-003 | M | iOS 17.0+; Swift 6 strict concurrency clean; no third-party analytics SDKs. |
| NFR-004 | S | Packaged for Custom App distribution via Apple Business Manager (or TestFlight); no public App Store listing. |
| NFR-005 | M | Proposed targets (HUMAN_CONFIRMATION_REQUIRED): REST p95 < 800 ms server time for reads, < 1.5 s writes; agent first visible token p95 < 4 s; briefing first content p95 < 15 s. Measured in dev with the seeded 11 users and recorded via EXP events. |
| NFR-006 | M | Cost per task (tokens and tool calls for AGENT; infra apportioned for CLASSIC) is computed for every task flow (EXP-005). |
| NFR-007 | M | Offline: cached read data is shown with an "as of" time; writes are never queued silently; the user sees "needs connection" and the draft is kept locally. |
| NFR-008 | M | Parity guard: a shared contract test suite runs each FR scenario against the REST path and the MCP tool path and asserts identical outcomes and error codes. |
| NFR-009 | M | Localisation: all UI strings in DE, FR, IT, EN via String Catalog; no hard-coded user-visible strings; dates/numbers by locale; agent replies in the user's UI language unless asked otherwise. |
| NFR-010 | M | Time handling: all business-day logic in Europe/Zurich including DST changes; tests cover the DST switch weeks. |
| NFR-011 | M | Rate limits and payload size limits on REST and agent endpoints (values set in Phase 2) to bound abuse and cost. |
| NFR-012 | M | Observability without personal data: structured logs with correlation ids; no tokens, calendar content, announcement bodies or vacation reasons in logs. |
| NFR-013 | S | Agent safety evals (adversarial set) are part of `./scripts/ci-check.sh` with pass thresholds (set in Phase 6). |
| NFR-014 | M | Secrets only in Key Vault via managed identity; none in code, plist, `azure.yaml`, Bicep outputs or logs. |

## 6. Accessibility

| ID | Pri | Requirement |
|---|---|---|
| A11Y-001 | M | Every interactive element has a VoiceOver label, role/traits and a logical focus order; confirm cards and sheets move focus on appear and announce results. |
| A11Y-002 | M | Dynamic Type up to the largest accessibility sizes without truncated critical content or overlapping controls; layouts reflow. |
| A11Y-003 | M | Contrast meets WCAG 2.2 AA (4.5:1 text, 3:1 UI) in light and dark; information is never conveyed by colour alone (status chips have text/icons). |
| A11Y-004 | M | Respect Reduce Motion, Bold Text, Increase Contrast and Reduce Transparency. |
| A11Y-005 | M | Touch targets >= 44x44 pt; every flow completable without drag or timed gestures; date selection has a non-calendar alternative (text entry/steppers). |
| A11Y-006 | M | Agent/chat: responses are exposed to VoiceOver as they complete (not char-by-char), the confirm action is reachable by VoiceOver and keyboard, and voice input uses the system keyboard dictation (no custom speech). |
| A11Y-007 | S | Localised accessibility labels and the same quality in DE/FR/IT/EN; no accessibility claims in release metadata beyond what is verified (Accessibility Nutrition Label data from tests). |

## 7. Privacy

| ID | Pri | Requirement |
|---|---|---|
| PRIV-001 | M | Data minimisation: only data listed in `docs/privacy/data-inventory.yml` is processed; adding a field requires updating the inventory in the same PR. |
| PRIV-002 | M | No sick leave, health, payroll or reason-for-absence data is collected, stored, or sent to agents; vacation requests have no free-text reason from the employee (rejection reasons from the manager are allowed, <= 500 chars, and flagged as personal data). |
| PRIV-003 | M | Work IQ output is user-delegated, used only to serve the requesting user, never cached across users, never written to logs, and, by default, not persisted after the response (assumption A-09, retention TBD). |
| PRIV-004 | M | Retention is a configurable TTL per data class with a deletion job and an owner; no default period is claimed (HUMAN_CONFIRMATION_REQUIRED, U-05). Agent transcripts and briefing output are not persisted by default. |
| PRIV-005 | M | Agent boundary: the agent receives only data returned by tools for the calling user; no bulk exports; per-tool minimal fields; tool results containing third-party text are marked untrusted. |
| PRIV-006 | M | Data subject rights are supportable: the data of one user can be exported and deleted by id across Cosmos, logs and experiment events (process owner open). |
| PRIV-007 | M | Experiment events are pseudonymous (random per-participant id, mapping kept separately and deletable), contain no content (no announcement text, calendar items, prompts). |
| PRIV-008 | M | No cross-user leakage: audience, manager, role and ownership checks are enforced server-side on every read; tests cover horizontal access (employee A reading employee B). |
| PRIV-009 | M | `PrivacyInfo.xcprivacy` and App Store privacy answers are derived from the data inventory; unknown items are marked HUMAN_CONFIRMATION_REQUIRED, not guessed. |
| PRIV-010 | S | Logging and crash reports exclude tokens, calendar content, announcement bodies and prompts; screenshots of sensitive screens are blanked in the app switcher. |

## 8. Experiment

| ID | Pri | Requirement |
|---|---|---|
| EXP-001 | M | Each task flow emits `task_started` and exactly one of `task_completed` / `task_abandoned` with `mode`, `task_id`, `feature`, per `docs/experiment/metrics.md`. |
| EXP-002 | M | Tap count and elapsed time per task are captured on-device (CLASSIC: taps; AGENT: taps + messages typed/spoken counts, no text content). |
| EXP-003 | M | Errors are captured as `task_error` with a code (domain reason codes, agent tool failures, validation errors) and whether the user recovered. |
| EXP-004 | M | Mode assignment is explicit and recorded per participant and task (within-subject, counterbalanced order); the app can force a mode for a session via a non-production setting that is compiled out of Release or protected by a role. |
| EXP-005 | M | Cost per task: tokens in/out, model id, tool-call count and latency are recorded server-side for AGENT; CLASSIC records API call count and latency; correlated by `task_run_id`. |
| EXP-006 | S | Post-task satisfaction (single 1-5 item, plus optional comment not stored with identity) and a post-session comparison item. |
| EXP-007 | M | Events follow PRIV-007; collection is disclosed to participants; a participant can withdraw and have events deleted. |

## 9. Out of scope (this PoC)

Sick leave and health data, payroll, Android, Teams client (brief). Additionally (decided here, change by
asking): admin UI for blackouts/holidays/entitlements, delegation of approvals, half-day requests
(A-03), machine translation of announcements, rich media in announcements, peer visibility of absences,
unattended server-side briefing generation, HR second approval step.

## 10. Traceability

Each ID above is covered in `docs/product/test-cases.md` (traceability table at the end). A check script
(Phase 0 `scripts/ci-check.sh` extension, to be added in the first slice) must fail if an ID has no test.
