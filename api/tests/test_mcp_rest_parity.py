"""NFR-008: the same announcement scenarios through REST and through MCP give the same outcome.

Scope today: announcements. The vacation tools join this suite in their own slice. Error codes and
persisted end state must match; ids, timestamps and the transport differ by design.
"""

from collections.abc import Iterator
from typing import Any

import pytest

from tests.mcp_harness import CEO, EMP1, EMP4, McpEnv, running

DRAFT = {"title": "Hours", "body": "Open at 8", "language": "de", "audience": "all"}
OUTSIDE = {**DRAFT, "audience": {"regions": ["IT"]}}


@pytest.fixture
def pair(private_key: Any) -> Iterator[tuple[McpEnv, McpEnv]]:
    with running(private_key) as rest, running(private_key) as mcp:
        yield rest, mcp


def rest_call(env: McpEnv, who: str, op: str, **a: Any) -> str:
    """Outcome string: 'ok' or the error code."""
    roles = ["Communicator", "Employee"] if who == CEO else ["Employee"]
    h, c = env.user(who, *roles), env.client  # type: ignore[union-attr]
    if op == "propose":
        r = c.post("/v1/proposals", json={"payload": a["draft"]}, headers=h)
    elif op == "publish":
        r = c.post(
            "/v1/announcements",
            json={"payload": a["draft"], "confirmation_token": a.get("token", "")},
            headers=h,
        )
    elif op == "resolve":
        r = c.post("/v1/audience/resolve", json={"audience": a["audience"]}, headers=h)
    else:
        r = c.get(f"/v1/announcements/{a['id']}", headers=h)
    return "ok" if r.status_code < 300 else r.json()["code"]


def mcp_call(env: McpEnv, who: str, op: str, **a: Any) -> str:
    roles = ["Communicator", "Employee"] if who == CEO else ["Employee"]
    token = env.tools_token(who, *roles)
    tool, args = {
        "propose": ("propose_announcement", a.get("draft")),
        "publish": (
            "publish_announcement",
            {"confirmation_token": a.get("token", ""), **a.get("draft", {})},
        ),
        "resolve": ("resolve_audience", {"audience": a.get("audience")}),
        "get": ("get_announcement", {"announcement_id": a.get("id")}),
    }[op]
    is_error, result = env.call(token, tool, args)
    return result.split("Error executing tool ")[-1].split(": ")[1] if is_error else "ok"


SCENARIOS = [
    ("employee cannot propose", EMP1, "propose", {"draft": DRAFT}, "FORBIDDEN"),
    ("employee cannot publish", EMP1, "publish", {"draft": DRAFT, "token": "x"}, "FORBIDDEN"),
    ("employee cannot resolve", EMP1, "resolve", {"audience": "all"}, "FORBIDDEN"),
    ("bad language", CEO, "propose", {"draft": {**DRAFT, "language": "es"}}, "VALIDATION_ERROR"),
    (
        "title too long",
        CEO,
        "propose",
        {"draft": {**DRAFT, "title": "x" * 121}},
        "VALIDATION_ERROR",
    ),
    (
        "empty audience",
        CEO,
        "propose",
        {"draft": {**DRAFT, "audience": {"stores": ["Nope"]}}},
        "EMPTY_AUDIENCE",
    ),
    (
        "all combined",
        CEO,
        "resolve",
        {"audience": {"all": True, "regions": ["IT"]}},
        "VALIDATION_ERROR",
    ),
    ("publish without token", CEO, "publish", {"draft": DRAFT}, "CONFIRMATION_REQUIRED"),
    (
        "publish with unknown token",
        CEO,
        "publish",
        {"draft": DRAFT, "token": "nope"},
        "INVALID_CONFIRMATION",
    ),
    (
        "unknown announcement",
        EMP1,
        "get",
        {"id": "00000000-0000-0000-0000-000000000000"},
        "NOT_FOUND",
    ),
    ("valid proposal", CEO, "propose", {"draft": DRAFT}, "ok"),
    ("valid resolve", CEO, "resolve", {"audience": "all"}, "ok"),
]


@pytest.mark.parametrize(
    ("name", "who", "op", "args", "expected"), SCENARIOS, ids=[s[0] for s in SCENARIOS]
)
def test_nfr_008_same_outcome_through_rest_and_mcp(
    pair: tuple[McpEnv, McpEnv], name: str, who: str, op: str, args: dict[str, Any], expected: str
) -> None:
    rest, mcp = pair
    assert rest_call(rest, who, op, **args) == expected
    assert mcp_call(mcp, who, op, **args) == expected


def publish_via_rest(env: McpEnv, draft: dict[str, Any]) -> None:
    c, h = env.client, env.ceo_user()  # type: ignore[union-attr]
    pid = c.post("/v1/proposals", json={"payload": draft}, headers=h).json()["proposal_id"]  # type: ignore[union-attr]
    token = c.post("/v1/confirmations", json={"proposal_id": pid}, headers=h).json()  # type: ignore[union-attr]
    r = c.post(
        "/v1/announcements",
        json={"payload": draft, "confirmation_token": token["confirmation_token"]},
        headers=h,
    )  # type: ignore[union-attr]
    assert r.status_code == 201


def publish_via_mcp(env: McpEnv, draft: dict[str, Any]) -> None:
    token = env.tools_token(CEO, "Communicator", "Employee")
    pid = env.call(token, "propose_announcement", draft)[1]["proposal_id"]
    card = env.client.post("/v1/confirmations", json={"proposal_id": pid}, headers=env.ceo_user())  # type: ignore[union-attr]
    is_error, out = env.call(
        token,
        "publish_announcement",
        {"confirmation_token": card.json()["confirmation_token"], **draft},
    )
    assert not is_error and out["status"] == "published"


@pytest.mark.parametrize("draft", [DRAFT, OUTSIDE], ids=["all", "region IT"])
def test_nfr_008_same_persisted_end_state_in_both_modes(
    pair: tuple[McpEnv, McpEnv], draft: dict[str, Any]
) -> None:
    rest, mcp = pair
    publish_via_rest(rest, draft)
    publish_via_mcp(mcp, draft)

    def state(env: McpEnv) -> list[dict[str, Any]]:
        out = []
        for oid in (CEO, EMP1, EMP4):
            roles = ["Communicator", "Employee"] if oid == CEO else ["Employee"]
            items = env.client.get("/v1/announcements", headers=env.user(oid, *roles)).json()[
                "items"
            ]  # type: ignore[union-attr]
            fields = (
                "title",
                "body",
                "language",
                "audience",
                "author",
                "status",
                "recipient_count",
            )
            out.append({"who": oid, "items": [{k: i[k] for k in fields} for i in items]})
        return out

    assert state(rest) == state(mcp) and rest.store.count() == mcp.store.count() == 1
