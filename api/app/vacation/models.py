import hashlib
import json
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any

ACTION_REQUEST = "create_vacation_request"
ACTION_CANCEL = "cancel_vacation_request"
CANTONS = "AG AI AR BE BL BS FR GE GL GR JU LU NE NW OW SG SH SO SZ TG TI UR VD VS ZG ZH".split()

# Reason codes in the precedence of FR-VAC-002.2.
INVALID_RANGE = "INVALID_RANGE"
PAST_DATE = "PAST_DATE"
ZERO_DAYS = "ZERO_DAYS"
BLACKOUT = "BLACKOUT"
OVERLAP = "OVERLAP"
INSUFFICIENT_BALANCE = "INSUFFICIENT_BALANCE"
PRECEDENCE = (INVALID_RANGE, PAST_DATE, ZERO_DAYS, BLACKOUT, OVERLAP, INSUFFICIENT_BALANCE)


@dataclass(frozen=True)
class Holiday:
    canton: str
    date: date
    names: dict[str, str]
    full_day: bool = True

    def name(self, lang: str | None = None) -> str:
        for key in (lang, "de", "en"):
            if key and key in self.names:
                return self.names[key]
        return next(iter(self.names.values()), "")


@dataclass(frozen=True)
class Blackout:
    start: date
    end: date
    scope: str = "all"  # all | region | store
    value: str | None = None


@dataclass(frozen=True)
class ExcludedDay:
    date: date
    kind: str  # weekend | holiday
    holiday: Holiday | None = None


@dataclass(frozen=True)
class DayCount:
    counted: int
    per_year: dict[int, int]
    excluded: tuple[ExcludedDay, ...]


@dataclass(frozen=True)
class Balance:
    year: int
    entitlement: int
    carried_over: int
    approved: int
    pending: int

    @property
    def remaining(self) -> int:
        return self.entitlement + self.carried_over - self.approved - self.pending


@dataclass(frozen=True)
class Violation:
    code: str
    details: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class VacationDraft:
    start: date
    end: date

    def canonical(self) -> dict[str, str]:
        return {"start": self.start.isoformat(), "end": self.end.isoformat()}

    def payload_hash(self) -> str:
        """Confirmation tokens are bound to the exact dates (FR-AUTH-006.1)."""
        raw = json.dumps(self.canonical(), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(raw.encode()).hexdigest()


@dataclass(frozen=True)
class VacationRequest:
    id: str
    owner_oid: str
    approver_oid: str
    approver_name: str
    start: date
    end: date
    counted_days: int
    per_year: dict[int, int]
    excluded: tuple[ExcludedDay, ...]
    canton: str  # canton used for counting; later canton changes never touch it (FR-VAC-006.4)
    created_at: datetime
    status: str = "pending"
    owner_name: str = ""
    decided_at: datetime | None = None  # approve, reject or cancel time
    decided_by: str | None = None
    decision_reason: str | None = None  # rejection reason, <= 500 chars (FR-VAC-004.1)


@dataclass(frozen=True)
class CancelDraft:
    request_id: str

    def canonical(self) -> dict[str, str]:
        return {"request_id": self.request_id}

    def payload_hash(self) -> str:
        """The cancel token is bound to this one request (FR-AUTH-006.1)."""
        raw = json.dumps(self.canonical(), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(raw.encode()).hexdigest()
