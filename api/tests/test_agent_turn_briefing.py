"""FR-BRF-001, FR-BRF-002, FR-BRF-004, FR-AUTH-006 @api: the briefing agent through
POST /v1/agent/briefing/turns."""

import json
from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.agents.foundry import AgentSettings
from tests.briefing_harness import EMP1, EMP2, BriefEnv
from tests.test_agent_turn import CONFIGURED, PROPOSAL, FakeFoundry, FakeTools, reply

TOKEN = "t" * 43


@pytest.fixture
def env(private_key: Any) -> Iterator[BriefEnv]:
    foundry = FakeFoundry()
    env = BriefEnv(
        private_key,
        agent_settings=CONFIGURED,
        tools_token_client=FakeTools(),
        agent_responder=foundry,
    )
    env.foundry = foundry  # type: ignore[attr-defined]
    with TestClient(env.app) as client:
        env.client = client
        yield env


def turn(env: BriefEnv, who: str, confirmation: dict[str, str] | None = None) -> Any:
    body: dict[str, Any] = {"messages": [{"role": "user", "content": "brief me on my week"}]}
    if confirmation:
        body["confirmation"] = confirmation
    return env.rest(who, "POST", "/v1/agent/briefing/turns", body)


def respond(env: BriefEnv, payload: Any, calls: list[dict[str, Any]] | None = None) -> None:
    env.foundry.response = reply(payload, calls)  # type: ignore[attr-defined]


def test_briefing_is_a_registered_agent() -> None:
    assert AgentSettings().agents["briefing"] == "briefing"


def test_fr_brf_001_the_opt_in_card_comes_from_the_stored_proposal(env: BriefEnv) -> None:
    _, proposal = env.tool(EMP1, "propose_briefing_optin", {"enabled": True})
    respond(
        env, {"kind": "proposal", "text": "Turn it on?", "proposal_id": proposal["proposal_id"]}
    )
    body = turn(env, EMP1).json()["reply"]
    assert body["kind"] == "proposal" and body["proposal_id"] == proposal["proposal_id"]
    # Someone else's proposal id, or an unknown one, is downgraded to a plain message.
    assert turn(env, EMP2).json()["reply"]["kind"] == "message"
    respond(env, {"kind": "proposal", "text": "Turn it on?", "proposal_id": PROPOSAL})
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"


def test_fr_auth_006_confirmation_reaches_the_agent_with_the_stored_draft(env: BriefEnv) -> None:
    _, proposal = env.tool(EMP1, "propose_briefing_optin", {"enabled": True})
    good = {"proposal_id": proposal["proposal_id"], "confirmation_token": TOKEN}
    assert turn(env, EMP1, good).status_code == 200
    (call,) = env.foundry.calls  # type: ignore[attr-defined]
    sent = call["messages"][-1]["content"]
    assert call["agent"] == "briefing" and f"confirmation_token={TOKEN}" in sent
    assert json.dumps({"enabled": True}, sort_keys=True) in sent
    assert turn(env, EMP2, good).status_code == 404  # someone else's proposal
    assert turn(env, EMP1, {**good, "proposal_id": PROPOSAL}).status_code == 404
    assert len(env.foundry.calls) == 1  # type: ignore[attr-defined]


def test_an_unknown_proposal_cannot_be_confirmed_to_the_briefing_agent(env: BriefEnv) -> None:
    fake = {"proposal_id": "6f0c2f6e-2f0e-4d7e-8f55-0a3d5d9c1c12", "confirmation_token": TOKEN}
    assert turn(env, EMP1, fake).status_code == 404
    assert env.foundry.calls == []  # type: ignore[attr-defined]


@pytest.mark.parametrize(
    ("kind", "tool"), [("opted_in", "set_briefing_optin"), ("summary", "get_my_week")]
)
def test_fr_brf_002_a_claim_is_only_believed_after_the_tool_succeeded(
    env: BriefEnv, kind: str, tool: str
) -> None:
    """The agent cannot say 'your week' without a successful get_my_week in this turn."""
    claim = {"kind": kind, "text": "Done", "omitted_count": 2}
    respond(env, claim)
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"
    respond(env, claim, [{"type": "mcp_call", "name": tool, "error": "NOT_OPTED_IN"}])
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"
    other = "get_briefing_status"
    respond(env, claim, [{"type": "mcp_call", "name": other, "error": None}])
    assert turn(env, EMP1).json()["reply"]["kind"] == "message"  # a different tool is no proof
    respond(env, claim, [{"type": "mcp_call", "name": tool, "error": None}])
    assert turn(env, EMP1).json()["reply"]["kind"] == kind


def test_fr_brf_002_omitted_count_only_belongs_to_a_summary(env: BriefEnv) -> None:
    ok = [{"type": "mcp_call", "name": "get_my_week", "error": None}]
    respond(env, {"kind": "summary", "text": "6 events", "omitted_count": 2}, ok)
    assert turn(env, EMP1).json()["reply"]["omitted_count"] == 2
    respond(env, {"kind": "message", "text": "hi", "omitted_count": 5})
    assert turn(env, EMP1).json()["reply"]["omitted_count"] is None


def test_fr_brf_004_a_refusal_keeps_a_closed_reason(env: BriefEnv) -> None:
    respond(
        env, {"kind": "refusal", "text": "Only your own calendar.", "reason": "other_users_data"}
    )
    reply_body = turn(env, EMP1).json()["reply"]
    assert reply_body["kind"] == "refusal" and reply_body["reason"] == "other_users_data"
    respond(env, {"kind": "refusal", "text": "No.", "reason": "made_up_reason"})
    assert turn(env, EMP1).json()["reply"]["reason"] == "unsupported_action"
    respond(env, {"kind": "message", "text": "hi", "reason": "other_users_data"})
    assert turn(env, EMP1).json()["reply"]["reason"] is None
