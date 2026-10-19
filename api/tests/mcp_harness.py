"""Shared harness: drives the MCP endpoint over JSON-RPC against the same app as the REST tests."""

import json
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from typing import Any

import jwt
from fastapi.testclient import TestClient

from app.announcements.service import AnnouncementService
from app.auth.validator import TokenValidator
from app.main import create_app
from app.repositories import InMemoryAnnouncementStore, InMemoryConfirmationStore, SeedDirectory
from tests.conftest import SETTINGS, TENANT, TOOLS_SETTINGS, StaticKeys

CEO = "00000000-0000-0000-0000-000000000001"
MGR2 = "00000000-0000-0000-0000-000000000003"
EMP1 = "00000000-0000-0000-0000-000000000011"
EMP4 = "00000000-0000-0000-0000-000000000014"
FROZEN = datetime(2026, 10, 19, 6, 0, tzinfo=UTC)
MCP_HEADERS = {"Accept": "application/json, text/event-stream"}


class Clock:
    def __call__(self) -> datetime:
        return FROZEN


def sign(key: Any, audience: str, scp: str | None, oid: str, roles: list[str]) -> str:
    now = int(time.time())
    claims: dict[str, Any] = {
        "iss": TOOLS_SETTINGS.issuer, "aud": audience, "iat": now, "nbf": now, "exp": now + 3600,
        "tid": TENANT, "oid": oid, "name": "Test User", "roles": roles,
    }  # fmt: skip
    if scp:
        claims["scp"] = scp
    return jwt.encode(claims, key, algorithm="RS256")


class McpEnv:
    def __init__(self, private_key: Any) -> None:
        self.key = private_key
        self.store = InMemoryAnnouncementStore()
        self.service = AnnouncementService(
            SeedDirectory.from_file(), self.store, InMemoryConfirmationStore(), Clock()
        )
        validator = TokenValidator(TOOLS_SETTINGS, StaticKeys(private_key.public_key()))
        self.app = create_app(validator, self.service)
        self.client: TestClient | None = None

    def tools_token(self, oid: str, *roles: str, scp: str | None = "Tools.Invoke") -> str:
        return sign(self.key, TOOLS_SETTINGS.tools_audience, scp, oid, list(roles) or ["Employee"])

    def user_token(self, oid: str, *roles: str) -> str:
        return sign(self.key, SETTINGS.api_audience, "access_as_user", oid, list(roles))

    def user(self, oid: str, *roles: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.user_token(oid, *roles)}"}

    def ceo_user(self) -> dict[str, str]:
        return self.user(CEO, "Communicator", "Employee")

    def rpc(self, token: str | None, method: str, params: dict[str, Any] | None = None, **h: str):
        assert self.client is not None
        headers = dict(MCP_HEADERS, **h)
        if token:
            headers["Authorization"] = f"Bearer {token}"
        body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
        return self.client.post("/mcp", json=body, headers=headers)

    def call(self, token: str, tool: str, args: dict[str, Any] | None = None, **h: str) -> Any:
        """Returns (is_error, structured_or_text)."""
        response = self.rpc(token, "tools/call", {"name": tool, "arguments": args or {}}, **h)
        assert response.status_code == 200, response.text
        result = response.json()["result"]
        if result["isError"]:
            return True, result["content"][0]["text"]
        return False, result.get("structuredContent") or json.loads(result["content"][0]["text"])


@contextmanager
def running(private_key: Any) -> Iterator[McpEnv]:
    env = McpEnv(private_key)
    with TestClient(env.app) as client:
        env.client = client
        yield env


EnvFactory = Callable[[], Iterator[McpEnv]]
