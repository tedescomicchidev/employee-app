"""JSON shapes shared by the REST routes and the rule-violation errors."""

from typing import Any

from app.vacation.models import Balance, DayCount, ExcludedDay, Holiday


def holiday_json(h: Holiday, lang: str | None = None) -> dict[str, Any]:
    return {
        "canton": h.canton,
        "date": h.date.isoformat(),
        "name": h.name(lang),
        "names": h.names,
        "full_day": h.full_day,
    }


def excluded_json(e: ExcludedDay, lang: str | None = None) -> dict[str, Any]:
    row: dict[str, Any] = {"date": e.date.isoformat(), "kind": e.kind}
    if e.holiday is not None:
        row["name"] = e.holiday.name(lang)
        row["names"] = e.holiday.names
    return row


def count_json(count: DayCount) -> dict[str, Any]:
    return {
        "counted_days": count.counted,
        "per_year": {str(y): d for y, d in sorted(count.per_year.items())},
        "excluded": [excluded_json(e) for e in count.excluded],
    }


def partial_review_json(count: DayCount, balance: Balance) -> dict[str, Any]:
    """What the review shows even when the request is blocked (mockup: INSUFFICIENT_BALANCE)."""
    return {**count_json(count), "remaining": balance.remaining, "balance_year": balance.year}
