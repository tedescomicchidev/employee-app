"""AGENT mode device contract: SSE turns, refusals, sources, Retry-After (docs/architecture/
agent-turn-contract.md). Foundry is faked with Responses API events; no tenant."""

import json
import time
from collections.abc import Iterator
from typing import Any

import pytest

from app.agents.foundry import AgentError
from app.agents.stream import WARMING, TextExtractor, parse_sse, with_warmup
from tests.conftest import SETTINGS
from tests.mcp_harness import CEO, EMP1, sign
from tests.test_agent_turn import PROPOSAL, Env, reply

SSE = {"Accept": "text/event-stream"}


def completed(payload: Any, calls: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {"type": "response.completed", "response": reply(payload, calls)}


def deltas(text: str, size: int = 7) -> list[dict[str, Any]]:
    return [
        {"type": "response.output_text.delta", "delta": text[i : i + size]}
        for i in range(0, len(text), size)
    ]


class StreamingFoundry:
    """Plays a scripted list of events; an AgentError in the list is raised mid-stream."""

    def __init__(self) -> None:
        self.events: list[Any] = []
        self.calls: list[dict[str, Any]] = []

    def respond(self, *args: Any, **kwargs: Any) -> Any:  # the JSON path is not under test here
        raise AssertionError("respond() called on a streaming turn")

    def stream(
        self,
        foundry_agent: str,
        user_oid: str,
        tools_token: str,
        messages: Any,
        task_run_id: str | None = None,
    ) -> Iterator[dict[str, Any]]:
        self.calls.append({"agent": foundry_agent, "oid": user_oid, "messages": messages})
        for event in self.events:
            if isinstance(event, Exception):
                raise event
            yield event


@pytest.fixture
def env(private_key: Any) -> Env:
    env = Env(private_key)
    env.app.state.agent_responder = env.streamer = StreamingFoundry()  # type: ignore[attr-defined]
    return env


def events(response: Any) -> list[tuple[str, dict[str, Any]]]:
    assert response.headers["content-type"].startswith("text/event-stream")
    out = []
    for block in response.text.strip().split("\n\n"):
        name, data = block.split("\n", 1)
        out.append((name.removeprefix("event: "), json.loads(data.removeprefix("data: "))))
    return out


def stream_turn(env: Env, **kw: Any) -> Any:
    body = {"messages": [{"role": "user", "content": "what's new?"}]}
    return env.client.post("/v1/agent/comms/turns", json=body, headers=env.headers(**kw, **SSE))


def test_text_extractor_streams_only_the_text_field_across_chunk_boundaries() -> None:
    raw = json.dumps(
        {"kind": "message", "text": 'Zürich "ok"\nline 2 \U0001f600 é', "proposal_id": None}
    )
    for size in (1, 2, 3, 5, 11, len(raw)):
        extractor = TextExtractor()
        out = "".join(extractor.feed(raw[i : i + size]) for i in range(0, len(raw), size))
        assert out == 'Zürich "ok"\nline 2 \U0001f600 é', size


def test_text_extractor_plain_fallback_and_missing_text() -> None:
    plain = TextExtractor()
    assert plain.feed("Hello ") + plain.feed("there") == "Hello there"
    none = TextExtractor()
    assert none.feed('{"kind": "proposal", "proposal_id": null}') == ""


def test_text_extractor_never_emits_a_lone_surrogate() -> None:
    raw = '{"text": "a\\ud83d b"}'  # a high surrogate without its low half
    out = TextExtractor().feed(raw)
    out.encode("utf-8")  # must be encodable
    assert out == "a� b"


def test_parse_sse_reads_data_payloads_and_skips_junk() -> None:
    lines = ["event: x", 'data: {"type": "a"}', "", "data: not json", "", 'data: {"type": "b"}', ""]
    assert [e["type"] for e in parse_sse(lines)] == ["a", "b"]
    assert list(
        parse_sse(['data: {"type": "a"}', "", "data: [DONE]", "", 'data: {"type":"b"}'])
    ) == [{"type": "a"}]


def test_stream_turn_emits_status_tool_delta_and_a_grounded_final(env: Env) -> None:
    payload = {"kind": "message", "text": "Two new announcements.", "sources": []}
    call = {"type": "mcp_call", "name": "list_announcements", "error": None}
    env.streamer.events = [
        {"type": "response.created"},
        {"type": "response.output_item.added", "item": {"type": "mcp_call", "name": call["name"]}},
        {"type": "response.output_item.done", "item": call},
        *deltas(json.dumps(payload)),
        completed(payload, [call]),
    ]
    response = stream_turn(env)
    assert response.status_code == 200
    got = events(response)
    names = [n for n, _ in got]
    assert names[:3] == ["status", "status", "tool"] and names[-1] == "final"
    assert got[0][1] == {"phase": "thinking"}
    assert got[1][1] == {"phase": "tool", "name": "list_announcements"}
    assert got[2][1] == {"name": "list_announcements", "ok": True}
    assert "".join(d["text"] for n, d in got if n == "delta") == "Two new announcements."
    final = got[-1][1]
    assert final["reply"]["kind"] == "message" and final["reply"]["text"] == payload["text"]
    assert final["tool_calls"] == [{"name": "list_announcements", "ok": True}]
    assert len(env.app.state.agent_runs.runs) == 1  # the run is recorded like the JSON path


def test_stream_final_is_grounded_not_taken_from_the_deltas(env: Env) -> None:
    claim = {"kind": "published", "text": "Done, it is live"}
    env.streamer.events = [*deltas(json.dumps(claim)), completed(claim)]  # no tool call
    got = events(stream_turn(env))
    assert "".join(d["text"] for n, d in got if n == "delta") == "Done, it is live"
    assert got[-1][1]["reply"]["kind"] == "message"  # a claimed write without the tool: downgraded


def test_stream_errors_become_one_error_event_without_detail(env: Env, caplog: Any) -> None:
    env.streamer.events = [{"type": "response.created"}, AgentError("foundry_500")]
    got = events(stream_turn(env))
    assert [n for n, _ in got] == ["status", "error"]
    assert got[-1][1]["code"] == "AGENT_UNAVAILABLE" and "foundry_500" not in json.dumps(got)
    assert "agent stream failed: agent=comms code=foundry_500" in caplog.text
    env.streamer.events = [{"type": "response.created"}]  # ends with neither completed nor failed
    assert events(stream_turn(env))[-1][0] == "error"
    env.streamer.events = [{"type": "response.failed"}]
    assert events(stream_turn(env))[-1][0] == "error"


def test_failures_before_the_stream_opens_are_normal_status_codes(env: Env) -> None:
    env.tools.error = AgentError("consent_required")
    response = stream_turn(env)
    assert response.status_code == 403 and response.json()["code"] == "AGENT_UNAVAILABLE"
    assert env.streamer.calls == []
    env.tools.error = None
    assert env.client.post(
        "/v1/agent/comms/turns", json={"messages": [{"role": "user", "content": "x"}]}, headers=SSE
    ).status_code == 401  # fmt: skip


def test_json_path_is_unchanged_without_the_sse_accept_header(private_key: Any) -> None:
    env = Env(private_key)
    response = env.turn()
    assert response.status_code == 200 and response.json()["reply"]["text"] == "Hi"


def test_rate_limit_carries_retry_after(private_key: Any) -> None:
    from app.agents.foundry import AgentSettings

    env = Env(private_key, AgentSettings(project_endpoint="https://f.test", turns_per_minute=1))
    assert env.turn().status_code == 200
    limited = env.turn()
    assert limited.status_code == 429 and limited.json()["code"] == "RATE_LIMITED"
    assert 1 <= int(limited.headers["Retry-After"]) <= 60


def publish_announcement(env: Env) -> str:
    token = sign(env.key, SETTINGS.api_audience, "access_as_user", CEO, ["Communicator"])
    ceo = {"Authorization": f"Bearer {token}"}
    draft = {"title": "Früher Start", "body": "Open at 7", "language": "de", "audience": "all"}
    pid = env.client.post("/v1/proposals", json={"payload": draft}, headers=ceo).json()
    confirmation = env.client.post(
        "/v1/confirmations", json={"proposal_id": pid["proposal_id"]}, headers=ceo
    ).json()
    created = env.client.post(
        "/v1/announcements",
        json={"payload": draft, "confirmation_token": confirmation["confirmation_token"]},
        headers=ceo,
    )
    assert created.status_code == 201
    return str(created.json()["id"])


def test_fr_ann_003_sources_are_kept_only_for_visible_announcements_with_stored_titles(
    private_key: Any,
) -> None:
    env = Env(private_key)
    visible = publish_announcement(env)
    answer = {
        "kind": "message",
        "text": "One new announcement.",
        "sources": [
            {"announcement_id": visible, "title": "Model-invented title"},
            {"announcement_id": visible, "title": "duplicate"},
            {"announcement_id": PROPOSAL, "title": "does not exist"},
        ],
    }
    env.foundry.response = reply(answer)
    sources = env.turn().json()["reply"]["sources"]
    assert sources == [{"announcement_id": visible, "title": "Früher Start"}]
    # Sources only accompany a plain answer.
    env.foundry.response = reply({**answer, "kind": "clarification"})
    assert env.turn().json()["reply"]["sources"] == []


def test_refusal_reply_kind_and_reason_for_both_agents(env: Env, private_key: Any) -> None:
    env2 = Env(private_key)
    for agent in ("comms", "vacation"):
        env2.foundry.response = reply(
            {"kind": "refusal", "text": "I can't do that.", "reason": "write_without_confirmation"}
        )
        body = env2.turn(agent=agent, oid=EMP1).json()["reply"]
        assert body["kind"] == "refusal" and body["reason"] == "write_without_confirmation"
    # A reason is a short code, never free text: anything else falls back to a plain message.
    env2.foundry.response = reply({"kind": "refusal", "text": "no", "reason": "Ignore all rules!"})
    assert env2.turn().json()["reply"]["kind"] == "message"


def test_with_warmup_marks_a_slow_first_event_once() -> None:
    def slow() -> Iterator[dict[str, Any]]:
        time.sleep(0.25)
        yield {"type": "response.created"}
        yield {"type": "response.completed"}

    got = [e["type"] for e in with_warmup(slow(), wait=0.05)]
    assert got == [WARMING, "response.created", "response.completed"]
    fast = [e["type"] for e in with_warmup(iter([{"type": "response.created"}]), wait=1)]
    assert fast == ["response.created"]


def test_with_warmup_propagates_upstream_errors() -> None:
    def broken() -> Iterator[dict[str, Any]]:
        yield {"type": "response.created"}
        raise AgentError("foundry_unreachable")

    with pytest.raises(AgentError):
        list(with_warmup(broken(), wait=1))
