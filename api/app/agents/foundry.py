"""API -> Foundry hosted agent, on behalf of the signed-in user (ADR-002, auth-flows.md flow 2).

Docs: learn.microsoft.com/azure/foundry/agents/how-to/use-on-behalf-of-flow (app-managed OBO,
`x-client-*` forwarding, `x-ms-user-identity`) and .../how-to/isolate-sessions-per-user.

Three credentials, never mixed:
- `Authorization`: the API's own managed-identity token for https://ai.azure.com. It does not
  represent the user and is not forwarded to the agent container.
- `x-ms-user-identity`: the validated caller's oid (never a client-supplied value).
- `x-client-api-access-token`: OBO token for the tools resource app (`Tools.Invoke`). Foundry
  forwards `x-client-*` headers to the agent container and does not exchange them. The agent calls
  `/mcp` with it as its Bearer token (agents/comms/main.py). T-user never leaves the API.
- `x-client-task-run-id`: the EXP-005 run id, so the MCP audit joins to the task run.
"""

import os
import time
from collections.abc import Iterator
from dataclasses import dataclass, field
from typing import Any, Protocol

import httpx
import msal
import requests

FOUNDRY_RESOURCE = "https://ai.azure.com"
TOOLS_HEADER = "x-client-api-access-token"
RUN_HEADER = "x-client-task-run-id"
USER_HEADER = "x-ms-user-identity"
TIMEOUT_SECONDS = 60
STREAM_DEADLINE_SECONDS = 120  # a whole streamed turn; TIMEOUT_SECONDS is per read
API_VERSION = "v1"


class AgentError(Exception):
    """A call failed. `code` is short and stable; it never holds tokens, prompts or replies."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class AgentSettings:
    project_endpoint: str = ""  # https://<account>.services.ai.azure.com/api/projects/<project>
    managed_identity_client_id: str = ""
    agents: dict[str, str] = field(
        default_factory=lambda: {  # route -> Foundry
            "comms": "comms",
            "vacation": "vacation",
            "briefing": "briefing",
        }
    )
    turns_per_minute: int = 20  # NFR-011
    max_messages: int = 20
    max_message_chars: int = 4000

    @property
    def enabled(self) -> bool:
        return bool(self.project_endpoint)


def load_agent_settings() -> AgentSettings:
    env = os.environ
    return AgentSettings(
        project_endpoint=env.get("FOUNDRY_PROJECT_ENDPOINT", "").rstrip("/"),
        managed_identity_client_id=env.get("AZURE_CLIENT_ID", ""),
        agents={
            "comms": env.get("COMMS_AGENT_NAME", "comms"),
            "vacation": env.get("VACATION_AGENT_NAME", "vacation"),
            "briefing": env.get("BRIEFING_AGENT_NAME", "briefing"),
        },
        turns_per_minute=int(env.get("AGENT_TURNS_PER_MINUTE", "20")),
    )


class ToolsTokenClient(Protocol):
    def acquire(self, user_assertion: str) -> str: ...


class AgentResponder(Protocol):
    def respond(
        self,
        foundry_agent: str,
        user_oid: str,
        tools_token: str,
        messages: list[dict[str, str]],
        task_run_id: str | None = None,
    ) -> dict[str, Any]: ...

    def stream(
        self,
        foundry_agent: str,
        user_oid: str,
        tools_token: str,
        messages: list[dict[str, str]],
        task_run_id: str | None = None,
    ) -> Iterator[dict[str, Any]]: ...


class MsalToolsTokenClient:
    """OBO for the tools resource app. Same federated-credential pattern as the Graph client."""

    def __init__(
        self, tenant_id: str, api_client_id: str, tools_audience: str, managed_identity_id: str
    ) -> None:
        self._scopes = [f"{tools_audience}/Tools.Invoke"]
        self._identity = msal.ManagedIdentityClient(
            msal.UserAssignedManagedIdentity(client_id=managed_identity_id),
            http_client=requests.Session(),
        )
        self._app = msal.ConfidentialClientApplication(
            api_client_id,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
            client_credential={"client_assertion": self._assertion},
        )

    def _assertion(self) -> str:
        result = self._identity.acquire_token_for_client(resource="api://AzureADTokenExchange")
        token = result.get("access_token")
        if not token:
            raise AgentError("managed_identity")
        return str(token)

    def acquire(self, user_assertion: str) -> str:
        result = self._app.acquire_token_on_behalf_of(user_assertion, scopes=self._scopes)
        token = result.get("access_token")
        if not token:
            # consent_required, interaction_required, invalid_grant: a code, never the description.
            raise AgentError(str(result.get("error") or "obo_failed"))
        return str(token)


class HttpAgentResponder:
    def __init__(self, settings: AgentSettings) -> None:
        self._settings = settings
        self._identity = msal.ManagedIdentityClient(
            msal.UserAssignedManagedIdentity(client_id=settings.managed_identity_client_id),
            http_client=requests.Session(),
        )

    def _workload_token(self) -> str:
        token = self._identity.acquire_token_for_client(resource=FOUNDRY_RESOURCE).get(
            "access_token"
        )
        if not token:
            raise AgentError("foundry_token")
        return str(token)

    def _request(
        self,
        foundry_agent: str,
        user_oid: str,
        tools_token: str,
        messages: list[dict[str, str]],
        task_run_id: str | None,
        stream: bool,
    ) -> tuple[str, dict[str, str], dict[str, Any]]:
        url = (
            f"{self._settings.project_endpoint}/agents/{foundry_agent}"
            f"/endpoint/protocols/openai/responses?api-version={API_VERSION}"
        )
        headers = {
            "Authorization": f"Bearer {self._workload_token()}",
            USER_HEADER: user_oid,
            TOOLS_HEADER: tools_token,
        }
        if task_run_id:
            headers[RUN_HEADER] = task_run_id
        # store=false: the app holds the history on the device (PRIV-004, overview.md section 5).
        body = {"input": messages, "stream": stream, "background": False, "store": False}
        return url, headers, body

    def respond(
        self,
        foundry_agent: str,
        user_oid: str,
        tools_token: str,
        messages: list[dict[str, str]],
        task_run_id: str | None = None,
    ) -> dict[str, Any]:
        url, headers, body = self._request(
            foundry_agent, user_oid, tools_token, messages, task_run_id, stream=False
        )
        try:
            response = httpx.post(url, json=body, headers=headers, timeout=TIMEOUT_SECONDS)
        except httpx.HTTPError:
            raise AgentError("foundry_unreachable") from None
        if response.status_code != 200:
            raise AgentError(f"foundry_{response.status_code}")
        result: dict[str, Any] = response.json()
        if result.get("status") != "completed":
            raise AgentError(f"agent_{result.get('status') or 'failed'}")
        return result

    def stream(
        self,
        foundry_agent: str,
        user_oid: str,
        tools_token: str,
        messages: list[dict[str, str]],
        task_run_id: str | None = None,
    ) -> Iterator[dict[str, Any]]:
        """The Responses API server-sent events, one dict per event (`stream: true`)."""
        from app.agents.stream import parse_sse  # local: stream.py imports this module's errors

        url, headers, body = self._request(
            foundry_agent, user_oid, tools_token, messages, task_run_id, stream=True
        )
        headers["Accept"] = "text/event-stream"
        deadline = time.monotonic() + STREAM_DEADLINE_SECONDS
        try:
            with httpx.stream(
                "POST", url, json=body, headers=headers, timeout=TIMEOUT_SECONDS
            ) as response:
                if response.status_code != 200:
                    raise AgentError(f"foundry_{response.status_code}")
                for event in parse_sse(response.iter_lines()):
                    if time.monotonic() > deadline:
                        raise AgentError("foundry_timeout")
                    yield event
        except httpx.HTTPError:
            raise AgentError("foundry_unreachable") from None
