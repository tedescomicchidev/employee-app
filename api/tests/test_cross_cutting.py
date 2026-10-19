"""Closing CLASSIC checks: EXP-003 ingestion, EXP-005 call records, PRIV-008 horizontal access."""

from typing import Any
from uuid import UUID

import pytest

from tests.test_vacation import OIDS, Env, TokenFactory, VacationConfig
from tests.test_vacation_lifecycle import book_pending, cancel_token, decide, decision_token

RUN = "5f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10"
OTHER_RUN = "6f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10"


@pytest.fixture
def env(private_key: Any, make_token: TokenFactory) -> Env:
    return Env(private_key, make_token, VacationConfig.from_files())


def event(**extra: Any) -> dict[str, Any]:
    return {
        "event": "task_error",
        "participant_id": "3f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10",
        "session_id": "4f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10",
        "task_run_id": RUN,
        "task_id": "T-VAC-REQ",
        "feature": "vac",
        "mode": "classic",
        "order_index": 0,
        "app_version": "1.0",
        "os_version": "17.5",
        "locale": "de",
        "ts": "2026-10-19T06:00:00Z",
        **extra,
    }


# EXP-003 ---------------------------------------------------------------------------------


def test_exp_003_task_error_carries_a_code_and_whether_the_user_recovered(env: Env) -> None:
    r = env.client.post(
        "/v1/events",
        json={"events": [event(code="BLACKOUT", recovered=True)]},
        headers=env.headers("emp1"),
    )
    assert r.status_code == 202
    stored = env.client.app.state.event_sink[-1]  # type: ignore[attr-defined]
    assert (stored.code, stored.recovered) == ("BLACKOUT", True)


@pytest.mark.parametrize(
    "bad",
    [
        {"code": "x" * 49},
        {"task_id": "T-UNKNOWN"},
        {"mode": "hybrid"},
        {"reason": "Inventory week"},  # content fields do not exist
    ],
)
def test_exp_003_malformed_events_are_rejected(env: Env, bad: dict[str, Any]) -> None:
    r = env.client.post("/v1/events", json={"events": [event(**bad)]}, headers=env.headers("emp1"))
    assert r.status_code == 422


def test_exp_003_events_need_a_signed_in_user(env: Env) -> None:
    assert env.client.post("/v1/events", json={"events": [event()]}).status_code == 401


# EXP-005 ---------------------------------------------------------------------------------


def calls(env: Env) -> Any:
    return env.client.app.state.api_call_log  # type: ignore[attr-defined]


def test_exp_005_api_calls_are_counted_per_task_run_with_status_and_latency(env: Env) -> None:
    headers = env.headers("emp2") | {"X-Task-Run-Id": RUN}
    for path in ("/balance", "/requests"):
        assert env.client.get(f"/v1/vacation{path}", headers=headers).status_code == 200
    env.client.get("/v1/vacation/balance", headers=env.headers("emp2"))  # no run id: not recorded
    log = calls(env)
    assert log.count_per_task()[UUID(RUN)] == 2
    assert {c.endpoint for c in log.calls} == {"/v1/vacation/balance", "/v1/vacation/requests"}
    assert all(c.status == 200 and c.latency_ms >= 0 for c in log.calls)
    assert log.latency_ms(UUID(OTHER_RUN)) == 0


def test_exp_005_records_the_route_template_never_ids_or_content(env: Env) -> None:
    request_id = book_pending(env)
    headers = env.headers("emp2") | {"X-Task-Run-Id": RUN}
    env.client.get(f"/v1/vacation/requests/{request_id}", headers=headers)
    recorded = calls(env).calls
    assert [c.endpoint for c in recorded] == ["/v1/vacation/requests/{request_id}"]
    assert request_id not in repr(recorded) and OIDS["emp2"] not in repr(recorded)


def test_exp_005_failed_calls_are_recorded_and_bad_run_ids_are_ignored(env: Env) -> None:
    env.client.get("/v1/vacation/inbox", headers=env.headers("emp1") | {"X-Task-Run-Id": RUN})
    env.client.get("/v1/vacation/balance", headers=env.headers("emp1") | {"X-Task-Run-Id": "nope"})
    log = calls(env)
    assert [(c.endpoint, c.status) for c in log.calls] == [("/v1/vacation/inbox", 403)]


def test_exp_005_unauthenticated_calls_are_not_recorded(env: Env) -> None:
    env.client.get("/v1/vacation/balance", headers={"X-Task-Run-Id": RUN})
    env.client.get(
        "/v1/vacation/balance",
        headers={"X-Task-Run-Id": RUN, "Authorization": "Bearer not-a-token"},
    )
    assert len(calls(env).calls) == 0


def test_exp_005_the_log_is_bounded() -> None:
    from app.telemetry import ApiCall, ApiCallLog

    log = ApiCallLog(limit=3)
    for i in range(10):
        log.record(ApiCall(UUID(RUN), "GET", "/x", 200, i))
    assert [c.latency_ms for c in log.calls] == [7, 8, 9]


def test_exp_005_the_event_endpoint_itself_is_not_counted(env: Env) -> None:
    env.client.post(
        "/v1/events",
        json={"events": [event(code="X", recovered=False)]},
        headers=env.headers("emp1") | {"X-Task-Run-Id": RUN},
    )
    assert len(calls(env).calls) == 0


# PRIV-008 --------------------------------------------------------------------------------


def test_priv_008_my_requests_never_lists_other_users_requests(env: Env) -> None:
    request_id = book_pending(env, "emp2")
    mine = env.get("emp1", "/requests").json()["items"]
    assert request_id not in [i["id"] for i in mine]
    assert request_id in [i["id"] for i in env.get("emp2", "/requests").json()["items"]]


def test_priv_008_decided_requests_are_visible_only_to_the_deciding_managers_reports(
    env: Env,
) -> None:
    request_id = book_pending(env, "emp2")
    token = decision_token(env, "mgr1", request_id)
    assert decide(env, "mgr1", request_id, token).status_code == 200
    assert request_id in [i["id"] for i in env.get("mgr1", "/decisions").json()["items"]]
    assert request_id not in [i["id"] for i in env.get("mgr2", "/decisions").json()["items"]]
    assert request_id not in [i["id"] for i in env.get("emp1", "/requests").json()["items"]]


def test_priv_008_the_assigned_manager_cannot_cancel_an_employees_request(env: Env) -> None:
    request_id = book_pending(env, "emp2")
    r = env.client.post(
        "/v1/proposals",
        json={"type": "vacation_cancel", "payload": {"request_id": request_id}},
        headers=env.headers("mgr1"),
    )
    assert r.status_code in (403, 404)
    token = cancel_token(env, "emp2", request_id)
    forged = env.client.post(
        f"/v1/vacation/requests/{request_id}/cancel",
        json={"confirmation_token": token},
        headers=env.headers("mgr1"),
    )
    assert forged.status_code in (403, 404, 409)
    assert env.store.get(request_id).status == "pending"


def test_priv_008_resolving_an_audience_is_publisher_only(env: Env) -> None:
    r = env.client.post(
        "/v1/audience/resolve",
        json={"audience": {"all": True}},
        headers=env.headers("emp1"),
    )
    assert r.status_code == 403


# PRIV-002 --------------------------------------------------------------------------------


def test_priv_002_a_vacation_request_stores_no_employee_reason(env: Env) -> None:
    proposal = env.propose("emp2", "2026-11-23", "2026-11-25").json()["proposal_id"]
    token = env.confirm("emp2", proposal)
    r = env.client.post(
        "/v1/vacation/requests",
        json={
            "start": "2026-11-23",
            "end": "2026-11-25",
            "confirmation_token": token,
            "reason": "Doctor appointment",
        },
        headers=env.headers("emp2"),
    )
    assert r.status_code in (201, 422)
    assert "Doctor appointment" not in r.text
    assert "Doctor appointment" not in env.get("emp2", "/requests").text
    assert "Doctor appointment" not in env.get("mgr1", "/inbox").text
