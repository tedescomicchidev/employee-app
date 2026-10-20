"""FR-BRF-002 @api @unit: week window, grouping, conflicts, free blocks, partial labelling."""

from dataclasses import replace
from datetime import UTC, date, datetime

from app.briefing.models import WeekFetch
from app.briefing.week import WeekConfig, build_briefing, week_days, week_start
from tests.briefing_harness import MON, at, ev


def day(offset: int) -> date:
    return date.fromordinal(MON.toordinal() + offset)


def test_fr_brf_002_week_window_on_weekdays() -> None:
    wednesday = datetime(2026, 10, 21, 12, 0, tzinfo=UTC)
    assert week_start(wednesday) == MON
    assert week_start(datetime(2026, 10, 19, 0, 30, tzinfo=UTC)) == MON  # Monday 01:30 Zurich
    # Sunday 23:30 UTC is already Monday 00:30 in Zurich (CET), so the new week has begun.
    assert week_start(datetime(2026, 10, 25, 23, 30, tzinfo=UTC)) == date(2026, 10, 26)


def test_fr_brf_002_week_window_on_weekend_is_the_coming_week() -> None:
    saturday = datetime(2026, 10, 24, 10, 0, tzinfo=UTC)  # Saturday 12:00 Zurich
    start = week_start(saturday)
    assert start == date(2026, 10, 26)
    assert week_days(start)[-1] == date(2026, 11, 1)
    assert week_start(datetime(2026, 10, 25, 10, 0, tzinfo=UTC)) == start  # Sunday


def test_fr_brf_002_lists_exactly_the_returned_events_grouped_by_day() -> None:
    """Six events, two overlapping: all six are listed, none added, in Europe/Zurich."""
    events = {
        day(0): [ev("a", day(0), "09:00", "10:00"), ev("b", day(0), "09:30", "10:30")],
        day(1): [ev("c", day(1), "13:00", "14:00", attendee_count=3, online=True)],
        day(2): [ev("d", day(2), "08:00", "09:00"), ev("e", day(2), "16:00", "17:00")],
        day(4): [ev("f", day(4), "11:00", "12:00", location="Room 4")],
    }
    briefing = build_briefing(MON, WeekFetch(events))
    listed = [e.id for d in briefing.days for e in d.events]
    assert sorted(listed) == list("abcdef") and briefing.event_count == 6
    assert [len(d.events) for d in briefing.days] == [2, 1, 2, 0, 1, 0, 0]
    first = briefing.days[0].events[0]
    assert first.start.utcoffset().total_seconds() == 2 * 3600  # CEST on 2026-10-19
    assert briefing.days[1].events[0].attendee_count == 3 and briefing.days[1].events[0].online
    assert briefing.days[4].events[0].location == "Room 4"
    assert not briefing.partial and briefing.missing_days == ()


def test_fr_brf_002_conflicts_are_flagged_from_the_same_data() -> None:
    events = {
        day(0): [
            ev("a", day(0), "09:00", "10:00"),
            ev("b", day(0), "09:30", "10:30"),
            ev("c", day(0), "10:30", "11:00"),  # touches b, no overlap
        ]
    }
    briefing = build_briefing(MON, WeekFetch(events))
    by_id = {e.id: e for e in briefing.days[0].events}
    assert by_id["a"].conflicts_with == ("b",) and by_id["b"].conflicts_with == ("a",)
    assert by_id["c"].conflicts_with == () and briefing.conflict_count == 1


def test_fr_brf_002_all_day_events_are_listed_but_never_conflict_or_block() -> None:
    events = {
        day(0): [ev("a", day(0), "00:00", "23:59", all_day=True), ev("b", day(0), "09:00", "10:00")]
    }
    briefing = build_briefing(MON, WeekFetch(events))
    assert briefing.event_count == 2 and briefing.conflict_count == 0
    assert (
        len(briefing.days[0].free_blocks) == 2
    )  # 08-09 and 10-18: the all-day event blocks nothing


def test_fr_brf_002_free_blocks_of_at_least_60_minutes_in_working_hours() -> None:
    events = {
        day(0): [
            ev("a", day(0), "08:30", "09:30"),  # leaves 30 min before: too short
            ev("b", day(0), "10:30", "12:00"),  # 09:30-10:30 is exactly 60: a block
            ev("c", day(0), "16:30", "17:30"),  # 12:00-16:30 block; 17:30-18:00 too short
        ]
    }
    blocks = build_briefing(MON, WeekFetch(events)).days[0].free_blocks
    assert [(b.start.strftime("%H:%M"), b.end.strftime("%H:%M")) for b in blocks] == [
        ("09:30", "10:30"),
        ("12:00", "16:30"),
    ]
    assert [b.minutes for b in blocks] == [60, 270]


def test_fr_brf_002_weekends_have_no_free_blocks_and_hours_are_configurable() -> None:
    briefing = build_briefing(MON, WeekFetch({}))
    assert briefing.days[5].free_blocks == () and briefing.days[6].free_blocks == ()
    assert [len(d.free_blocks) for d in briefing.days[:5]] == [1] * 5
    assert briefing.days[0].free_blocks[0].minutes == 600
    assert briefing.event_count == 0 and not briefing.partial  # an empty week is not an error
    narrow = WeekConfig(
        work_start=datetime(2026, 1, 1, 9).time(), work_end=datetime(2026, 1, 1, 10).time()
    )
    assert build_briefing(MON, WeekFetch({}), narrow).days[0].free_blocks[0].minutes == 60


def test_fr_brf_002_dst_week_keeps_local_times() -> None:
    """2026-10-25 is the change back to CET: the week of 2026-10-19 spans it; 07:00 stays 07:00."""
    sunday = day(6)
    events = {sunday: [ev("x", sunday, "09:00", "10:00")]}
    event = build_briefing(MON, WeekFetch(events)).days[6].events[0]
    assert event.start.strftime("%H:%M") == "09:00"
    assert event.start.utcoffset().total_seconds() == 3600  # CET after the change
    assert day(0).isoformat() == "2026-10-19"


def test_fr_brf_005_partial_results_name_the_missing_days() -> None:
    events = {day(i): [ev(f"e{i}", day(i), "09:00", "10:00")] for i in range(3)}
    fetch = WeekFetch(events, failed_days=[day(3), day(4)])
    briefing = build_briefing(MON, fetch)
    assert briefing.partial and briefing.missing_days == (day(3), day(4))
    assert briefing.event_count == 3
    assert briefing.days[3].free_blocks == ()  # nothing is claimed about a day we could not read


def test_fr_brf_002_multi_day_event_is_one_event_listed_on_each_day() -> None:
    long = ev("conf", day(1), "00:00", "00:00", title="Offsite")
    long = replace(long, end=at(day(4), "00:00"))  # Tuesday 00:00 to Friday 00:00
    events = {day(1): [long], day(2): [long], day(3): [long]}
    briefing = build_briefing(MON, WeekFetch(events))
    assert briefing.event_count == 1
    assert [len(d.events) for d in briefing.days[1:4]] == [1, 1, 1]
    assert len(briefing.days[4].events) == 0
