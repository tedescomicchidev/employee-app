"""NFR-013 / FR-VAC-004 / FR-AUTH-006: the attack traces of evals/vacation/dataset.jsonl, replayed.

The evals decide whether a *model* misbehaves (live runs). This test decides what happens when it
does: each write a compromised or injected vacation agent could emit is sent to the real MCP server
as the persona, and the server must refuse it and change no request. api/ is the boundary.
"""

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from tests.mcp_harness import CEO, EMP1, EMP4, MGR2
from tests.test_mcp_vacation import MGR1, VacEnv

DATASET = Path(__file__).parents[2] / "evals" / "vacation" / "dataset.jsonl"
CASES = [json.loads(line) for line in DATASET.read_text().splitlines() if line.strip()]
ATTACKS = [
    pytest.param(case, violation, id=f"{case['id']}::{violation['name']}")
    for case in CASES
    for violation in case["violations"]
    if case["set"] == "safety"
]
OIDS = {
    "ceo": CEO, "mgr1": MGR1, "mgr2": MGR2, "emp1": EMP1,
    "emp2": "00000000-0000-0000-0000-000000000012", "emp4": EMP4,
}  # fmt: skip
WRITES = {"create_vacation_request", "cancel_vacation_request", "decide_vacation_request"}
VACATION_TOOLS = WRITES | {
    "get_balance", "get_holidays", "list_vacation_requests", "get_team_coverage",
    "list_pending_approvals", "propose_vacation_request", "propose_cancel", "propose_decision",
}  # fmt: skip


@pytest.fixture
def env(private_key: Any) -> Iterator[VacEnv]:
    env = VacEnv(private_key)
    with TestClient(env.app) as client:
        env.client = client
        yield env


def seed(env: VacEnv, fixtures: list[dict[str, Any]]) -> None:
    """Book fixtures the way the app does: propose, confirm card, create (then decide)."""
    approver = {"emp1": "mgr1", "emp2": "mgr1", "emp4": "mgr2", "mgr1": "ceo", "mgr2": "ceo"}
    for f in fixtures:
        owner = OIDS[f["owner"]]
        request = env.book(owner, f["start"], f["end"])
        if f["status"] == "pending":
            continue
        decision = "approve" if f["status"] == "approved" else "reject"
        args = {"request_id": request["id"], "decision": decision, "reason": f.get("reason")}
        _, proposal = env.tool(OIDS[approver[f["owner"]]], "propose_decision", args)
        token = env.confirm(
            OIDS[approver[f["owner"]]], "vacation_decision", proposal["proposal_id"]
        )
        err, _ = env.tool(
            OIDS[approver[f["owner"]]],
            "decide_vacation_request",
            {**args, "confirmation_token": token},
        )
        assert not err


def snapshot(env: VacEnv) -> list[tuple[str, str]]:
    store = env.vacation._store  # noqa: SLF001
    owners = {r.owner_oid for oid in OIDS.values() for r in store.for_owner(oid)}
    return sorted((r.id, r.status) for oid in owners for r in store.for_owner(oid))


def test_dataset_has_vacation_attack_traces_with_arguments_to_replay() -> None:
    assert len(ATTACKS) >= 15
    writes = [
        t
        for p in ATTACKS
        for t in p.values[1]["trace"]["tools"]
        if t["name"] in WRITES and t.get("args")
    ]
    assert len(writes) >= 10


@pytest.mark.parametrize(("case", "violation"), ATTACKS)
def test_attack_trace_changes_nothing(
    env: VacEnv, case: dict[str, Any], violation: dict[str, Any]
) -> None:
    seed(env, case["fixtures"])
    before = snapshot(env)
    oid = OIDS[case["persona"]]
    for call in violation["trace"]["tools"]:
        name = call["name"]
        assert name in VACATION_TOOLS or name not in env_tool_names(env), name
        if name not in VACATION_TOOLS:
            continue  # a tool of the other agent: the vacation agent is never offered it
        is_error, _ = env.tool(oid, name, call.get("args") or {})
        if name in WRITES:
            assert is_error, f"{name} must be refused without a token the app issued"
    assert snapshot(env) == before, "an attack trace changed a vacation request"


def env_tool_names(env: VacEnv) -> set[str]:
    response = env.rpc(env.tools_token(EMP1), "tools/list")
    return {t["name"] for t in response.json()["result"]["tools"]}
