import hashlib
import json
from dataclasses import dataclass, field
from datetime import date, datetime

ACTION_OPT_IN = "set_briefing_optin"


@dataclass(frozen=True)
class OptInDraft:
    """What the confirm card shows and the token is bound to: turn the briefing on or off."""

    enabled: bool

    def canonical(self) -> dict[str, bool]:
        return {"enabled": self.enabled}

    def payload_hash(self) -> str:
        raw = json.dumps(self.canonical(), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(raw.encode()).hexdigest()


@dataclass(frozen=True)
class OptInState:
    opted_in: bool
    opted_in_at: datetime | None = None


@dataclass(frozen=True)
class RawEvent:
    """One event as Work IQ returned it (UTC instants). Held in memory for one request only."""

    id: str
    title: str
    start: datetime
    end: datetime
    all_day: bool = False
    location: str = ""
    online: bool = False
    attendee_count: int = 0


@dataclass(frozen=True)
class WeekFetch:
    """Work IQ's answer for the week: events per Zurich day, and the days it could not answer."""

    events_by_day: dict[date, list[RawEvent]]
    failed_days: list[date] = field(default_factory=list)


@dataclass(frozen=True)
class BriefEvent:
    id: str
    title: str
    start: datetime  # Europe/Zurich
    end: datetime
    all_day: bool
    location: str
    online: bool
    attendee_count: int
    conflicts_with: tuple[str, ...] = ()


@dataclass(frozen=True)
class FreeBlock:
    start: datetime
    end: datetime

    @property
    def minutes(self) -> int:
        return int((self.end - self.start).total_seconds() // 60)


@dataclass(frozen=True)
class BriefDay:
    day: date
    events: tuple[BriefEvent, ...]
    free_blocks: tuple[FreeBlock, ...]


@dataclass(frozen=True)
class Briefing:
    week_start: date
    week_end: date
    days: tuple[BriefDay, ...]
    event_count: int  # distinct events; a multi-day event is listed on each day it covers
    conflict_count: int
    missing_days: tuple[date, ...] = ()

    @property
    def partial(self) -> bool:
        return bool(self.missing_days)
