"""Work IQ calendar reads, user-delegated (OBO) only (FR-AUTH-004, ADR-004).

Docs: learn.microsoft.com/microsoft-365/copilot/extensibility/work-iq/permissions
(`WorkIQAgent.Ask`, delegated, admin consent), .../work-iq/mcp/tool-reference (`call_function` on
`/me/calendarView`), learn.microsoft.com/azure/foundry/agents/how-to/tools/work-iq (403: billing
not enabled, or scopes not consented), and
learn.microsoft.com/entra/identity-platform/v2-oauth2-on-behalf-of-flow.
No client secret: the app registration trusts the container app's managed identity. There is no
client-credentials call anywhere in this module, and nothing here caches a result.

Unverified against a real tenant (spike S-2): tool name and response shape follow the Learn pages.
"""

import itertools
import json
import logging
from collections.abc import Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any, Protocol

import jwt
import msal
import requests

from app.briefing.models import RawEvent, WeekFetch
from app.briefing.week import ZURICH, day_bounds

log = logging.getLogger("app.briefing.workiq")

SCOPE = "api://workiq.svc.cloud.microsoft/WorkIQAgent.Ask"
MCP_URL = "https://workiq.svc.cloud.microsoft/mcp"

UNAVAILABLE = "unavailable"
NO_LICENCE = "no_licence"
CONSENT_REQUIRED = "consent_required"
REAUTH = "reauth"


class WorkIQError(Exception):
    """`code` is one of the constants above; it never holds tokens, event text or descriptions."""

    def __init__(self, code: str, stage: str = "") -> None:
        super().__init__(code)
        self.code = code
        # Where it failed (`obo:...`, `http:403:...`, `rpc:...`): for the log only.
        self.stage = stage


class WorkIQClient(Protocol):
    def fetch_week(self, user_assertion: str, days: Sequence[date]) -> WeekFetch:
        """Events for each Zurich day. Days that failed come back in `failed_days`; if none could
        be read, or the failure is about the user (consent, licence, token), raise WorkIQError."""


class UnconfiguredWorkIQClient:
    """Used where Work IQ is not set up (no managed identity or app id): fails closed."""

    def fetch_week(self, user_assertion: str, days: Sequence[date]) -> WeekFetch:
        raise WorkIQError(UNAVAILABLE)


def error_for_status(status: int, body: str) -> str:
    """Learn troubleshooting: 403 with `Required scopes` is missing admin consent; any other 403 is
    billing or licence; 401 is a token problem; the rest is the service."""
    if status == 403:
        return CONSENT_REQUIRED if "required scopes" in body.lower() else NO_LICENCE
    if status == 401:
        return REAUTH
    return UNAVAILABLE


# Entra codes for "the app was not consented for this permission" (65001) or "no administrator
# approved it for the tenant" (90094, 90095, 65005). `invalid_grant` carries them, so it is not
# always a session problem: only the other codes (revoked or expired sign-in) mean "sign in again".
_CONSENT_CODES = frozenset({65001, 65005, 90094, 90095, 90008})


def error_for_obo(error: str, numbers: Sequence[int] = ()) -> str:
    if error == "consent_required" or _CONSENT_CODES & set(numbers):
        return CONSENT_REQUIRED
    if error in ("interaction_required", "invalid_grant"):
        return REAUTH
    return UNAVAILABLE


def parse_event(item: dict[str, Any]) -> RawEvent | None:
    """A Graph event to a RawEvent; None when it has no usable id or times."""
    try:
        start = _instant(item["start"])
        end = _instant(item["end"])
        event_id = str(item["id"])
    except (KeyError, TypeError, ValueError):
        return None
    location = item.get("location") or {}
    return RawEvent(
        id=event_id,
        title=str(item.get("subject") or ""),
        start=start,
        end=end,
        all_day=bool(item.get("isAllDay")),
        location=str(location.get("displayName") or "") if isinstance(location, dict) else "",
        online=bool(item.get("isOnlineMeeting")),
        attendee_count=len(item.get("attendees") or []),
    )


def _instant(value: dict[str, Any]) -> datetime:
    """Graph returns `{dateTime, timeZone}`; UTC unless the zone is named."""
    raw = datetime.fromisoformat(str(value["dateTime"]).rstrip("Z")[:26])
    zone = str(value.get("timeZone") or "UTC")
    local_zone = zone in ("W. Europe Standard Time", "Europe/Zurich")
    return raw.replace(tzinfo=ZURICH if local_zone else UTC)


class _Rpc:
    """Minimal MCP streamable-HTTP client: initialize, then `tools/call`."""

    def __init__(self, url: str, token: str, timeout: float) -> None:
        self._url, self._timeout = url, timeout
        self._headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }
        self._ids = itertools.count(1)
        self._http = requests.Session()

    def _post(self, method: str, params: dict[str, Any], notify: bool = False) -> dict[str, Any]:
        body: dict[str, Any] = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notify:
            body["id"] = next(self._ids)
        try:
            response = self._http.post(
                self._url, json=body, headers=self._headers, timeout=self._timeout
            )
        except requests.RequestException as exc:
            raise WorkIQError(UNAVAILABLE, f"http:unreachable:{type(exc).__name__}") from None
        if response.status_code >= 400:
            raise WorkIQError(
                error_for_status(response.status_code, response.text),
                f"http:{response.status_code}:{method}",
            )
        session = response.headers.get("Mcp-Session-Id")
        if session:
            self._headers["Mcp-Session-Id"] = session
        if notify or not response.text.strip():
            return {}
        return _decode(response)

    def start(self) -> None:
        self._post(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "employee-api", "version": "1"},
            },
        )
        self._post("notifications/initialized", {}, notify=True)

    def call(self, tool: str, arguments: dict[str, Any]) -> dict[str, Any]:
        message = self._post("tools/call", {"name": tool, "arguments": arguments})
        result = message.get("result") or {}
        if message.get("error") or result.get("isError"):
            # The JSON-RPC error code, or "tool_error"; never the message, which may carry content.
            code = (message.get("error") or {}).get("code", "tool_error")
            raise WorkIQError(UNAVAILABLE, f"rpc:{code}:{tool}")
        structured = result.get("structuredContent")
        return structured if isinstance(structured, dict) else {}


def _decode(response: requests.Response) -> dict[str, Any]:
    if "text/event-stream" in response.headers.get("Content-Type", ""):
        for line in response.text.splitlines():
            if line.startswith("data:"):
                try:
                    return dict(json.loads(line[5:].strip()))
                except ValueError:
                    continue
        raise WorkIQError(UNAVAILABLE, "rpc:bad_event_stream")
    try:
        return dict(response.json())
    except ValueError:
        raise WorkIQError(UNAVAILABLE, "rpc:bad_json") from None


@dataclass(frozen=True)
class WorkIQApp:
    """The app registration that does the exchange: the token's `aud` says which one."""

    client_id: str
    audiences: tuple[str, ...]


class MsalWorkIQClient:
    def __init__(
        self,
        tenant_id: str,
        apps: Sequence[WorkIQApp],
        managed_identity_client_id: str,
        url: str = MCP_URL,
        timeout: float = 25.0,
    ) -> None:
        self._url, self._timeout = url, timeout
        self._identity = msal.ManagedIdentityClient(
            msal.UserAssignedManagedIdentity(client_id=managed_identity_client_id),
            http_client=requests.Session(),
        )
        self._tenant = tenant_id
        self._apps = list(apps)
        self._clients: dict[str, msal.ConfidentialClientApplication] = {}

    def _assertion(self) -> str:
        token = self._identity.acquire_token_for_client(resource="api://AzureADTokenExchange")
        if not token.get("access_token"):
            raise WorkIQError(UNAVAILABLE, "obo:managed_identity")
        return str(token["access_token"])

    def _app_for(self, user_assertion: str) -> msal.ConfidentialClientApplication:
        """REST calls carry an `access_as_user` token and MCP tool calls a `Tools.Invoke` one; the
        exchange must be made by the app the token was issued for. The token was validated
        upstream, so only its audience is read here."""
        aud = jwt.decode(user_assertion, options={"verify_signature": False}).get("aud")
        for app in self._apps:
            if aud in app.audiences:
                break
        else:
            raise WorkIQError(UNAVAILABLE, "obo:no_app_for_audience")
        if app.client_id not in self._clients:
            self._clients[app.client_id] = msal.ConfidentialClientApplication(
                app.client_id,
                authority=f"https://login.microsoftonline.com/{self._tenant}",
                client_credential={"client_assertion": self._assertion},
            )
        return self._clients[app.client_id]

    def fetch_week(self, user_assertion: str, days: Sequence[date]) -> WeekFetch:
        result = self._app_for(user_assertion).acquire_token_on_behalf_of(
            user_assertion, scopes=[SCOPE]
        )
        token = result.get("access_token")
        if not token:
            error = str(result.get("error") or "")  # an OAuth error code, never the description
            # The numeric AADSTS codes (for example 700211) say which setting Entra rejected.
            codes = [c for c in result.get("error_codes") or [] if isinstance(c, int)]
            suffix = f":{'+'.join(str(c) for c in codes)}" if codes else ""
            raise WorkIQError(error_for_obo(error, codes), f"obo:{error or 'unknown'}{suffix}")
        rpc = _Rpc(self._url, str(token), self._timeout)
        rpc.start()

        def one(day: date) -> tuple[date, list[RawEvent] | WorkIQError]:
            lo, hi = day_bounds(day)
            path = (
                "/me/calendarView?startDateTime="
                f"{lo.astimezone(UTC):%Y-%m-%dT%H:%M:%SZ}&endDateTime={hi.astimezone(UTC):%Y-%m-%dT%H:%M:%SZ}"
                "&$top=100&$orderby=start/dateTime"
            )
            try:
                data = rpc.call("call_function", {"functionUrl": path})
            except WorkIQError as exc:
                return day, exc
            if data.get("statusCode", 200) != 200:
                status = int(data["statusCode"])
                return day, WorkIQError(error_for_status(status, ""), f"graph:{status}")
            body = data.get("data") or {}
            events = [e for e in map(parse_event, body.get("value") or []) if e is not None]
            if body.get("@odata.nextLink"):  # more than the page cap: not the whole day
                return day, WorkIQError(UNAVAILABLE, "graph:next_link")
            return day, events

        with ThreadPoolExecutor(max_workers=4) as pool:
            answers = list(pool.map(one, days))
        by_day: dict[date, list[RawEvent]] = {}
        failures: list[tuple[date, WorkIQError]] = []
        for day, answer in answers:
            if isinstance(answer, WorkIQError):
                failures.append((day, answer))
            else:
                by_day[day] = answer
        for _, error in failures:
            if error.code != UNAVAILABLE:  # about the user, not the service: no partial briefing
                raise error
        if not by_day:
            stages = sorted({e.stage for _, e in failures if e.stage})
            raise WorkIQError(UNAVAILABLE, ";".join(stages) or "all_days_failed")
        log.info("work iq week days_ok=%d days_failed=%d", len(by_day), len(failures))
        for _, error in failures:
            log.warning("work iq day failed code=%s stage=%s", error.code, error.stage)
        return WeekFetch(by_day, [d for d, _ in failures])
