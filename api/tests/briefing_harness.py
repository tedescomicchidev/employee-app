"""Shared fakes for the briefing tests: a Work IQ client that records every call."""

from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from datetime import UTC, date, datetime, time
from typing import Any

from fastapi.testclient import TestClient

from app.announcements.service import AnnouncementService
from app.auth.validator import TokenValidator
from app.briefing.models import RawEvent, WeekFetch
from app.briefing.service import BriefingService
from app.briefing.store import InMemoryBriefingSettingsStore
from app.briefing.week import ZURICH
from app.briefing.workiq import WorkIQError
from app.main import create_app
from app.repositories import InMemoryAnnouncementStore, InMemoryConfirmationStore, SeedDirectory
from tests.conftest import TOOLS_SETTINGS, StaticKeys
from tests.mcp_harness import CEO, EMP1, MGR2, Clock, McpEnv

EMP2 = "00000000-0000-0000-0000-000000000012"
MGR1 = "00000000-0000-0000-0000-000000000002"
MON = date(2026, 10, 19)  # the frozen clock's Monday


def at(day: date, hhmm: str) -> datetime:
    """A Europe/Zurich wall-clock time as the UTC instant Work IQ would return."""
    hour, minute = map(int, hhmm.split(":"))
    return datetime.combine(day, time(hour, minute), tzinfo=ZURICH).astimezone(UTC)


def ev(
    event_id: str,
    day: date,
    start: str,
    end: str,
    title: str | None = None,
    **extra: Any,
) -> RawEvent:
    return RawEvent(event_id, title or f"Event {event_id}", at(day, start), at(day, end), **extra)


class FakeWorkIQ:
    """Returns the configured events (by Zurich day) and remembers who asked."""

    def __init__(self) -> None:
        self.events: dict[date, list[RawEvent]] = {}
        self.failed_days: list[date] = []
        self.error: str | None = None
        self.assertions: list[str] = []

    def fetch_week(self, user_assertion: str, days: Sequence[date]) -> WeekFetch:
        self.assertions.append(user_assertion)
        if self.error:
            raise WorkIQError(self.error)
        answered = {d: list(self.events.get(d, [])) for d in days if d not in self.failed_days}
        return WeekFetch(answered, list(self.failed_days))

    @property
    def calls(self) -> int:
        return len(self.assertions)


class BriefEnv(McpEnv):
    """McpEnv with a briefing service on the frozen clock and a fake Work IQ."""

    def __init__(self, private_key: Any, **app_kwargs: Any) -> None:
        self.key = private_key
        directory = SeedDirectory.from_file()
        self.work_iq = FakeWorkIQ()
        self.service = AnnouncementService(
            directory, InMemoryAnnouncementStore(), InMemoryConfirmationStore(), Clock()
        )
        self.briefing = BriefingService(
            directory,
            InMemoryBriefingSettingsStore(),
            InMemoryConfirmationStore(),
            self.work_iq,
            clock=Clock(),
        )
        validator = TokenValidator(TOOLS_SETTINGS, StaticKeys(private_key.public_key()))
        self.app = create_app(
            validator,
            self.service,
            briefing_service=self.briefing,
            directory=directory,
            **app_kwargs,
        )
        self.client: TestClient | None = None

    def roles(self, who: str) -> tuple[str, ...]:
        return ("Manager", "Employee") if who in (CEO, MGR1, MGR2) else ("Employee",)

    def tool(self, who: str, name: str, args: dict[str, Any] | None = None) -> Any:
        return self.call(self.tools_token(who, *self.roles(who)), name, args)

    def rest(self, who: str, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        assert self.client is not None
        return self.client.request(
            method, path, json=body, headers=self.user(who, *self.roles(who))
        )

    def confirm(self, who: str, proposal_id: str) -> str:
        """The app's confirm card: only a user token mints a confirmation token."""
        r = self.rest(
            who, "POST", "/v1/confirmations", {"type": "briefing", "proposal_id": proposal_id}
        )
        assert r.status_code == 200, r.text
        return r.json()["confirmation_token"]

    def opt_in(self, who: str, enabled: bool = True) -> None:
        proposal = self.rest(
            who, "POST", "/v1/proposals", {"type": "briefing", "payload": {"enabled": enabled}}
        )
        assert proposal.status_code == 200, proposal.text
        token = self.confirm(who, proposal.json()["proposal_id"])
        done = self.rest(
            who, "POST", "/v1/briefing/opt-in", {"enabled": enabled, "confirmation_token": token}
        )
        assert done.status_code == 200, done.text


@contextmanager
def running(private_key: Any, **app_kwargs: Any) -> Iterator[BriefEnv]:
    env = BriefEnv(private_key, **app_kwargs)
    with TestClient(env.app) as client:
        env.client = client
        yield env


__all__ = [
    "BriefEnv",
    "FakeWorkIQ",
    "EMP1",
    "EMP2",
    "CEO",
    "MGR1",
    "MGR2",
    "MON",
    "at",
    "ev",
    "running",
]
