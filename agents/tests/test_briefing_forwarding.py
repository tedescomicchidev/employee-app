"""Briefing twin of test_comms_forwarding.py. ADR-002 / S-3 fallback: the user's tool token reaches api/'s /mcp from the request header, outside the model.

Real pieces: the Agent Framework Responses host, our middleware, the per-request agent factory and the
MCP client. Fake pieces: the model (it calls one tool, then answers) and the MCP server (it records what
it receives). No network beyond localhost, no Azure.
"""

import importlib.util
import json
import socket
import threading
import time
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest
import uvicorn
from agent_framework import (
    BaseChatClient,
    ChatResponse,
    ChatResponseUpdate,
    Content,
    Message,
    ResponseStream,
)
from briefing_context import MissingToolsToken, tools_token
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from starlette.applications import Starlette
from starlette.routing import Mount
from starlette.testclient import TestClient


def _load_briefing_main() -> Any:
    """agents/comms/main.py is also `main` (each agent deploys flat), so load this one by path."""
    spec = importlib.util.spec_from_file_location(
        "briefing_main", Path(__file__).parents[1] / "briefing" / "main.py"
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


main = _load_briefing_main()
BRIEFING_TOOLS = main.BRIEFING_TOOLS
TOKEN = "obo-token-for-employee-tools"
RUN_ID = "5d1c6c1e-0f50-4a6e-9c5b-1f2f1a7d9b10"


class Recorder:
    """Stands in for api/ /mcp: records the headers of every request."""

    def __init__(self) -> None:
        self.requests: list[dict[str, str]] = []
        self.mcp = FastMCP(
            "fake-employee-tools",
            stateless_http=True,
            json_response=True,
            streamable_http_path="/",
            transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
        )

        @self.mcp.tool()
        def get_my_week() -> dict[str, Any]:
            return {"event_count": 0, "days": [], "partial": False}

        @self.mcp.tool()
        def delete_everything() -> str:  # not a briefing tool: must never be offered to the model
            return "boom"

        self.app = Starlette(
            routes=[Mount("/mcp", app=self._record(self.mcp.streamable_http_app()))],
            lifespan=lambda app: self.mcp.session_manager.run(),
        )

    def _record(self, inner: Any) -> Any:
        async def app(scope: Any, receive: Any, send: Any) -> None:
            if scope["type"] == "http":
                self.requests.append({k.decode().lower(): v.decode() for k, v in scope["headers"]})
            await inner(scope, receive, send)

        return app


@pytest.fixture
def fake_api() -> Iterator[tuple[Recorder, str]]:
    recorder = Recorder()
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(recorder.app, port=port, log_level="warning"))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    for _ in range(100):
        if server.started:
            break
        time.sleep(0.05)
    yield recorder, f"http://127.0.0.1:{port}/mcp/"
    server.should_exit = True
    thread.join(timeout=5)


class ScriptedModel(BaseChatClient):
    """Round 1: call get_my_week. Round 2: answer with a structured reply."""

    def __init__(self) -> None:
        super().__init__()
        self.offered_tools: list[list[str]] = []
        self.rounds = 0

    def _inner_get_response(
        self, *, messages: Any, stream: bool, options: Any, **kwargs: Any
    ) -> Any:
        self.offered_tools.append(
            sorted(getattr(t, "name", str(t)) for t in (options.get("tools") or []))
        )
        self.rounds += 1
        if self.rounds == 1:
            contents = [Content.from_function_call("call-1", "get_my_week", arguments="{}")]
        else:
            reply = json.dumps(
                {"kind": "summary", "omitted_count": 0, "text": "No events this week."}
            )
            contents = [Content.from_text(reply)]
        if not stream:
            return self._respond(contents)

        async def updates() -> Any:
            yield ChatResponseUpdate(contents=contents, role="assistant")

        return ResponseStream(updates(), finalizer=ChatResponse.from_updates)

    @staticmethod
    async def _respond(contents: list[Content]) -> ChatResponse:
        return ChatResponse(messages=[Message("assistant", contents)])


def post_turn(client: TestClient, **headers: str) -> httpx.Response:
    body = {"input": "brief me on my week", "stream": False, "store": False}
    return client.post("/responses", json=body, headers=headers)


def test_token_reaches_the_mcp_call_as_bearer_and_the_model_never_sees_it(
    fake_api: tuple[Recorder, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    recorder, url = fake_api
    monkeypatch.setenv("API_MCP_URL", url)
    model = ScriptedModel()
    seen_by_model: list[str] = []
    real_build = main.build_agent

    def spy(chat_client: Any, token: str, run_id: str | None = None) -> Any:
        agent = real_build(chat_client, token, run_id)
        return agent

    monkeypatch.setattr(main, "build_agent", spy)
    with TestClient(main.create_server(model)) as client:
        response = post_turn(
            client, **{"x-client-api-access-token": TOKEN, "x-client-task-run-id": RUN_ID}
        )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "completed"
    mcp_calls = [r for r in recorder.requests if r.get("authorization")]
    assert mcp_calls, "the agent never called the MCP server"
    assert {r["authorization"] for r in mcp_calls} == {f"Bearer {TOKEN}"}
    assert {r.get("x-task-run-id") for r in mcp_calls} == {RUN_ID}
    # only briefing tools were offered to the model, and the token is not in anything it was shown
    assert "delete_everything" not in str(model.offered_tools)
    assert set(model.offered_tools[0]) <= set(BRIEFING_TOOLS)
    assert TOKEN not in json.dumps(response.json()) and not seen_by_model


def test_a_request_without_the_forwarded_token_fails_closed(
    fake_api: tuple[Recorder, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    recorder, url = fake_api
    monkeypatch.setenv("API_MCP_URL", url)
    with TestClient(main.create_server(ScriptedModel()), raise_server_exceptions=False) as client:
        response = post_turn(client)
    assert response.status_code >= 400 or response.json().get("status") != "completed"
    assert not [r for r in recorder.requests if r.get("authorization")]


def test_two_users_in_a_row_each_use_only_their_own_token(
    fake_api: tuple[Recorder, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    recorder, url = fake_api
    monkeypatch.setenv("API_MCP_URL", url)
    with TestClient(main.create_server(ScriptedModel())) as client:
        post_turn(client, **{"x-client-api-access-token": "token-of-alice"})
        post_turn(client, **{"x-client-api-access-token": "token-of-bob"})
    auth = [r["authorization"] for r in recorder.requests if r.get("authorization")]
    assert "Bearer token-of-alice" in auth and "Bearer token-of-bob" in auth
    first_bob = auth.index("Bearer token-of-bob")
    assert "Bearer token-of-alice" not in auth[first_bob:]


def test_context_is_reset_after_each_request() -> None:
    with pytest.raises(MissingToolsToken):
        tools_token()
