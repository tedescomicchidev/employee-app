import json
import threading
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Protocol

from app.vacation.models import Blackout, Holiday, VacationRequest

SEED_DIR = Path(__file__).parent.parent / "seed"


class VacationStore(Protocol):
    def add(self, request: VacationRequest) -> VacationRequest:
        """Atomic and idempotent on `request.id`: a second call returns the stored one."""

    def get(self, request_id: str) -> VacationRequest | None: ...
    def for_owner(self, oid: str) -> list[VacationRequest]: ...
    def pending_for_approver(self, oid: str) -> list[VacationRequest]: ...
    def for_approver(self, oid: str) -> list[VacationRequest]:
        """Every request assigned to `oid`, any status, in the same order as `for_owner`."""

    def replace_if_status(
        self, request: VacationRequest, expected_status: str
    ) -> VacationRequest | None:
        """Atomic transition: stores `request` only while the stored status is `expected_status`."""


@dataclass
class InMemoryVacationStore:
    _requests: dict[str, VacationRequest] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def add(self, request: VacationRequest) -> VacationRequest:
        with self._lock:
            return self._requests.setdefault(request.id, request)

    def get(self, request_id: str) -> VacationRequest | None:
        return self._requests.get(request_id)

    def replace_if_status(
        self, request: VacationRequest, expected_status: str
    ) -> VacationRequest | None:
        with self._lock:
            current = self._requests.get(request.id)
            if current is None or current.status != expected_status:
                return None
            self._requests[request.id] = request
            return request

    def for_owner(self, oid: str) -> list[VacationRequest]:
        mine = [r for r in self._requests.values() if r.owner_oid == oid]
        return sorted(mine, key=lambda r: (r.start, r.created_at))

    def for_approver(self, oid: str) -> list[VacationRequest]:
        rows = [r for r in self._requests.values() if r.approver_oid == oid]
        return sorted(rows, key=lambda r: (r.start, r.created_at))

    def pending_for_approver(self, oid: str) -> list[VacationRequest]:
        rows = [
            r for r in self._requests.values() if r.approver_oid == oid and r.status == "pending"
        ]
        return sorted(rows, key=lambda r: (r.start, r.created_at))


@dataclass(frozen=True)
class SeedRequest:
    id: str
    owner: str
    start: date
    end: date
    status: str
    decided_at: datetime | None = None
    reason: str | None = None


@dataclass(frozen=True)
class VacationConfig:
    """Policy and calendars; values are HR-CONFIRM / HUMAN_CONFIRMATION_REQUIRED seeds."""

    entitlement: int = 25
    carry_over: dict[str, int] = field(default_factory=dict)
    blackouts: tuple[Blackout, ...] = ()
    holidays: tuple[Holiday, ...] = ()
    seed_requests: tuple[SeedRequest, ...] = ()

    @classmethod
    def from_files(cls, directory: Path = SEED_DIR) -> "VacationConfig":
        policy = json.loads((directory / "vacation.json").read_text())
        calendar = json.loads((directory / "holidays.json").read_text())
        return cls(
            entitlement=policy["entitlement_per_year"],
            carry_over=policy["carry_over"],
            blackouts=tuple(
                Blackout(
                    date.fromisoformat(b["start"]),
                    date.fromisoformat(b["end"]),
                    b["scope"],
                    b["value"],
                )
                for b in policy["blackouts"]
            ),
            holidays=tuple(
                Holiday(h["canton"], date.fromisoformat(h["date"]), h["names"], h["full_day"])
                for h in calendar["holidays"]
            ),
            seed_requests=tuple(
                SeedRequest(
                    r["id"],
                    r["owner"],
                    date.fromisoformat(r["start"]),
                    date.fromisoformat(r["end"]),
                    r["status"],
                    datetime.fromisoformat(r["decided_at"]) if r.get("decided_at") else None,
                    r.get("reason"),
                )
                for r in policy["requests"]
            ),
        )
