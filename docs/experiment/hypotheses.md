# Hypotheses

Intent (brief): prove that Foundry agents let employees reach the same outcomes faster than classic
forms/feeds. The "Phase 9" document was not available when this was written; protocol, analysis plan and
thresholds are therefore proposals to be reconciled with `docs/experiment/protocol.md` and
`analysis.md` (HUMAN_CONFIRMATION_REQUIRED).

## Design
- Within-subject crossover: each participant performs each task in CLASSIC and AGENT mode, order
  counterbalanced (Latin square by participant id).
- Population: 11 seeded users (1 CEO, 2 managers, 8 employees). Publish and approve tasks have n = 1 and
  n = 2 participants respectively: those results are descriptive only.
- Equal outcomes are a precondition: a task counts only if the persisted end state satisfies the shared
  Outcome AC of the FR (FR-ANN-001, FR-VAC-002, FR-VAC-004, ...). Parity is checked by the NFR-008 suite.
- Thresholds below are proposals (HUMAN_CONFIRMATION_REQUIRED). Report medians, effect sizes and
  confidence intervals; do not claim statistical significance at this sample size (A-10).

## Tasks
| Task id | Feature | Participants | Outcome checked |
|---|---|---|---|
| T-ANN-PUB | FR-ANN-001/002 | CEO | announcement published to a given audience |
| T-ANN-READ | FR-ANN-003 | 8 employees | find the announcement and answer a content question |
| T-VAC-BAL | FR-VAC-001 | employees | state the remaining balance |
| T-VAC-REQ | FR-VAC-002 | employees | request exists with the given dates |
| T-VAC-REJ | FR-VAC-002 (negative) | employees | understand why a request fails and correct it |
| T-VAC-APR | FR-VAC-004 | managers | given request approved |
| T-VAC-COV | FR-VAC-005 | managers | identify the day with lowest coverage |
| T-BRF-VIEW | FR-BRF-002 | opted-in participants | state the first meeting on Thursday and any conflict |

## Hypotheses
| ID | Statement | Primary metric | Proposed threshold | Falsified if |
|---|---|---|---|---|
| H1 | AGENT reduces median time on task for T-VAC-REQ vs CLASSIC | `elapsed_ms` | >= 20% lower | difference < 0 or CI includes no reduction |
| H2 | AGENT reduces taps for T-VAC-REQ and T-ANN-PUB | `tap_count` | >= 30% lower | no reduction |
| H3 | AGENT does not reduce completion (outcome parity) | completion rate with correct outcome | within 10 points of CLASSIC | AGENT lower by more than 10 points |
| H4 | AGENT does not increase errors that change state (wrong dates, wrong audience) | wrong-outcome rate, `task_error` rate | not higher than CLASSIC | AGENT higher |
| H5 | AGENT is not worse in satisfaction | 1-5 rating | mean difference >= -0.3 | below |
| H6 | AGENT cost per task is bounded | tokens, tool calls, CHF-equivalent per task | within the budget set in U-13 | exceeds |
| H7 | Retrieval-style tasks (T-VAC-BAL, T-ANN-READ, T-BRF-VIEW) are faster with AGENT | `elapsed_ms` | >= 20% lower | no reduction |
| H8 | CLASSIC is faster or equal for T-VAC-APR (two-tap inbox decision) | `elapsed_ms` | AGENT not faster | AGENT faster by >= 20% (then our expectation was wrong) |
| H9 | Agent safety: no unconfirmed write, no cross-user disclosure, no injected action in live sessions | safety counters | zero occurrences | any occurrence |
| H10 | Work IQ works from the custom iOS app for opted-in users (PoC goal 1) | briefing success rate | >= 95% of attempts return content or a defined empty state | below; or U-03 unresolved |

H8 is a deliberate counter-hypothesis so the experiment can show where agents do not help.
