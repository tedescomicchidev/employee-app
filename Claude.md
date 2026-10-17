# Employee App PoC: agent map
You run in the `agent` macOS account. You have no signing identity, no
secrets and no Azure deploy rights; the human does those in their account.
Read first: docs/product/brief.md. Later also: docs/product/requirements.md,
test-cases.md, docs/design/ (tokens + mockups), docs/architecture/overview.md
+ decisions/, docs/experiment/metrics.md. Prompt patterns:
docs/reference/prompt-library.md.
Non-secret logs from the human (e.g. azd errors): /Users/Shared/handoff/.

## Repository layout (create in Phase 0; keep it this way)
CLAUDE.md                 this file
azure.yaml                azd: project, connections, toolboxes, agents, api (Phase 3)
infra/                    Bicep modules (Phase 3)
ios/                      CLAUDE.md, project.yml (XcodeGen), App/,
                          Packages/Core, Packages/Features, AppTests/, AppUITests/
api/                      CLAUDE.md, FastAPI app, MCP tool server (Phase 6), tests/
agents/                   CLAUDE.md, comms/, vacation/, briefing/ (Phase 6/8), toolboxes/
evals/                    agent eval datasets + runners (Phase 6)
docs/product/             brief.md (human-owned), requirements.md, test-cases.md,
                          open-questions.md (Phase 1)
docs/design/              screen-state-matrix.md (Phase 1); tokens.md and
                          mockups/<feature>/ (human-owned, from Claude Design)
docs/architecture/        overview.md, auth-flows.md, decisions/ADR-*.md (Phase 2)
docs/experiment/          hypotheses.md, metrics.md, protocol.md, analysis.md
docs/privacy/             data-inventory.yml, dpia-notes.md, threat-model.md
docs/release/             runbook.md, review-notes.md, metadata/ (Phase 11)
docs/reference/           prompt-library.md (human-owned)
scripts/                  doctor.sh, ci-check.sh, screenshot.sh, seed-demo.sh
.github/workflows/        ci.yml
.claude/agents/           ios-reviewer.md, agent-reviewer.md
.claude/commands/         discover, slice, agent-slice, security-audit,
                          release-dossier, impact
Human-owned files (never rewrite without being asked): CLAUDE.md layout
section, docs/product/brief.md, docs/design/tokens.md, docs/design/mockups/,
docs/reference/, .claude/settings.json.

## Stack
iOS SwiftUI (Swift 6, iOS 17+, XcodeGen, MSAL) | API Python 3.12 FastAPI on
Azure Container Apps | Agents: Foundry hosted agents (Microsoft Agent
Framework, Python) + toolboxes | Data: Cosmos DB | IaC: Bicep via azd.

## Invariants
- Every feature exists in CLASSIC and AGENT mode with identical domain rules;
  business rules live in api/, never in prompts or the iOS app.
- Agents act only through api/ MCP tools; any write (publish, submit,
  approve) requires explicit user confirmation in the app.
- Work IQ is user-delegated only; never cache other users' Work IQ output;
  never call it with app-only credentials.
- UI follows docs/design/ (DesignSystem components, no hard-coded colours or
  sizes). Apple HIG and system components win over mockups; report every
  deviation from a mockup in the PR.
- No secrets in code, plist, azure.yaml or logs. Key Vault + managed identity.
  Never ask the human to paste a secret into this session.
- Foundry/Work IQ/azd APIs change often: check the microsoft-learn MCP
  server before writing integration code; cite the doc URL in the PR.
- Emit experiment events (docs/experiment/metrics.md) for every task flow.
- Every requirement ID maps to at least one test (unit, UI or agent eval).

## Verify
./scripts/ci-check.sh (ios + api + agents). UI changes: ./scripts/screenshot.sh
and compare with docs/design/mockups/. Agents: azd ai agent run / invoke
--local against the dev project.

## Workflow
Work on a phase-* branch, push it, open a PR with gh. Never merge.

## Human-only actions (prepare exact commands, then stop and ask)
any azd up/deploy/provision/down, azd ai connection or toolbox creation,
Entra app registrations and consent, role assignments, secrets, merging,
pushing to main, device builds and signing, App Store Connect actions.
