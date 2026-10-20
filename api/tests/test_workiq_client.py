"""FR-AUTH-004, FR-BRF-005 @api: the Work IQ client is user-delegated only and maps failures to
codes. Nothing here calls the network: the HTTP layer is replaced."""

import json
import re
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

import pytest

from app.briefing import workiq
from app.briefing.workiq import (
    CONSENT_REQUIRED,
    NO_LICENCE,
    REAUTH,
    UNAVAILABLE,
    WorkIQError,
    error_for_obo,
    error_for_status,
    parse_event,
)

APP = Path(__file__).resolve().parents[1] / "app"


def test_fr_auth_004_no_work_iq_call_uses_client_credentials() -> None:
    """The code base has no app-only Work IQ call: every token comes from an OBO exchange."""
    sources = {p: p.read_text() for p in APP.rglob("*.py")}
    offenders = [
        str(p.relative_to(APP))
        for p, text in sources.items()
        if "workiq" in text.lower() and re.search(r"acquire_token_for_client\(\s*scopes", text)
    ]
    assert offenders == []
    text = (APP / "briefing" / "workiq.py").read_text()
    assert text.count("acquire_token_on_behalf_of") == 1
    assert "client_secret" not in text and "secret" not in text.lower().replace(
        "no client secret", ""
    )
    assert workiq.SCOPE == "api://workiq.svc.cloud.microsoft/WorkIQAgent.Ask"


@pytest.mark.parametrize(
    ("status", "body", "code"),
    [
        (403, "Forbidden. Required scopes = [WorkIQAgent.Ask]", CONSENT_REQUIRED),
        (403, "Billing is not enabled for the Work IQ API", NO_LICENCE),
        (403, "", NO_LICENCE),
        (401, "", REAUTH),
        (429, "", UNAVAILABLE),
        (500, "", UNAVAILABLE),
        (503, "", UNAVAILABLE),
    ],
)
def test_fr_brf_005_http_failures_map_to_one_specific_code(
    status: int, body: str, code: str
) -> None:
    assert error_for_status(status, body) == code


@pytest.mark.parametrize(
    ("error", "code"),
    [
        ("consent_required", CONSENT_REQUIRED),
        ("interaction_required", REAUTH),
        ("invalid_grant", REAUTH),
        ("temporarily_unavailable", UNAVAILABLE),
        ("", UNAVAILABLE),
    ],
)
def test_fr_brf_005_obo_failures_map_to_one_specific_code(error: str, code: str) -> None:
    assert error_for_obo(error) == code


def test_fr_brf_002_graph_events_become_raw_events() -> None:
    graph = {
        "id": "AAMk1",
        "subject": "Standup",
        "start": {"dateTime": "2026-10-19T07:00:00.0000000", "timeZone": "UTC"},
        "end": {"dateTime": "2026-10-19T07:30:00.0000000", "timeZone": "UTC"},
        "isAllDay": False,
        "isOnlineMeeting": True,
        "location": {"displayName": "Room 4"},
        "attendees": [{}, {}, {}],
    }
    event = parse_event(graph)
    assert event is not None
    assert event.start == datetime(2026, 10, 19, 7, 0, tzinfo=UTC)
    assert (event.title, event.online, event.location, event.attendee_count) == (
        "Standup",
        True,
        "Room 4",
        3,
    )
    assert parse_event({"subject": "no times"}) is None
    assert parse_event({"id": "x", "start": {"dateTime": "garbage"}, "end": {}}) is None


class _Response:
    def __init__(self, body: Any, status: int = 200, sse: bool = False) -> None:
        self.status_code = status
        self.text = f"data: {json.dumps(body)}\n" if sse else json.dumps(body)
        self.headers = {"Content-Type": "text/event-stream" if sse else "application/json"}
        self._body = body

    def json(self) -> Any:
        return self._body


class _Http:
    """Replays MCP replies: initialize, then one `tools/call` answer per requested day."""

    def __init__(self, answers: dict[str, Any], sse: bool = False) -> None:
        self.answers, self.sse = answers, sse
        self.sent: list[dict[str, Any]] = []

    def post(self, url: str, json: Any, headers: Any, timeout: Any) -> _Response:  # noqa: A002
        self.sent.append(json)
        if json["method"] != "tools/call":
            return _Response({"jsonrpc": "2.0", "id": json.get("id"), "result": {}}, sse=self.sse)
        path = json["params"]["arguments"]["functionUrl"]
        answer = self.answers[re.search(r"startDateTime=(\d{4}-\d\d-\d\d)", path).group(1)]  # type: ignore[union-attr]
        if isinstance(answer, int):
            return _Response("denied", status=answer)
        result = {"structuredContent": answer}
        return _Response({"jsonrpc": "2.0", "id": json["id"], "result": result}, sse=self.sse)


def _client(http: _Http, monkeypatch: pytest.MonkeyPatch) -> workiq.MsalWorkIQClient:
    client = workiq.MsalWorkIQClient.__new__(workiq.MsalWorkIQClient)
    client._url, client._timeout = "https://workiq.test/mcp", 5.0  # noqa: SLF001
    monkeypatch.setattr(
        client,
        "_app_for",
        lambda _: type(
            "App",
            (),
            {
                "acquire_token_on_behalf_of": lambda self, a, scopes: {
                    "access_token": "workiq-token"
                }
            },
        )(),
    )
    monkeypatch.setattr(workiq.requests, "Session", lambda: http)
    return client


def _day(events: list[dict[str, Any]]) -> dict[str, Any]:
    return {"statusCode": 200, "data": {"value": events}}


def _graph(event_id: str, hour: int) -> dict[str, Any]:
    return {
        "id": event_id,
        "subject": event_id,
        "start": {"dateTime": f"2026-10-19T{hour:02d}:00:00", "timeZone": "UTC"},
        "end": {"dateTime": f"2026-10-19T{hour + 1:02d}:00:00", "timeZone": "UTC"},
    }


DAYS = [date(2026, 10, 19), date(2026, 10, 20)]
# Zurich midnight is 22:00 UTC the evening before (CEST): the queries start on the 18th and 19th.
WINDOW = {"2026-10-18": _day([_graph("a", 8)]), "2026-10-19": _day([])}


@pytest.mark.parametrize("sse", [False, True])
def test_fr_brf_002_week_is_read_with_the_users_obo_token(
    monkeypatch: pytest.MonkeyPatch, sse: bool
) -> None:
    http = _Http(WINDOW, sse=sse)
    fetch = _client(http, monkeypatch).fetch_week("user-assertion", DAYS)
    assert [e.id for e in fetch.events_by_day[DAYS[0]]] == ["a"] and fetch.events_by_day[
        DAYS[1]
    ] == []
    assert fetch.failed_days == []
    methods = [m["method"] for m in http.sent]
    assert (
        methods[:2] == ["initialize", "notifications/initialized"]
        and methods.count("tools/call") == 2
    )


def test_fr_brf_005_some_days_failing_makes_a_partial_week(monkeypatch: pytest.MonkeyPatch) -> None:
    answers = {"2026-10-18": _day([_graph("a", 8)]), "2026-10-19": {"statusCode": 504}}
    fetch = _client(_Http(answers), monkeypatch).fetch_week("u", DAYS)
    assert list(fetch.events_by_day) == [DAYS[0]] and fetch.failed_days == [DAYS[1]]


def test_fr_brf_005_all_days_failing_is_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    answers = {"2026-10-18": 503, "2026-10-19": 503}
    with pytest.raises(WorkIQError) as exc:
        _client(_Http(answers), monkeypatch).fetch_week("u", DAYS)
    assert exc.value.code == UNAVAILABLE


def test_fr_brf_005_a_user_level_failure_is_never_a_partial_briefing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A billing or consent 403 on one day is about the account: no half-briefing is shown."""
    answers = {"2026-10-18": _day([_graph("a", 8)]), "2026-10-19": {"statusCode": 403}}
    with pytest.raises(WorkIQError) as exc:
        _client(_Http(answers), monkeypatch).fetch_week("u", DAYS)
    assert exc.value.code == NO_LICENCE


def test_fr_brf_005_more_than_the_page_cap_is_not_passed_off_as_the_whole_day(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    truncated = {"statusCode": 200, "data": {"value": [_graph("a", 8)], "@odata.nextLink": "x"}}
    answers = {"2026-10-18": truncated, "2026-10-19": _day([])}
    fetch = _client(_Http(answers), monkeypatch).fetch_week("u", DAYS)
    assert fetch.failed_days == [DAYS[0]] and list(fetch.events_by_day) == [DAYS[1]]


def test_fr_brf_005_unconfigured_work_iq_is_unavailable() -> None:
    with pytest.raises(WorkIQError) as exc:
        workiq.UnconfiguredWorkIQClient().fetch_week("u", DAYS)
    assert exc.value.code == UNAVAILABLE


def test_fr_brf_005_a_failure_names_its_stage_and_never_its_content(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    """The log says where Work IQ failed (http:403, rpc, graph, obo) so the cause can be found."""
    secret = "Quarterly planning with ACME"

    class Http(_Http):
        def post(self, url: str, json: Any, headers: Any, timeout: Any) -> _Response:  # noqa: A002
            if json["method"] == "tools/call":
                return _Response(
                    {"jsonrpc": "2.0", "id": 1, "error": {"code": -32602, "message": secret}}
                )
            return super().post(url, json, headers, timeout)

    with pytest.raises(WorkIQError) as exc:
        _client(Http({}), monkeypatch).fetch_week("u", DAYS)
    assert exc.value.code == UNAVAILABLE
    assert exc.value.stage == "rpc:-32602:call_function"
    assert secret not in caplog.text and "workiq-token" not in caplog.text


def test_fr_brf_005_an_obo_failure_logs_its_entra_error_numbers_only(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = workiq.MsalWorkIQClient.__new__(workiq.MsalWorkIQClient)
    rejected = {
        "error": "invalid_client",
        "error_codes": [700211],
        "error_description": "AADSTS700211: No matching federated record for jane@example.com",
    }
    app = type("App", (), {"acquire_token_on_behalf_of": lambda self, a, scopes: rejected})()
    monkeypatch.setattr(client, "_app_for", lambda _: app)
    with pytest.raises(WorkIQError) as exc:
        client.fetch_week("u", DAYS)
    assert exc.value.stage == "obo:invalid_client:700211"
    assert "jane" not in exc.value.stage and exc.value.code == UNAVAILABLE
