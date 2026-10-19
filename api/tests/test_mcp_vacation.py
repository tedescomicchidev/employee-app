"""FR-VAC-001..007 AGENT path, NFR-008, FR-AUTH-003/006: the vacation MCP tools.

The tools call the same VacationService methods as /v1/vacation, so these tests check the adapter:
roles, confirmation tokens, error data, parity with REST and a content-free audit trail.
"""

from collections.abc import Iterator
from dataclasses import replace
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.announcements.service import AnnouncementService
from app.auth.validator import TokenValidator
from app.main import create_app
from app.repositories import InMemoryAnnouncementStore, InMemoryConfirmationStore, SeedDirectory
from app.vacation.service import VacationService
from app.vacation.store import InMemoryVacationStore, VacationConfig
from tests.conftest import TOOLS_SETTINGS, StaticKeys
from tests.mcp_harness import CEO, EMP1, FROZEN, MGR2, Clock, McpEnv

MGR1 = "00000000-0000-0000-0000-000000000002"
EMP2 = "00000000-0000-0000-0000-000000000012"
EMP_ROLES = ("Employee",)
MGR_ROLES = ("Manager", "Employee")

VACATION_TOOLS = {
    "get_balance",
    "get_holidays",
    "list_vacation_requests",
    "get_team_coverage",
    "list_pending_approvals",
    "propose_vacation_request",
    "create_vacation_request",
    "propose_cancel",
    "cancel_vacation_request",
    "propose_decision",
    "decide_vacation_request",
}


class VacEnv(McpEnv):
    """McpEnv with a vacation service on the frozen clock (today = 2026-10-19)."""

    def __init__(self, private_key: Any, **app_kwargs: Any) -> None:
        self.key = private_key
        directory = SeedDirectory.from_file()
        self.service = AnnouncementService(
            directory, InMemoryAnnouncementStore(), InMemoryConfirmationStore(), Clock()
        )
        self.vacation = VacationService(
            directory,
            InMemoryVacationStore(),
            InMemoryConfirmationStore(),
            VacationConfig.from_files(),
            Clock(),
        )
        validator = TokenValidator(TOOLS_SETTINGS, StaticKeys(private_key.public_key()))
        self.app = create_app(
            validator,
            self.service,
            vacation_service=self.vacation,
            directory=directory,
            **app_kwargs,
        )
        self.client: TestClient | None = None

    def tool(self, who: str, name: str, args: dict[str, Any] | None = None) -> Any:
        roles = MGR_ROLES if who in (CEO, MGR1, MGR2) else EMP_ROLES
        return self.call(self.tools_token(who, *roles), name, args)

    def confirm(self, who: str, kind: str, proposal_id: str) -> str:
        """The app's confirm card: only a user token mints a confirmation token."""
        roles = MGR_ROLES if who in (CEO, MGR1, MGR2) else EMP_ROLES
        assert self.client is not None
        r = self.client.post(
            "/v1/confirmations",
            json={"type": kind, "proposal_id": proposal_id},
            headers=self.user(who, *roles),
        )
        assert r.status_code == 200, r.text
        return r.json()["confirmation_token"]

    def book(self, who: str, start: str, end: str) -> dict[str, Any]:
        err, proposal = self.tool(who, "propose_vacation_request", {"start": start, "end": end})
        assert not err, proposal
        token = self.confirm(who, "vacation", proposal["proposal_id"])
        err, request = self.tool(
            who,
            "create_vacation_request",
            {"start": start, "end": end, "confirmation_token": token},
        )
        assert not err, request
        return request


@pytest.fixture
def env(private_key: Any) -> Iterator[VacEnv]:
    env = VacEnv(private_key)
    with TestClient(env.app) as client:
        env.client = client
        yield env


def code_of(text: str) -> str:
    return text.split("Error executing tool ")[-1].split(": ")[1].split(" ")[0]


def test_vacation_tools_are_listed_and_none_mints_a_token(env: VacEnv) -> None:
    """FR-AUTH-006 @api: the agent has propose and confirm-bearing tools, never a token minter."""
    response = env.rpc(env.tools_token(EMP1), "tools/list")
    names = {t["name"] for t in response.json()["result"]["tools"]}
    assert VACATION_TOOLS <= names
    assert not {n for n in names if "confirm" in n and n != "confirmation_token"}


def test_fr_vac_001_balance_matches_rest(env: VacEnv) -> None:
    """FR-VAC-001 @agent-eval @api (NFR-008): the same numbers as GET /v1/vacation/balance."""
    err, balance = env.tool(EMP2, "get_balance")
    rest = env.client.get(  # type: ignore[union-attr]
        "/v1/vacation/balance", headers=env.user(EMP2, *EMP_ROLES)
    ).json()
    assert not err and balance.pop("today") == "2026-10-19" and balance == rest
    assert balance["remaining"] == 20  # 25 - 5 approved


def test_fr_vac_006_holidays_are_the_callers_canton(env: VacEnv) -> None:
    """FR-VAC-006 @api: emp1 (ZH) and emp4 (TI) get their own canton's list."""
    _, zh = env.tool(EMP1, "get_holidays")
    _, ti = env.tool("00000000-0000-0000-0000-000000000014", "get_holidays")
    assert zh["canton"] == "ZH" and ti["canton"] == "TI"
    err, text = env.tool(EMP1, "get_holidays", {"year": 1999})
    assert err and code_of(text) == "VALIDATION_ERROR"


def test_fr_vac_002_propose_returns_review_and_no_token(env: VacEnv) -> None:
    """FR-VAC-002 @agent-eval: counted days and balance come from the api, no token yet."""
    _, balance = env.tool(EMP1, "get_balance")
    err, proposal = env.tool(
        EMP1, "propose_vacation_request", {"start": "2026-11-23", "end": "2026-11-25"}
    )
    assert not err
    assert proposal["status"] == "awaiting_user_confirmation"
    assert (
        proposal["review"]["counted_days"] == 3
        and proposal["review"]["remaining_after"] == balance["remaining"] - 3
    )
    assert "confirmation_token" not in proposal


def test_fr_vac_002_submit_after_confirmation(env: VacEnv) -> None:
    """FR-VAC-002 @agent-eval: the request is pending and assigned to the manager."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    assert request["status"] == "pending" and request["created"] is True
    err, listed = env.tool(EMP1, "list_vacation_requests")
    assert not err and request["id"] in [r["id"] for r in listed["items"]]


def test_fr_auth_006_submit_needs_a_token(env: VacEnv) -> None:
    """FR-AUTH-006 @api: no token, a made-up token and a token for other dates all fail."""
    args = {"start": "2026-11-23", "end": "2026-11-25"}
    err, text = env.tool(EMP1, "create_vacation_request", args)
    assert err and code_of(text) == "CONFIRMATION_REQUIRED"
    err, text = env.tool(EMP1, "create_vacation_request", {**args, "confirmation_token": "yes"})
    assert err and code_of(text) == "INVALID_CONFIRMATION"
    _, proposal = env.tool(EMP1, "propose_vacation_request", args)
    token = env.confirm(EMP1, "vacation", proposal["proposal_id"])
    other = {"start": "2026-11-23", "end": "2026-11-27", "confirmation_token": token}
    err, text = env.tool(EMP1, "create_vacation_request", other)
    assert err and code_of(text) == "INVALID_CONFIRMATION"
    assert "2026-11-23" not in [
        r.start.isoformat() for r in env.vacation.requests(_principal(env, EMP1))
    ]


def test_fr_auth_006_replayed_token_creates_one_request(env: VacEnv) -> None:
    """FR-AUTH-006 @api: a retry with the same token returns the same request."""
    args = {"start": "2026-11-23", "end": "2026-11-25"}
    _, proposal = env.tool(EMP1, "propose_vacation_request", args)
    token = env.confirm(EMP1, "vacation", proposal["proposal_id"])
    _, first = env.tool(EMP1, "create_vacation_request", {**args, "confirmation_token": token})
    _, again = env.tool(EMP1, "create_vacation_request", {**args, "confirmation_token": token})
    assert first["id"] == again["id"] and again["created"] is False


@pytest.mark.parametrize(
    ("start", "end", "expected"),
    [
        ("2026-12-14", "2026-12-18", "BLACKOUT"),
        ("2026-10-12", "2026-10-14", "PAST_DATE"),
        ("2026-11-27", "2026-11-23", "INVALID_RANGE"),
        ("2026-11-21", "2026-11-22", "ZERO_DAYS"),
        ("2026-10-26", "2026-12-11", "INSUFFICIENT_BALANCE"),
    ],
)
def test_fr_vac_002_rule_failures_carry_the_codes(
    env: VacEnv, start: str, end: str, expected: str
) -> None:
    """FR-VAC-002 @agent-eval: the primary code leads and every failing code is in the text."""
    err, text = env.tool(EMP1, "propose_vacation_request", {"start": start, "end": end})
    assert err and code_of(text) == expected
    assert f'"{expected}"' in text  # the codes list from the api, for the agent to quote


def test_fr_vac_002_overlap_with_an_existing_request(env: VacEnv) -> None:
    """FR-VAC-002 @agent-eval: a second request over the same days is OVERLAP."""
    env.book(EMP1, "2026-11-23", "2026-11-25")
    err, text = env.tool(
        EMP1, "propose_vacation_request", {"start": "2026-11-25", "end": "2026-11-27"}
    )
    assert err and code_of(text) == "OVERLAP"


def test_fr_vac_003_cancel_goes_through_a_confirmation(env: VacEnv) -> None:
    """FR-VAC-003 @api: propose, confirm, cancel; without the token nothing changes."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    err, text = env.tool(EMP1, "cancel_vacation_request", {"request_id": request["id"]})
    assert err and code_of(text) == "CONFIRMATION_REQUIRED"
    _, proposal = env.tool(EMP1, "propose_cancel", {"request_id": request["id"]})
    token = env.confirm(EMP1, "vacation_cancel", proposal["proposal_id"])
    err, done = env.tool(
        EMP1, "cancel_vacation_request", {"request_id": request["id"], "confirmation_token": token}
    )
    assert not err and done["status"] == "cancelled"


def test_fr_vac_003_cannot_propose_cancel_for_someone_elses_request(env: VacEnv) -> None:
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    err, text = env.tool(EMP2, "propose_cancel", {"request_id": request["id"]})
    assert err and code_of(text) == "NOT_FOUND"


def test_fr_vac_004_manager_approves_through_a_confirmation(env: VacEnv) -> None:
    """FR-VAC-004 @agent-eval: inbox, propose, confirm, decide."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    _, inbox = env.tool(MGR1, "list_pending_approvals")
    assert request["id"] in [r["id"] for r in inbox["items"]]
    err, text = env.tool(
        MGR1, "decide_vacation_request", {"request_id": request["id"], "decision": "approve"}
    )
    assert err and code_of(text) == "CONFIRMATION_REQUIRED"
    _, proposal = env.tool(
        MGR1, "propose_decision", {"request_id": request["id"], "decision": "approve"}
    )
    assert "confirmation_token" not in proposal
    token = env.confirm(MGR1, "vacation_decision", proposal["proposal_id"])
    err, decided = env.tool(
        MGR1,
        "decide_vacation_request",
        {"request_id": request["id"], "decision": "approve", "confirmation_token": token},
    )
    assert not err and decided["status"] == "approved"


def test_fr_vac_004_reject_keeps_the_reason_out_of_the_audit(env: VacEnv) -> None:
    """NFR-012 @api: the reason is data for the owner, never in the audit trail."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    reason = "Staffing gap during stocktake"
    args = {"request_id": request["id"], "decision": "reject", "reason": reason}
    _, proposal = env.tool(MGR1, "propose_decision", args)
    token = env.confirm(MGR1, "vacation_decision", proposal["proposal_id"])
    err, decided = env.tool(MGR1, "decide_vacation_request", {**args, "confirmation_token": token})
    assert not err and decided["status"] == "rejected" and decided["content_trust"] == "untrusted"
    assert reason not in repr(env.app.state.mcp_audit.records)


def test_fr_vac_004_an_employee_cannot_approve_their_own_request(env: VacEnv) -> None:
    """FR-VAC-004 @agent-eval: SELF_APPROVAL at the proposal, and no token can exist for it."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    args = {"request_id": request["id"], "decision": "approve"}
    err, text = env.tool(EMP1, "propose_decision", args)
    assert err and code_of(text) == "SELF_APPROVAL"
    err, text = env.tool(EMP1, "decide_vacation_request", {**args, "confirmation_token": "x"})
    assert err and code_of(text) in ("INVALID_CONFIRMATION", "SELF_APPROVAL")
    assert env.vacation.get_request(_principal(env, EMP1), request["id"]).status == "pending"


def test_fr_vac_004_a_manager_cannot_approve_their_own_request(env: VacEnv) -> None:
    """FR-VAC-004 @agent-eval: mgr1's own request is assigned to the CEO, not to mgr1."""
    request = env.book(MGR1, "2026-11-23", "2026-11-25")
    err, text = env.tool(
        MGR1, "propose_decision", {"request_id": request["id"], "decision": "approve"}
    )
    assert err and code_of(text) == "SELF_APPROVAL"


def test_fr_vac_004_only_the_assigned_approver_can_decide(env: VacEnv) -> None:
    """FR-VAC-004 @agent-eval: another manager is FORBIDDEN, an unrelated employee too."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    args = {"request_id": request["id"], "decision": "approve"}
    err, text = env.tool(MGR2, "propose_decision", args)
    assert err and code_of(text) == "FORBIDDEN"
    err, text = env.tool(EMP2, "propose_decision", args)
    assert err and code_of(text) == "FORBIDDEN"


def test_fr_vac_004_approval_revalidates_the_blackout(env: VacEnv) -> None:
    """FR-VAC-004 @agent-eval: a request that became invalid cannot be proposed for approval."""
    request = env.book(EMP1, "2026-11-23", "2026-11-25")
    config = env.vacation._config  # noqa: SLF001 - fixture: a blackout added after booking
    env.vacation._config = replace(  # noqa: SLF001
        config, blackouts=(*config.blackouts, _blackout("2026-11-24", "2026-11-24"))
    )
    err, text = env.tool(
        MGR1, "propose_decision", {"request_id": request["id"], "decision": "approve"}
    )
    assert err and code_of(text) == "BLACKOUT"


def test_fr_vac_005_coverage_is_for_managers_only(env: VacEnv) -> None:
    """FR-VAC-005 @agent-eval: employees are FORBIDDEN, a manager sees direct reports only."""
    env.book(EMP1, "2026-11-23", "2026-11-25")
    err, text = env.tool(EMP1, "get_team_coverage")
    assert err and code_of(text) == "FORBIDDEN"
    err, text = env.tool(EMP1, "list_pending_approvals")
    assert err and code_of(text) == "FORBIDDEN"
    err, coverage = env.tool(
        MGR1, "get_team_coverage", {"start": "2026-11-23", "end": "2026-11-27"}
    )
    assert not err and coverage["content_trust"] == "untrusted"
    monday = next(d for d in coverage["days"] if d["date"] == "2026-11-23")
    assert [a["name"] for a in monday["absent"]] == ["Emp One"]
    _, other = env.tool(MGR2, "get_team_coverage", {"start": "2026-11-23", "end": "2026-11-27"})
    assert all(not d["absent"] for d in other["days"])


def test_fr_vac_005_bad_dates_are_validation_errors(env: VacEnv) -> None:
    err, text = env.tool(MGR1, "get_team_coverage", {"start": "tomorrow"})
    assert err and code_of(text) == "VALIDATION_ERROR"


def test_fr_auth_003_vacation_calls_are_audited_without_content(env: VacEnv) -> None:
    """FR-AUTH-003 @api: one record per call: user, tool, outcome, and nothing else."""
    env.tool(EMP1, "get_balance")
    env.tool(EMP1, "propose_vacation_request", {"start": "2026-12-14", "end": "2026-12-18"})
    rows = [(r.user_id, r.tool, r.outcome) for r in env.app.state.mcp_audit.records]
    assert rows == [(EMP1, "get_balance", "ok"), (EMP1, "propose_vacation_request", "blackout")]
    assert "2026-12" not in repr(env.app.state.mcp_audit.records)


def test_frozen_clock_is_the_one_the_tests_assume() -> None:
    assert FROZEN.date().isoformat() == "2026-10-19"


def _principal(env: VacEnv, oid: str) -> Any:
    from app.auth.principal import Principal

    employee = env.vacation._directory.get(oid)  # noqa: SLF001
    assert employee is not None
    return Principal(oid, employee.name, "", ("Employee",), "tenant")


def _blackout(start: str, end: str) -> Any:
    from datetime import date

    from app.vacation.models import Blackout

    return Blackout(date.fromisoformat(start), date.fromisoformat(end))
