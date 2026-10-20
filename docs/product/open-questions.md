# Open questions, decisions and assumptions (Phase 1)

Owner of answers: human (product/HR/legal). Nothing here is HR, legal or retention policy unless the
human states it; values marked HR-CONFIRM are placeholders.

## Decisions (answered in the /discover session)

| ID | Topic | Decision | Status |
|---|---|---|---|
| D-01 | Entitlement | Flat 25 days per year for all employees | Placeholder, HR-CONFIRM |
| D-02 | Carry-over | Unlimited carry-over; balance accumulates | Placeholder, HR-CONFIRM, legal check |
| D-03 | Approval chain | Direct manager only; manager/CEO requests approved by CEO; no delegation | Decided for PoC |
| D-04 | Blackouts | None by default; configurable date ranges (scope all/region/store); seeded one for tests | Decided |
| D-05 | Cantons | All 26 cantons for holidays | Decided; data HUMAN_CONFIRMATION_REQUIRED |
| D-06 | Audiences | All, plus region, store, role targeting | Decided (All = Must; targeting = Should) |
| D-07 | Briefing schedule | Opt-in; Monday 07:00 Europe/Zurich; generated at open (delegated token) | Decided; see U-03 |
| D-08 | Retention | Unknown; must be configurable; no period asserted | Open (U-05) |
| D-09 | Languages | DE/FR/IT/EN per brief (not asked in session) | Confirm |

## Assumptions (with risk)

| ID | Assumption | Risk if wrong | Mitigation |
|---|---|---|---|
| A-01 | Entitlement is per calendar year, same for everyone, independent of canton, age, part-time | Real policy has tiers or pro-rata, balances wrong | Engine parameterised per employee; seed value only |
| A-02 | Carry-over has no expiry or cap | Swiss law/contract may require limits; unlimited is a liability statement | Flag to HR; config field `carry_over_cap` nullable |
| A-03 | Whole days only; no half-days | Retail staff often take half days | Add as later requirement; data model stores `day_fraction` ready (Phase 2 decision) |
| A-04 | Counted days = Mon-Fri minus holidays of the employee's work canton; no Saturday work schedules, no part-time working patterns | Store staff with Sat/Sun schedules get wrong counts | Make working-week pattern a per-employee parameter in Phase 2 |
| A-05 | A holiday is a full day; half-day or municipal holidays are not modelled | Wrong counts around e.g. local holidays | Seed table has `scope` field; confirm with HR |
| A-06 | Carry-over for the first PoC year is seeded per employee (e.g. 0) | Demo data unrealistic | seed-demo.sh sets values explicitly |
| A-07 | Announcements are authored per language by the publisher; each has one `language`; no automatic translation | CEO must write 4 versions or readers get foreign-language text | Show language label; consider multi-language announcement later |
| A-08 | Late joiners (employees added after publish) do not see earlier targeted announcements | Gaps in communication | Decide per U-02 |
| A-09 | Briefing output and agent transcripts are not stored server-side by default | Cannot audit agent behaviour after the fact; eval data limited | Store only metadata/tool-call logs without content; opt-in debug capture in dev only |
| A-10 | One tenant (demo) and 11 seeded users: results are exploratory, not statistically conclusive | Over-claiming | Report effect sizes and CIs as exploratory (hypotheses.md) |
| A-11 | Publisher role can be held by more than one user (CEO + Comms) | Role mapping in demo tenant has only one | Demo uses CEO only |
| A-12 | Manager, work canton, store, region, language are available as Entra attributes or from a seeded directory file | If missing, targeting and approver routing cannot be derived | Seed file mapped by `oid`; decision in Phase 2 ADR |
| A-13 | The confirm card is rendered natively by the app from a structured proposal, not by model-generated UI | If agent hosting forces rendering in text, confirmation can be spoofed | Enforce in Phase 2/6 |
| A-14 | Employees cannot see each other's absences | Real teams may expect shared calendars | Manager coverage only (U-10) |
| A-15 | Push notifications for announcements and decisions use APNs via Azure (Notification Hubs or direct) | Extra infra, privacy surface | Retention hooks are opt-in and optional; can be local-only polling in PoC |

## Unknowns (ranked by impact; see requirements.md section 3)

| ID | Question | Why it matters | Needed by | Proposed way to resolve |
|---|---|---|---|---|
| U-03 | What is the exact Work IQ API surface for a custom iOS app, is it available and licensed in `m365cpi55218196.onmicrosoft.com`, which delegated scopes does it need, can it return calendar events for a time window? | Core PoC goal (1). FR-BRF-* may be infeasible or need a Graph fallback | Phase 2 spike | Human checks tenant licences and consent; check microsoft-learn MCP; record in ADR. If unavailable, decide: Graph Calendar delegated as fallback (changes the PoC claim). **Status: spike prepared, awaiting human run of `docs/architecture/spikes/u03/`; see ADR-011** |
| U-01 | HR rules: weekend/part-time/half-day, holiday counting, entitlement rules, carry-over legality, treatment on leaving | Domain engine correctness | Before Phase 4 | HR review of rules R1-R11 |
| U-05 | Retention periods and deletion duties per data class; who is controller; DPIA needed? | Privacy, Cosmos TTL, App Store privacy answers | Before Phase 3 | Human with legal/DPO |
| U-04 | Authoritative source and update process for cantonal/public holidays; what about half-days and municipal holidays? | 26-canton table accuracy | Before Phase 4 | Human supplies a vetted table or accepts a seed marked demo-only |
| U-06 | Should announcements be multilingual (one record, 4 texts)? | Data model, FR-ANN-001 | Phase 2 | Human decision |
| U-07 | Which org attributes exist in Entra for the 11 seeded users (manager, officeLocation/state, department, extension attributes)? | Audience, approval routing | Phase 2 | Human exports a non-secret user attribute list to `/Users/Shared/handoff/` |
| U-08 | ABM Custom App: Apple Developer organisation, DUNS, reviewer account without MFA, region availability (Switzerland) | Distribution | Phase 11 | Human |
| U-09 | Are Foundry hosted agents, the chosen model and Cosmos available in Switzerland North? Is data processed outside CH (model inference)? | NFR-001, privacy statement | Phase 2 | microsoft-learn MCP + human confirms subscription; ADR for any deviation |
| U-02 | Announcement edit/withdraw semantics, read receipts, acknowledgements, and whether approved vacation can be cancelled by the employee | Scope of FR-ANN-004, FR-VAC-003 | Phase 4 | Human decision |
| U-10 | Visibility of peers' absence to employees | Privacy, FR-VAC-005 | Phase 4 | Human decision |
| U-11 | Who may configure blackouts and holidays, and how (no admin UI in PoC): seed file, API with admin role? | Operability | Phase 3 | Human decision |
| U-12 | Is the CEO's own vacation approved by someone (board chair)? Seeded CEO has no manager | R10 edge case | Phase 4 | Assumed: CEO requests auto-route to no approver and are rejected with `NO_APPROVER`; confirm |
| U-13 | Acceptable agent cost and latency (are NFR-005 targets right?) | Experiment success criteria | Phase 6 | Human sets budget |
| U-14 | Participant consent and works-council/employee-representation involvement for the experiment | Legal/ethical | Before experiment | Human |

## Questions asked in the session (10 maximum)

Asked in three rounds (10 individual questions total): entitlement, carry-over, approval chain, blackouts
and cantons (blackouts answered, cantons answered "all 26"), flat days number, audiences (first answer
"All employees" only, then reconciled to follow the brief), briefing schedule, retention, targeting scope.
Not asked, assumed: languages (D-09), half-days (A-03), weekend rule (A-04).
