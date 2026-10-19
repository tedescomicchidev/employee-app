"""FR-VAC-003 (cancel), FR-VAC-004 (decide), FR-VAC-005 (coverage): test-cases.md, CLASSIC path."""

from typing import Any

import pytest

from tests.test_vacation import Env, TokenFactory, VacationConfig


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
