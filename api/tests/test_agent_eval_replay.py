"""NFR-013 / FR-ANN-005 / FR-AUTH-006: the attack traces of evals/comms/dataset.jsonl, replayed.

The evals decide whether a *model* misbehaves (live runs). This test decides what happens when it
does: each tool call a compromised or injected agent could emit is sent to the real MCP server as
the persona, and the server must refuse every write, create nothing, and show that persona only
what is addressed to them. api/ is the boundary, not the prompt.
"""

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import pytest

from tests.mcp_harness import CEO, EMP1, EMP4, MGR2, McpEnv, running

DATASET = Path(__file__).parents[2] / "evals" / "comms" / "dataset.jsonl"
CASES = [json.loads(line) for line in DATASET.read_text().splitlines() if line.strip()]
ATTACKS = [
    pytest.param(case, violation, id=f"{case['id']}::{violation['name']}")
    for case in CASES
    for violation in case["violations"]
    if case["set"] == "safety"
]
PERSONAS = {
    "ceo": (CEO, ["Communicator", "Employee"]),
    "mgr1": ("00000000-0000-0000-0000-000000000002", ["Manager", "Employee"]),
    "mgr2": (MGR2, ["Manager", "Employee"]),
    "emp1": (EMP1, ["Employee"]),
    "emp4": (EMP4, ["Employee"]),
}
WRITES = {"publish_announcement"}


@pytest.fixture
def env(private_key: Any) -> Iterator[McpEnv]:
    with running(private_key) as e:
        yield e


def seed(env: McpEnv, fixtures: list[dict[str, Any]]) -> None:
    """Publish fixtures the way the app does: propose, confirm card, publish."""
    for f in fixtures:
        payload = {k: f[k] for k in ("title", "body", "language", "audience")}
        headers = env.ceo_user()
        post = env.client.post  # type: ignore[union-attr]
        pid = post("/v1/proposals", json={"payload": payload}, headers=headers).json()[
            "proposal_id"
        ]
        token = post("/v1/confirmations", json={"proposal_id": pid}, headers=headers).json()
        body = {"payload": payload, "confirmation_token": token["confirmation_token"]}
        assert post("/v1/announcements", json=body, headers=headers).status_code == 201


def test_dataset_has_attack_traces_with_arguments_to_replay() -> None:
    assert len(ATTACKS) >= 10
    replayable = [p for p in ATTACKS if any(t.get("args") for t in p.values[1]["trace"]["tools"])]
    assert len(replayable) >= 8


@pytest.mark.parametrize(("case", "violation"), ATTACKS)
def test_attack_trace_changes_nothing_and_leaks_nothing(
    env: McpEnv, case: dict[str, Any], violation: dict[str, Any]
) -> None:
    seed(env, case["fixtures"])
    before = env.store.count()
    oid, roles = PERSONAS[case["persona"]]
    token = env.tools_token(oid, *roles)
    feed = env.client.get("/v1/announcements", headers=env.user(oid, *roles)).json()  # type: ignore[union-attr]
    addressed_to_persona = {item["id"] for item in feed["items"]}

    for call in violation["trace"]["tools"]:
        is_error, result = env.call(token, call["name"], call.get("args") or {})
        if call["name"] in WRITES:
            assert is_error, f"{call['name']} must be refused without a server-issued token"
        if call["name"] not in {
            "list_announcements", "get_announcement", "list_audience_options",
            "resolve_audience", "propose_announcement", "publish_announcement",
        }:  # fmt: skip
            assert is_error, f"unknown tool {call['name']} must not exist"
        if call["name"] == "list_announcements" and not is_error:
            assert {a["id"] for a in result["announcements"]} <= addressed_to_persona

    assert env.store.count() == before, "an attack trace created an announcement"
