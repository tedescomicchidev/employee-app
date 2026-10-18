"""FR-ANN-001 (+ FR-AUTH-006 token rules), test-cases.md section FR-ANN-001."""

import logging
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.announcements.service import AnnouncementService
from app.auth.validator import TokenValidator
from app.main import create_app
from app.repositories import InMemoryAnnouncementStore, InMemoryConfirmationStore, SeedDirectory
from tests.conftest import SETTINGS, StaticKeys

CEO = "00000000-0000-0000-0000-000000000001"
EMP1 = "00000000-0000-0000-0000-000000000011"
DISABLED = "00000000-0000-0000-0000-0000000000d1"
GUEST = "00000000-0000-0000-0000-0000000000ff"
FROZEN = datetime(2026, 10, 19, 6, 0, tzinfo=UTC)  # 08:00 Europe/Zurich

TokenFactory = Callable[..., str]


class Clock:
    def __init__(self) -> None:
        self.now = FROZEN

    def __call__(self) -> datetime:
        return self.now


class Env:
    def __init__(self, private_key: Any, make_token: TokenFactory) -> None:
        self.clock = Clock()
        self.store = InMemoryAnnouncementStore()
        service = AnnouncementService(
            SeedDirectory.from_file(), self.store, InMemoryConfirmationStore(), self.clock
        )
        validator = TokenValidator(SETTINGS, StaticKeys(private_key.public_key()))
        self.client = TestClient(create_app(validator, service))
        self._make = make_token

    def headers(self, oid: str, *roles: str) -> dict[str, str]:
        token = self._make(oid=oid, roles=list(roles) or ["Employee"])
        return {"Authorization": f"Bearer {token}"}

    def ceo(self) -> dict[str, str]:
        return self.headers(CEO, "Communicator", "Employee")


@pytest.fixture
def env(private_key: Any, make_token: TokenFactory) -> Env:
    return Env(private_key, make_token)


PAYLOAD = {
    "title": "Store hours",
    "body": "Open 8:00 on Friday",
    "language": "de",
    "audience": "all",
}


def propose(env: Env, payload: dict[str, Any] | None = None, headers: Any = None) -> Any:
    return env.client.post(
        "/v1/proposals", json={"payload": payload or PAYLOAD}, headers=headers or env.ceo()
    )


def confirm(env: Env, proposal_id: str, headers: Any = None) -> Any:
    return env.client.post(
        "/v1/confirmations", json={"proposal_id": proposal_id}, headers=headers or env.ceo()
    )


def publish(
    env: Env, token: str | None, payload: dict[str, Any] | None = None, headers: Any = None
):
    body: dict[str, Any] = {"payload": payload or PAYLOAD}
    if token:
        body["confirmation_token"] = token
    return env.client.post("/v1/announcements", json=body, headers=headers or env.ceo())


def confirmed_token(env: Env, payload: dict[str, Any] | None = None) -> str:
    proposal = propose(env, payload).json()["proposal_id"]
    return confirm(env, proposal).json()["confirmation_token"]


def feed(env: Env, oid: str) -> Any:
    return env.client.get("/v1/announcements", headers=env.headers(oid))


def test_fr_ann_001_publisher_publishes_to_all_after_confirmation(env: Env) -> None:
    proposal = propose(env)
    assert proposal.status_code == 200
    assert proposal.json()["recipient_count"] == 11
    response = publish(
        env, confirm(env, proposal.json()["proposal_id"]).json()["confirmation_token"]
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "published" and body["audience"] == "all" and body["language"] == "de"
    assert body["published_at"] and body["recipient_count"] == 11
    assert env.store.count() == 1
    seeded = SeedDirectory.from_file().active()
    assert len(seeded) == 11
    for employee in seeded:
        items = feed(env, employee.oid).json()["items"]
        assert [i["id"] for i in items] == [body["id"]]


def test_fr_ann_001_not_visible_to_guest_or_deactivated_user(env: Env) -> None:
    publish(env, confirmed_token(env))
    assert feed(env, DISABLED).status_code == 403
    assert feed(env, GUEST).json()["code"] == "NOT_PROVISIONED"


def test_fr_ann_001_employee_cannot_publish(env: Env) -> None:
    emp = env.headers(EMP1, "Employee")
    for response in (
        propose(env, headers=emp),
        confirm(env, "x", headers=emp),
        publish(env, "forged", headers=emp),
        propose(env, {"title": ""}, headers=emp),
    ):
        assert response.status_code == 403
        assert response.json()["code"] == "FORBIDDEN"
    assert env.store.count() == 0


def test_fr_ann_001_unconfirmed_draft_is_not_visible(env: Env) -> None:
    propose(env)
    assert env.store.count() == 0
    assert feed(env, EMP1).json()["items"] == []


def test_fr_ann_001_publish_without_token_is_confirmation_required(env: Env) -> None:
    response = publish(env, None)
    assert response.status_code == 409
    assert response.json()["code"] == "CONFIRMATION_REQUIRED"
    assert env.store.count() == 0


def test_fr_ann_001_publish_is_idempotent(env: Env) -> None:
    token = confirmed_token(env)
    first = publish(env, token)
    second = publish(env, token)
    assert first.status_code == 201 and second.status_code == 200
    assert second.json()["id"] == first.json()["id"] and second.json()["created"] is False
    assert env.store.count() == 1
    assert len(feed(env, EMP1).json()["items"]) == 1


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("title", ""),
        ("title", "x" * 121),
        ("body", ""),
        ("body", "x" * 5001),
        ("language", "es"),
    ],
)
def test_fr_ann_001_field_validation(env: Env, field: str, value: str) -> None:
    response = propose(env, {**PAYLOAD, field: value})
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"
    assert response.json()["field"] == field


def test_fr_ann_001_limits_are_inclusive(env: Env) -> None:
    ok = {**PAYLOAD, "title": "x" * 120, "body": "y" * 5000}
    assert propose(env, ok).status_code == 200


def test_fr_auth_006_tampered_payload_is_rejected(env: Env) -> None:
    token = confirmed_token(env)
    response = publish(env, token, {**PAYLOAD, "body": "Open 6:00 on Friday"})
    assert response.status_code == 409 and response.json()["code"] == "INVALID_CONFIRMATION"
    assert env.store.count() == 0


def test_fr_auth_006_token_of_another_user_is_rejected(env: Env) -> None:
    token = confirmed_token(env)
    other = env.headers("00000000-0000-0000-0000-000000000002", "Communicator")
    response = publish(env, token, headers=other)
    assert response.json()["code"] == "INVALID_CONFIRMATION" and env.store.count() == 0


def test_fr_auth_006_unknown_token_is_rejected(env: Env) -> None:
    assert publish(env, "made-up").json()["code"] == "INVALID_CONFIRMATION"


def test_fr_auth_006_cannot_confirm_someone_elses_proposal(env: Env) -> None:
    proposal = propose(env).json()["proposal_id"]
    other = env.headers("00000000-0000-0000-0000-000000000002", "Communicator")
    assert confirm(env, proposal, headers=other).json()["code"] == "INVALID_CONFIRMATION"


def test_fr_auth_006_expired_token_is_rejected(env: Env) -> None:
    token = confirmed_token(env)
    env.clock.now += timedelta(minutes=5, seconds=1)
    assert publish(env, token).json()["code"] == "INVALID_CONFIRMATION"
    assert env.store.count() == 0


def test_fr_auth_006_expired_proposal_cannot_be_confirmed(env: Env) -> None:
    proposal = propose(env).json()["proposal_id"]
    env.clock.now += timedelta(minutes=6)
    assert confirm(env, proposal).json()["code"] == "INVALID_CONFIRMATION"


def test_fr_auth_006_replay_after_expiry_still_returns_the_existing_one(env: Env) -> None:
    token = confirmed_token(env)
    first = publish(env, token)
    env.clock.now += timedelta(hours=1)
    again = publish(env, token)
    assert again.status_code == 200 and again.json()["id"] == first.json()["id"]


def test_fr_auth_006_tools_invoke_token_cannot_mint_confirmation(
    env: Env, make_token: TokenFactory
) -> None:
    agent_token = make_token(oid=CEO, roles=["Communicator"], scp=None)
    response = confirm(env, "x", headers={"Authorization": f"Bearer {agent_token}"})
    assert response.status_code == 401


def test_fr_ann_001_logs_hold_no_content_or_tokens(
    env: Env, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    token = confirmed_token(env)
    publish(env, token)
    assert "Open 8:00" not in caplog.text and token not in caplog.text


def test_fr_ann_001_events_reject_unknown_fields_and_content(env: Env) -> None:
    event = {
        "event": "task_started",
        "participant_id": "3f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10",
        "session_id": "4f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10",
        "task_run_id": "5f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10",
        "task_id": "T-ANN-PUB",
        "feature": "ann",
        "mode": "classic",
        "order_index": 0,
        "app_version": "1.0",
        "os_version": "17.5",
        "locale": "de",
        "ts": "2026-10-19T06:00:00Z",
    }
    ok = env.client.post("/v1/events", json={"events": [event]}, headers=env.ceo())
    assert ok.status_code == 202 and ok.json() == {"accepted": 1}
    bad = env.client.post(
        "/v1/events", json={"events": [{**event, "title": "Store hours"}]}, headers=env.ceo()
    )
    assert bad.status_code == 422
