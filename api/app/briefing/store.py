import threading
from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol


class BriefingSettingsStore(Protocol):
    """`briefing_optin` per user: the consent record (PRIV-003). No calendar content is stored."""

    def get(self, oid: str) -> datetime | None:
        """When the user opted in, or None."""

    def opt_in(self, oid: str, at: datetime) -> None: ...

    def delete(self, oid: str) -> None:
        """Opt-out removes the record (FR-BRF-001.3)."""


@dataclass
class InMemoryBriefingSettingsStore:
    _opted_in: dict[str, datetime] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def get(self, oid: str) -> datetime | None:
        return self._opted_in.get(oid)

    def opt_in(self, oid: str, at: datetime) -> None:
        with self._lock:
            self._opted_in.setdefault(oid, at)

    def delete(self, oid: str) -> None:
        with self._lock:
            self._opted_in.pop(oid, None)
