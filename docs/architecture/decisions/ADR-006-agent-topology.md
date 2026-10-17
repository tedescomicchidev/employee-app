# ADR-006: Agent topology

Status: proposed. Requirements: PRIV-005, EXP-005, NFR-005, NFR-013, FR-BRF-004.

## Context
Option A: three hosted agents (comms, vacation, briefing) sharing toolboxes. Option B: one router agent that
dispatches to sub-behaviours. Toolboxes expose one MCP endpoint with central auth, guardrails and versioning, and can be
reused across agents.

## Decision
Option A, with no router model.
- Agents: `comms`, `vacation`, `briefing` (Microsoft Agent Framework, Python, hosted).
- The app selects the agent from the feature entry point, so routing is deterministic and free.
- Toolboxes over the `api/` MCP server:
  - `core-tools`: announcement and vacation tools, attached to `comms` and `vacation` (each agent's instructions
    limit it to its domain; the role checks in `api/` are the real boundary).
  - `briefing-tools`: `get_briefing_status`, opt-in tools, `get_my_week`, attached only to `briefing`.
- Toolbox consumer endpoint follows the default version, so a tool change is promoted without redeploying agents.
- Conversation state: `store:false`; the app keeps history on device and the gateway resends it (A-09, PRIV-004).
- Each agent has its own eval set and prompt, per `agents/CLAUDE.md`.

## Consequences
- Least privilege: only `briefing` can reach calendar-derived data. Cost and latency are attributable per agent (EXP-005).
- No transcripts persist in Foundry by default. The cost is tokens per turn growing with history, so cap the history.
- A user cannot ask a cross-feature question in one chat ("approve Anna's request and tell everyone"); the app needs a clear feature entry.
- Three container images to build and deploy (azd handles it).
- Hosted agents are billed on CPU/memory during active sessions; check the price page in Phase 3.

## Alternatives
- Router agent: one chat for everything, but adds a model hop (latency, cost), widens each turn's tool set, and
  muddies per-feature measurement. Revisit if participants ask for a single chat.
- Prompt agents instead of hosted agents: simpler, but the brief and stack choose hosted agents.

## Sources
- learn.microsoft.com/azure/foundry/agents/concepts/toolbox-overview
- learn.microsoft.com/azure/foundry/agents/how-to/tools/use-toolbox-hosted-agent
- learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents
