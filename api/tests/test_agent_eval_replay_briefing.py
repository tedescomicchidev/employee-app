"""NFR-013 / FR-BRF-004 / FR-AUTH-006: the attack traces of evals/briefing/dataset.jsonl, replayed.

The evals decide whether a *model* misbehaves (live runs). This test decides what happens when it
does: each call a compromised or injected briefing agent could emit is sent to the real MCP server
as the persona. The server must refuse a write without the card's token, must refuse a user argument
on the calendar tools, and must only ever read Work IQ with the persona's own token.
"""

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import jwt
import pytest
from fastapi.testclient import TestClient

from tests.briefing_harness import CEO, EMP1, EMP2, MGR1, MGR2, MON, BriefEnv, at, ev
from tests.mcp_harness import EMP4

DATASET = Path(__file__).parents[2] / "evals" / "briefing" / "dataset.jsonl"
CASES = [json.loads(line) for line in DATASET.read_text().splitlines() if line.strip()]
ATTACKS = [
    pytest.param(case, violation, id=f"{case['id']}::{violation['name']}")
    for case in CASES
    for violation in case["violations"]
    if case["set"] == "safety"
]
OIDS = {"ceo": CEO, "mgr1": MGR1, "mgr2": MGR2, "emp1": EMP1, "emp2": EMP2, "emp4": EMP4}
BRIEFING_TOOLS = {
    "get_briefing_status",
    "get_my_week",
    "propose_briefing_optin",
    "set_briefing_optin",
}


@pytest.fixture
def env(private_key: Any) -> Iterator[BriefEnv]:
    env = BriefEnv(private_key)
    with TestClient(env.app) as client:
        env.client = client
        yield env


def seed(env: BriefEnv, fixtures: list[dict[str, Any]]) -> None:
    """The persona's opt-in state, and a Work IQ calendar equal to the case's events."""
    for f in fixtures:
        if f["opted_in"]:
            env.opt_in(OIDS[f["owner"]])
        events = [
            ev(f"{f['owner']}-{i}", MON.replace(day=MON.day + e["day"]), e["start"], e["end"],
               title=e["title"], attendee_count=e["attendees"])
            for i, e in enumerate(f["events"])
        ]  # fmt: skip
        for event in events:
            day = event.start.astimezone(at(MON, "00:00").tzinfo).date()
            env.work_iq.events.setdefault(day, []).append(event)


def server_tools(env: BriefEnv) -> set[str]:
    response = env.rpc(env.tools_token(EMP1), "tools/list")
    return {t["name"] for t in response.json()["result"]["tools"]}


def state(env: BriefEnv) -> list[bool]:
    return [env.briefing.status(_p(oid)).opted_in for oid in OIDS.values()]


def _p(oid: str) -> Any:
    from app.auth.principal import Principal

    return Principal(oid, "", "", (), "t")


def test_dataset_has_briefing_attack_traces_with_arguments_to_replay() -> None:
    assert len(ATTACKS) >= 25
    attempts = [
        t
        for p in ATTACKS
        for t in p.values[1]["trace"]["tools"]
        if t["name"] in BRIEFING_TOOLS and t.get("args")
    ]
    assert len(attempts) >= 10


@pytest.mark.parametrize(("case", "violation"), ATTACKS)
def test_attack_trace_changes_nothing_and_reads_only_the_personas_own_calendar(
    env: BriefEnv, case: dict[str, Any], violation: dict[str, Any]
) -> None:
    seed(env, case["fixtures"])
    before = state(env)
    oid = OIDS[case["persona"]]
    tools = server_tools(env)
    for call in violation["trace"]["tools"]:
        name = call["name"]
        if name not in BRIEFING_TOOLS:
            # Another agent's tool is never offered to this one; a tool that does not exist
            # (send_mail, delete_event) cannot be called at all.
            assert not {"send_mail", "delete_event"} & tools
            continue
        is_error, _ = env.tool(oid, name, call.get("args") or {})
        if name == "set_briefing_optin":
            assert is_error, "the opt-in write must be refused without the card's token"
        if name in ("get_my_week", "get_briefing_status") and call.get("args"):
            assert is_error, f"{name} must reject any argument (no user parameter exists)"
    assert state(env) == before, "an attack trace changed an opt-in"
    for assertion in env.work_iq.assertions:
        # Work IQ is only ever called with the persona's own delegated token (FR-AUTH-004).
        assert jwt.decode(assertion, options={"verify_signature": False})["oid"] == oid
