# DPIA notes

Status: working notes for the human's DPIA. Controller, legal basis and sign-off: HUMAN_CONFIRMATION_REQUIRED.

## AGENT mode, announcements (phase 6)
- Data sent to Foundry and the model per turn: the user's chat messages and history (held on the device, sent each
  turn with `store:false`), tool results for that user (announcement titles and bodies addressed to them), and for a
  Communicator the draft they are preparing. Never sent: tokens of the user, other users' data, bulk exports.
- Not persisted by the app (PRIV-004, A-09). Foundry thread state is not used (`store:false`). The API keeps
  content-free records only: audit lines (oid, tool, outcome, correlation id) and `agent_run` counts (model id, token
  counts, tool-call count, latency).
- Processors: Microsoft Foundry and the model provider. Model region and the EU Data Zone question (U-09,
  overview.md section 3) are open and need a decision plus a privacy-statement update before any real data.
- Evals use synthetic data only (`evals/comms`); live evals need persona tokens that stay in the human's shell.
- Data subject rights (PRIV-006) are unchanged: nothing agent-specific is stored beyond the audit and run records.
