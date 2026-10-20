"""FR-BRF-002: week window, grouping, conflicts and free blocks, pure, from the returned events."""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from app.briefing.models import BriefDay, BriefEvent, Briefing, FreeBlock, RawEvent, WeekFetch

ZURICH = ZoneInfo("Europe/Zurich")
WEEK_DAYS = 7


@dataclass(frozen=True)
class WeekConfig:
    """Free-block rule: >= 60 minutes inside working hours Mon-Fri (FR-BRF-002.2, proposed)."""

    work_start: time = time(8, 0)
    work_end: time = time(18, 0)
    min_free: timedelta = timedelta(minutes=60)


def week_start(now: datetime) -> date:
    """Most recent Monday (Europe/Zurich); on Saturday and Sunday the coming Monday."""
    today = now.astimezone(ZURICH).date()
    if today.weekday() >= 5:
        return today + timedelta(days=7 - today.weekday())
    return today - timedelta(days=today.weekday())


def week_days(start: date) -> list[date]:
    return [start + timedelta(days=i) for i in range(WEEK_DAYS)]


def local(day: date, at: time = time(0, 0)) -> datetime:
    return datetime.combine(day, at, tzinfo=ZURICH)


def day_bounds(day: date) -> tuple[datetime, datetime]:
    """Midnight to midnight in Zurich; 23 or 25 hours on a DST change."""
    return local(day), local(day + timedelta(days=1))


def _brief(raw: RawEvent, conflicts: tuple[str, ...]) -> BriefEvent:
    return BriefEvent(
        id=raw.id,
        title=raw.title,
        start=raw.start.astimezone(ZURICH),
        end=raw.end.astimezone(ZURICH),
        all_day=raw.all_day,
        location=raw.location,
        online=raw.online,
        attendee_count=raw.attendee_count,
        conflicts_with=conflicts,
    )


def _overlaps(a: RawEvent, b: RawEvent) -> bool:
    return a.start < b.end and b.start < a.end


def _conflicts(events: list[RawEvent]) -> dict[str, tuple[str, ...]]:
    timed = [e for e in events if not e.all_day and e.end > e.start]
    found: dict[str, list[str]] = {}
    for i, a in enumerate(timed):
        for b in timed[i + 1 :]:
            if a.id != b.id and _overlaps(a, b):
                found.setdefault(a.id, []).append(b.id)
                found.setdefault(b.id, []).append(a.id)
    return {k: tuple(v) for k, v in found.items()}


def _free_blocks(day: date, events: list[RawEvent], config: WeekConfig) -> tuple[FreeBlock, ...]:
    if day.weekday() >= 5:
        return ()
    open_at, close_at = local(day, config.work_start), local(day, config.work_end)
    busy = sorted(
        (max(e.start, open_at), min(e.end, close_at))
        for e in events
        if not e.all_day and e.end > open_at and e.start < close_at
    )
    blocks: list[FreeBlock] = []
    cursor = open_at
    for start, end in busy:
        if start - cursor >= config.min_free:
            blocks.append(FreeBlock(cursor.astimezone(ZURICH), start.astimezone(ZURICH)))
        cursor = max(cursor, end)
    if close_at - cursor >= config.min_free:
        blocks.append(FreeBlock(cursor.astimezone(ZURICH), close_at))
    return tuple(blocks)


def build_briefing(start: date, fetch: WeekFetch, config: WeekConfig | None = None) -> Briefing:
    """Every returned event is listed on each day it covers; nothing is dropped or added."""
    config = config or WeekConfig()
    days = week_days(start)
    all_events = {e.id: e for events in fetch.events_by_day.values() for e in events}
    conflicts = _conflicts(list(all_events.values()))
    built: list[BriefDay] = []
    for day in days:
        lo, hi = day_bounds(day)
        # A failed day has no entry; an answered day may legitimately be empty.
        raw = [e for e in fetch.events_by_day.get(day, []) if e.start < hi and e.end > lo]
        raw.sort(key=lambda e: (e.start, e.end, e.id))
        built.append(
            BriefDay(
                day,
                tuple(_brief(e, conflicts.get(e.id, ())) for e in raw),
                () if day in fetch.failed_days else _free_blocks(day, raw, config),
            )
        )
    return Briefing(
        week_start=days[0],
        week_end=days[-1],
        days=tuple(built),
        event_count=len(all_events),
        conflict_count=sum(len(v) for v in conflicts.values()) // 2,
        missing_days=tuple(sorted(fetch.failed_days)),
    )
