"""Pure vacation rules R1-R9 (requirements.md FR-VAC). No I/O; the service supplies the data."""

from collections.abc import Callable, Iterable, Mapping
from datetime import date, timedelta

from app.vacation.models import (
    BLACKOUT,
    INSUFFICIENT_BALANCE,
    INVALID_RANGE,
    OVERLAP,
    PAST_DATE,
    PRECEDENCE,
    ZERO_DAYS,
    Balance,
    Blackout,
    DayCount,
    ExcludedDay,
    Holiday,
    VacationRequest,
    Violation,
)

BLOCKING = ("pending", "approved")


def count_days(start: date, end: date, holidays: Mapping[date, Holiday]) -> DayCount:
    """R4/R9: Mon-Fri minus full-day holidays of the work canton, split per calendar year.

    Pure calendar-date arithmetic, so a DST change cannot shift a day.
    """
    per_year: dict[int, int] = {}
    excluded: list[ExcludedDay] = []
    day = start
    while day <= end:
        holiday = holidays.get(day)
        if day.weekday() >= 5:
            excluded.append(ExcludedDay(day, "weekend"))
        elif holiday is not None and holiday.full_day:
            excluded.append(ExcludedDay(day, "holiday", holiday))
        else:
            per_year[day.year] = per_year.get(day.year, 0) + 1
        day += timedelta(days=1)
    return DayCount(sum(per_year.values()), per_year, tuple(excluded))


def balance_for(
    year: int,
    entitlement: int,
    base_carry_over: int,
    base_year: int,
    requests: Iterable[VacationRequest],
) -> Balance:
    """R1-R3. Unused days carry over without limit (R2): carry(Y+1) = remaining(Y)."""
    held = [r for r in requests if r.status in BLOCKING]
    carry = base_carry_over
    for y in range(base_year, year + 1):
        approved = sum(r.per_year.get(y, 0) for r in held if r.status == "approved")
        pending = sum(r.per_year.get(y, 0) for r in held if r.status == "pending")
        balance = Balance(y, entitlement, carry, approved, pending)
        carry = max(balance.remaining, 0)
    return balance


def blackout_applies(blackout: Blackout, region: str, store: str) -> bool:
    if blackout.scope == "region":
        return blackout.value == region
    if blackout.scope == "store":
        return blackout.value == store
    return True


def validate(
    start: date,
    end: date,
    today: date,
    count: DayCount | None,
    blackouts: Iterable[Blackout],
    existing: Iterable[VacationRequest],
    balance_for_year: Callable[[int], Balance],
) -> list[Violation]:
    """R5-R8. All failing codes, in the precedence order of FR-VAC-002.2."""
    found: dict[str, Violation] = {}
    if end < start:
        return [Violation(INVALID_RANGE)]
    if start < today:
        found[PAST_DATE] = Violation(PAST_DATE, {"today": today.isoformat()})
    if count is not None and count.counted == 0:
        found[ZERO_DAYS] = Violation(ZERO_DAYS)
    hit = next((b for b in blackouts if b.start <= end and start <= b.end), None)
    if hit is not None:
        found[BLACKOUT] = Violation(
            BLACKOUT, {"start": hit.start.isoformat(), "end": hit.end.isoformat()}
        )
    clash = [r for r in existing if r.status in BLOCKING and r.start <= end and start <= r.end]
    if clash:
        conflicts = [{"start": r.start.isoformat(), "end": r.end.isoformat()} for r in clash]
        found[OVERLAP] = Violation(
            OVERLAP,
            {"conflicts": conflicts},
        )
    if count is not None:
        short = [
            (year, days, balance_for_year(year).remaining)
            for year, days in sorted(count.per_year.items())
            if days > balance_for_year(year).remaining
        ]
        if short:
            year, days, remaining = short[0]
            found[INSUFFICIENT_BALANCE] = Violation(
                INSUFFICIENT_BALANCE, {"remaining": remaining, "requested": days, "year": year}
            )
    return [found[code] for code in PRECEDENCE if code in found]
