"""FR-VAC-003 (cancel), FR-VAC-004 (decide), FR-VAC-005 (coverage): test-cases.md, CLASSIC path."""

from dataclasses import replace
from datetime import date
from typing import Any

import pytest

from app.vacation.models import Blackout
from tests.test_vacation import OIDS, Env, TokenFactory, VacationConfig


@pytest.fixture
def env(private_key: Any, make_token: TokenFactory) -> Env:
    return Env(private_key, make_token, VacationConfig.from_files())


def cancel_token(env: Env, who: str, request_id: str) -> str:
    proposal = env.client.post(
        "/v1/proposals",
        json={"type": "vacation_cancel", "payload": {"request_id": request_id}},
        headers=env.headers(who),
    )
    assert proposal.status_code == 200, proposal.text
    r = env.client.post(
        "/v1/confirmations",
        json={"type": "vacation_cancel", "proposal_id": proposal.json()["proposal_id"]},
        headers=env.headers(who),
    )
    assert r.status_code == 200, r.text
    return r.json()["confirmation_token"]


def cancel(env: Env, who: str, request_id: str, token: str) -> Any:
    return env.client.post(
        f"/v1/vacation/requests/{request_id}/cancel",
        json={"confirmation_token": token},
        headers=env.headers(who),
    )


def book_pending(env: Env, who: str = "emp2") -> str:
    r = env.book(who, "2026-11-23", "2026-11-25")
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_fr_vac_003_cancel_pending_releases_days_and_leaves_the_inbox(env: Env) -> None:
    """FR-VAC-003.1 @api: status cancelled, remaining +3, inbox entry gone."""
    request_id = book_pending(env)
    before = env.get("emp2", "/balance").json()
    assert env.get("mgr1", "/inbox").json()["items"]
    r = cancel(env, "emp2", request_id, cancel_token(env, "emp2", request_id))
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert r.json()["decided_at"]
    after = env.get("emp2", "/balance").json()
    assert (
        after["remaining"] == before["remaining"] + 3 and after["pending"] == before["pending"] - 3
    )
    assert request_id not in [i["id"] for i in env.get("mgr1", "/inbox").json()["items"]]
    listed = {i["id"]: i for i in env.get("emp2", "/requests").json()["items"]}
    assert listed[request_id]["status"] == "cancelled"


def test_fr_vac_003_cancel_is_idempotent_on_the_token(env: Env) -> None:
    """FR-VAC-003.3: a retry with the same token returns the cancelled request."""
    request_id = book_pending(env)
    token = cancel_token(env, "emp2", request_id)
    assert cancel(env, "emp2", request_id, token).status_code == 200
    again = cancel(env, "emp2", request_id, token)
    assert again.status_code == 200 and again.json()["status"] == "cancelled"


def test_fr_vac_003_cancel_needs_a_confirmation(env: Env) -> None:
    """FR-VAC-003.3: no token, forged token, or a token for another request."""
    first, other = book_pending(env), env.book("emp2", "2026-12-01", "2026-12-02").json()["id"]
    assert cancel(env, "emp2", first, "").status_code == 409
    assert cancel(env, "emp2", first, "forged").json()["code"] == "INVALID_CONFIRMATION"
    wrong = cancel_token(env, "emp2", other)
    assert cancel(env, "emp2", first, wrong).json()["code"] == "INVALID_CONFIRMATION"
    assert env.store.get(first).status == "pending"


def test_fr_vac_003_cannot_cancel_a_decided_request(env: Env) -> None:
    """FR-VAC-003.2 @api: the fixture approved request returns INVALID_STATE."""
    r = env.client.post(
        "/v1/proposals",
        json={"type": "vacation_cancel", "payload": {"request_id": "seed-emp2-nov"}},
        headers=env.headers("emp2"),
    )
    assert (r.status_code, r.json()["code"]) == (409, "INVALID_STATE")
    assert env.store.get("seed-emp2-nov").status == "approved"


def test_fr_vac_003_second_cancel_with_a_new_token_is_invalid_state(env: Env) -> None:
    """FR-VAC-003.2: terminal states are final (R11)."""
    request_id = book_pending(env)
    assert cancel(env, "emp2", request_id, cancel_token(env, "emp2", request_id)).status_code == 200
    r = env.client.post(
        "/v1/proposals",
        json={"type": "vacation_cancel", "payload": {"request_id": request_id}},
        headers=env.headers("emp2"),
    )
    assert r.json()["code"] == "INVALID_STATE"


def test_fr_vac_003_cannot_cancel_someone_elses_request(env: Env) -> None:
    """FR-VAC-003 @adversarial: emp1 cancelling emp2's pending request gets NOT_FOUND."""
    request_id = book_pending(env)
    r = env.client.post(
        "/v1/proposals",
        json={"type": "vacation_cancel", "payload": {"request_id": request_id}},
        headers=env.headers("emp1"),
    )
    assert r.status_code == 404
    # even with a token minted for emp2, emp1 cannot use it
    token = cancel_token(env, "emp2", request_id)
    assert cancel(env, "emp1", request_id, token).status_code == 409
    assert env.store.get(request_id).status == "pending"


# FR-VAC-004 ------------------------------------------------------------------------------


def decision_proposal(
    env: Env, who: str, request_id: str, decision: str = "approve", reason: str | None = None
) -> Any:
    payload: dict[str, Any] = {"request_id": request_id, "decision": decision}
    if reason is not None:
        payload["reason"] = reason
    return env.client.post(
        "/v1/proposals",
        json={"type": "vacation_decision", "payload": payload},
        headers=env.headers(who),
    )


def decision_token(
    env: Env, who: str, request_id: str, decision: str = "approve", reason: str | None = None
) -> str:
    proposal = decision_proposal(env, who, request_id, decision, reason)
    assert proposal.status_code == 200, proposal.text
    r = env.client.post(
        "/v1/confirmations",
        json={"type": "vacation_decision", "proposal_id": proposal.json()["proposal_id"]},
        headers=env.headers(who),
    )
    assert r.status_code == 200, r.text
    return r.json()["confirmation_token"]


def decide(
    env: Env,
    who: str,
    request_id: str,
    token: str,
    decision: str = "approve",
    reason: str | None = None,
) -> Any:
    body: dict[str, Any] = {"decision": decision, "confirmation_token": token}
    if reason is not None:
        body["reason"] = reason
    return env.client.post(
        f"/v1/vacation/requests/{request_id}/decision", json=body, headers=env.headers(who)
    )


def test_fr_vac_004_manager_approves(env: Env) -> None:
    """FR-VAC-004.1/.4 @api: approved, the owner sees it, the balance stays as reserved."""
    request_id = book_pending(env)
    before = env.get("emp2", "/balance").json()
    r = decide(env, "mgr1", request_id, decision_token(env, "mgr1", request_id))
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert r.json()["decided_at"] and r.json()["reason"] is None
    assert env.get("emp2", "/balance").json() == before | {
        "approved": before["approved"] + 3,
        "pending": before["pending"] - 3,
    }
    mine = {i["id"]: i for i in env.get("emp2", "/requests").json()["items"]}
    assert mine[request_id]["status"] == "approved"
    assert request_id not in [i["id"] for i in env.get("mgr1", "/inbox").json()["items"]]


def test_fr_vac_004_manager_rejects_with_a_reason(env: Env) -> None:
    """FR-VAC-004.1/.4 @api: rejected, days released, the owner sees the reason."""
    request_id = book_pending(env)
    before = env.get("emp2", "/balance").json()
    token = decision_token(env, "mgr1", request_id, "reject", "Inventory week")
    r = decide(env, "mgr1", request_id, token, "reject", "Inventory week")
    assert r.status_code == 200 and r.json()["status"] == "rejected"
    after = env.get("emp2", "/balance").json()
    assert after["remaining"] == before["remaining"] + 3
    mine = {i["id"]: i for i in env.get("emp2", "/requests").json()["items"]}
    assert (mine[request_id]["status"], mine[request_id]["reason"]) == (
        "rejected",
        "Inventory week",
    )


def test_fr_vac_004_reason_is_limited_to_500_characters(env: Env) -> None:
    """FR-VAC-004.1: a longer reason is a validation error and nothing changes."""
    request_id = book_pending(env)
    r = decision_proposal(env, "mgr1", request_id, "reject", "x" * 501)
    assert (r.status_code, r.json()["code"]) == (422, "VALIDATION_ERROR")
    assert decision_proposal(env, "mgr1", request_id, "reject", "x" * 500).status_code == 200
    assert env.store.get(request_id).status == "pending"


def test_fr_vac_004_decision_needs_a_matching_confirmation(env: Env) -> None:
    """FR-AUTH-006: no token, a forged one, or a token for the other decision."""
    request_id = book_pending(env)
    assert decide(env, "mgr1", request_id, "").status_code == 409
    assert decide(env, "mgr1", request_id, "forged").json()["code"] == "INVALID_CONFIRMATION"
    approve = decision_token(env, "mgr1", request_id, "approve")
    assert decide(env, "mgr1", request_id, approve, "reject").json()["code"] == (
        "INVALID_CONFIRMATION"
    )
    assert env.store.get(request_id).status == "pending"


def test_fr_vac_004_wrong_manager_is_forbidden(env: Env) -> None:
    """FR-VAC-004.5 @adversarial: mgr2 cannot decide emp2's request; it stays pending."""
    request_id = book_pending(env)
    assert decision_proposal(env, "mgr2", request_id).json()["code"] == "FORBIDDEN"
    token = decision_token(env, "mgr1", request_id)
    assert decide(env, "mgr2", request_id, token).status_code == 409  # token is mgr1's
    assert env.store.get(request_id).status == "pending"


def test_fr_vac_004_employee_cannot_decide(env: Env) -> None:
    """FR-VAC-004.5 @adversarial: emp1 gets FORBIDDEN and the inbox is manager-only."""
    request_id = book_pending(env)
    r = decision_proposal(env, "emp1", request_id)
    assert (r.status_code, r.json()["code"]) == (403, "FORBIDDEN")
    assert env.get("emp1", "/inbox").status_code == 403
    assert env.get("emp1", "/decisions").status_code == 403
    assert env.store.get(request_id).status == "pending"


def test_fr_vac_004_self_approval_changes_nothing(env: Env) -> None:
    """FR-VAC-004.5 @adversarial: mgr1's own request (assigned to the CEO) is not theirs."""
    r = decision_proposal(env, "mgr1", "seed-mgr1-pending")
    assert (r.status_code, r.json()["code"]) == (422, "SELF_APPROVAL")
    assert env.store.get("seed-mgr1-pending").status == "pending"
    assert decision_proposal(env, "ceo", "seed-mgr1-pending").status_code == 200


def test_fr_vac_004_approval_revalidates_blackouts(env: Env) -> None:
    """FR-VAC-004.2 @api: a blackout added after submission blocks the approval."""
    request_id = book_pending(env)
    token = decision_token(env, "mgr1", request_id)
    blackout = Blackout(date(2026, 11, 20), date(2026, 11, 27))
    env.service._config = replace(env.service._config, blackouts=(blackout,))
    r = decide(env, "mgr1", request_id, token)
    assert (r.status_code, r.json()["code"]) == (422, "BLACKOUT")
    assert env.store.get(request_id).status == "pending"
    rejected = decide(
        env, "mgr1", request_id, decision_token(env, "mgr1", request_id, "reject"), "reject"
    )
    assert rejected.json()["status"] == "rejected"  # a rejection needs no re-validation


def test_fr_vac_004_approval_revalidates_the_balance(env: Env) -> None:
    """FR-VAC-004.2/R5: not enough days any more returns INSUFFICIENT_BALANCE, still pending."""
    request_id = book_pending(env)
    token = decision_token(env, "mgr1", request_id)
    request = env.store.get(request_id)
    env.store._requests[request_id] = replace(request, counted_days=40, per_year={2026: 40})
    r = decide(env, "mgr1", request_id, token)
    assert (r.status_code, r.json()["code"]) == (422, "INSUFFICIENT_BALANCE")
    assert env.store.get(request_id).status == "pending"


def test_fr_vac_004_overlap_at_decision_time_blocks_the_approval(env: Env) -> None:
    """FR-VAC-004.2/R6: an approved request that now overlaps returns OVERLAP."""
    request_id = book_pending(env)
    token = decision_token(env, "mgr1", request_id)
    clash = replace(env.store.get(request_id), id="clash", status="approved")
    env.store.add(clash)
    assert decide(env, "mgr1", request_id, token).json()["code"] == "OVERLAP"


def test_fr_vac_004_double_decision_is_invalid_state(env: Env) -> None:
    """FR-VAC-004.3 @api: reject after approve is INVALID_STATE; a token replay is idempotent."""
    request_id = book_pending(env)
    token = decision_token(env, "mgr1", request_id)
    assert decide(env, "mgr1", request_id, token).status_code == 200
    replay = decide(env, "mgr1", request_id, token)
    assert replay.status_code == 200 and replay.json()["status"] == "approved"
    r = decision_proposal(env, "mgr1", request_id, "reject", "late")
    assert (r.status_code, r.json()["code"]) == (409, "INVALID_STATE")
    assert env.store.get(request_id).status == "approved"


def test_fr_vac_004_manager_sees_the_same_status_as_the_employee(env: Env) -> None:
    """FR-VAC-007.2 @api: identical status and order in emp2's list and mgr1's decisions."""
    request_id = book_pending(env)
    decide(env, "mgr1", request_id, decision_token(env, "mgr1", request_id))
    mine = env.get("emp2", "/requests").json()["items"]
    theirs = [
        i for i in env.get("mgr1", "/decisions").json()["items"] if i["owner_oid"] == OIDS["emp2"]
    ]
    assert [(i["id"], i["status"], i["start"]) for i in mine] == [
        (i["id"], i["status"], i["start"]) for i in theirs
    ]
    assert {"rejected", "approved"} <= {i["status"] for i in theirs}


def test_fr_vac_004_detail_for_the_approver_includes_the_balance_only_for_them(env: Env) -> None:
    """FR-VAC-001.3/004: the report's balance goes to their approver, never to others."""
    request_id = book_pending(env)
    as_manager = env.get("mgr1", f"/requests/{request_id}").json()
    assert as_manager["owner_balance"]["remaining"] == 17 and as_manager["owner_name"]
    assert "owner_balance" not in env.get("emp2", f"/requests/{request_id}").json()
    assert env.get("mgr2", f"/requests/{request_id}").status_code == 404
    assert env.get("emp1", f"/requests/{request_id}").status_code == 404
