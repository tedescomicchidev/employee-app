"""FR-VAC-001..007 AGENT path: the vacation agent through POST /v1/agent/vacation/turns.

Confirm cards come from the stored proposal (A-13), the confirmation reaches the agent with the
stored draft, and a reply that claims a write is believed only after the tool succeeded.
"""

import json
from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.agents.foundry import AgentSettings
from tests.mcp_harness import CEO, EMP1, MGR2
from tests.test_agent_turn import CONFIGURED, PROPOSAL, FakeFoundry, FakeTools, reply
from tests.test_mcp_vacation import MGR1, VacEnv

RANGE = {"start": "2026-11-23", "end": "2026-11-25"}
TOKEN = "t" * 43


@pytest.fixture
def env(private_key: Any) -> Iterator[VacEnv]:
    tools, foundry = FakeTools(), FakeFoundry()
    env = VacEnv(
        private_key,
        agent_settings=CONFIGURED,
        tools_token_client=tools,
        agent_responder=foundry,
    )
    env.foundry = foundry  # type: ignore[attr-defined]
    with TestClient(env.app) as client:
        env.client = client
        yield env


def turn(
    env: VacEnv, who: str, confirmation: dict[str, str] | None = None, agent: str = "vacation"
):
    body: dict[str, Any] = {"messages": [{"role": "user", "content": "ok"}]}
    if confirmation:
        body["confirmation"] = confirmation
    roles = ("Manager", "Employee") if who in (CEO, MGR1, MGR2) else ("Employee",)
    assert env.client is not None
    return env.client.post(f"/v1/agent/{agent}/turns", json=body, headers=env.user(who, *roles))


def card(env: VacEnv, who: str, proposal_id: str) -> Any:
    roles = ("Manager", "Employee") if who in (CEO, MGR1, MGR2) else ("Employee",)
    assert env.client is not None
    return env.client.get(f"/v1/proposals/{proposal_id}", headers=env.user(who, *roles))


def test_vacation_is_a_registered_agent() -> None:
    assert AgentSettings().agents["vacation"] == "vacation"


def test_vacation_confirm_card_is_server_rendered_and_owner_only(env: VacEnv) -> None:
    """FR-VAC-002 @api: dates, days and balance on the card come from the stored proposal."""
    _, proposal = env.tool(EMP1, "propose_vacation_request", RANGE)
    shown = card(env, EMP1, proposal["proposal_id"])
    assert shown.status_code == 200
    body = shown.json()
    assert body["type"] == "vacation" and body["payload"] == RANGE
    assert body["review"] == proposal["review"]
    assert card(env, EMP1, proposal["proposal_id"]).json() == body  # stable
    # Not the owner: the same answer as an unknown id (here the announcement lookup's 403).
    other = card(env, "00000000-0000-0000-0000-000000000012", proposal["proposal_id"])
    assert other.status_code == 403


def test_vacation_cancel_and_decision_cards_show_the_request(env: VacEnv) -> None:
    """FR-VAC-003/004 @api: the card is the request itself, for its owner or its approver."""
    request = env.book(EMP1, RANGE["start"], RANGE["end"])
    _, cancel = env.tool(EMP1, "propose_cancel", {"request_id": request["id"]})
    shown = card(env, EMP1, cancel["proposal_id"]).json()
    assert shown["type"] == "vacation_cancel" and shown["request"]["id"] == request["id"]
    _, decision = env.tool(
        MGR1, "propose_decision", {"request_id": request["id"], "decision": "approve"}
    )
    shown = card(env, MGR1, decision["proposal_id"]).json()
    assert shown["type"] == "vacation_decision" and shown["payload"]["decision"] == "approve"
    assert card(env, EMP1, decision["proposal_id"]).status_code == 403  # not the approver's card


def test_vacation_confirmation_reaches_the_agent_with_the_stored_draft(env: VacEnv) -> None:
    """FR-AUTH-006 @api: what the agent submits is exactly what the user confirmed."""
    _, proposal = env.tool(EMP1, "propose_vacation_request", RANGE)
    good = {"proposal_id": proposal["proposal_id"], "confirmation_token": TOKEN}
    assert turn(env, EMP1, good).status_code == 200
    (call,) = env.foundry.calls  # type: ignore[attr-defined]
    sent = call["messages"][-1]["content"]
    assert call["agent"] == "vacation" and f"confirmation_token={TOKEN}" in sent
    assert json.dumps("2026-11-25") in sent
    assert turn(env, MGR1, good).status_code == 404  # someone else's proposal
    assert turn(env, EMP1, {**good, "proposal_id": PROPOSAL}).status_code == 404
    assert len(env.foundry.calls) == 1  # type: ignore[attr-defined]


def test_an_announcement_proposal_cannot_be_confirmed_to_the_vacation_agent(env: VacEnv) -> None:
    draft = {"title": "T", "body": "B", "language": "en", "audience": "all"}
    _, proposed = env.call(
        env.tools_token(CEO, "Communicator", "Employee"), "propose_announcement", draft
    )
    confirmation = {"proposal_id": proposed["proposal_id"], "confirmation_token": TOKEN}
    assert turn(env, CEO, confirmation).status_code == 404
    assert env.foundry.calls == []  # type: ignore[attr-defined]


@pytest.mark.parametrize(
    ("kind", "tool"),
    [
        ("submitted", "create_vacation_request"),
        ("cancelled", "cancel_vacation_request"),
        ("decided", "decide_vacation_request"),
    ],
)
def test_a_claimed_write_is_only_believed_after_the_tool_succeeded(
    env: VacEnv, kind: str, tool: str
) -> None:
    """FR-VAC-002/003/004 @agent-eval: the reply cannot say 'done' if nothing was written."""
    claim = {"kind": kind, "text": "Done"}
    foundry: FakeFoundry = env.foundry  # type: ignore[attr-defined]
    foundry.response = reply(claim)
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"
    failed = {"type": "mcp_call", "name": tool, "error": "INVALID_CONFIRMATION"}
    foundry.response = reply(claim, [failed])
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"
    other = {
        "type": "mcp_call",
        "name": "create_vacation_request"
        if tool != "create_vacation_request"
        else "propose_cancel",
        "error": None,
    }
    foundry.response = reply(claim, [other])
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"  # a different tool is no proof
    ok = {"type": "mcp_call", "name": tool, "error": None}
    foundry.response = reply(claim, [ok])
    assert turn(env, EMP1).json()["reply"]["kind"] == kind


def test_vacation_reply_shapes(env: VacEnv) -> None:
    """FR-VAC-002 @agent-eval: proposals and options carry ids and dates, never numbers."""
    foundry: FakeFoundry = env.foundry  # type: ignore[attr-defined]
    foundry.response = reply({"kind": "proposal", "text": "Review", "proposal_id": PROPOSAL})
    assert turn(env, EMP1).json()["reply"]["proposal_id"] == PROPOSAL
    foundry.response = reply({"kind": "proposal", "text": "no id"})
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"
    options = [{"proposal_id": PROPOSAL, "start": "2026-11-23", "end": "2026-11-25", "days": 99}]
    foundry.response = reply({"kind": "options", "text": "Two choices", "options": options})
    (option,) = turn(env, EMP1).json()["reply"]["options"]
    assert option == {"proposal_id": PROPOSAL, "start": "2026-11-23", "end": "2026-11-25"}
    foundry.response = reply({"kind": "options", "text": "none", "options": []})
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"
    foundry.response = reply({"kind": "published", "text": "comms kind"})
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"  # not a vacation kind
