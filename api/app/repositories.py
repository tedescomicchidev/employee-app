import json
import threading
from dataclasses import dataclass, field, replace
from datetime import datetime
from pathlib import Path
from typing import Protocol

from app.announcements.models import Announcement, Draft, InboxItem

SEED_FILE = Path(__file__).parent / "seed" / "employees.json"


@dataclass(frozen=True)
class Employee:
    oid: str
    name: str
    active: bool
    role: str = "Employee"
    store: str = ""
    region: str = ""


@dataclass(frozen=True)
class Proposal:
    id: str
    oid: str
    action: str
    draft: Draft
    expires_at: datetime


@dataclass
class ConfirmationToken:
    token: str
    oid: str
    action: str
    payload_hash: str
    expires_at: datetime
    announcement_id: str | None = None


class Directory(Protocol):
    def get(self, oid: str) -> Employee | None: ...
    def active(self) -> list[Employee]: ...


class AnnouncementStore(Protocol):
    def publish(self, announcement: Announcement, recipients: list[str]) -> Announcement:
        """Atomic and idempotent on `announcement.id`: a second call returns the stored one."""

    def get(self, announcement_id: str) -> Announcement | None: ...
    def list_for(self, oid: str) -> list[tuple[Announcement, InboxItem]]: ...
    def get_for(self, oid: str, announcement_id: str) -> tuple[Announcement, InboxItem] | None:
        """Only items in `oid`'s own inbox; anything else is None (FR-ANN-002.3)."""

    def mark_read(self, oid: str, announcement_id: str, at: datetime) -> InboxItem | None:
        """Idempotent; touches only `oid`'s inbox item (FR-ANN-003.2)."""

    def count(self) -> int: ...


class ConfirmationStore(Protocol):
    def save_proposal(self, proposal: Proposal) -> None: ...
    def get_proposal(self, proposal_id: str) -> Proposal | None: ...
    def save_token(self, token: ConfirmationToken) -> None: ...
    def get_token(self, token: str) -> ConfirmationToken | None: ...


class SeedDirectory:
    """Employees from the seed file (ADR-010); a Cosmos-backed directory replaces it later."""

    def __init__(self, employees: list[Employee]) -> None:
        self._by_oid = {e.oid: e for e in employees}

    @classmethod
    def from_file(cls, path: Path = SEED_FILE) -> "SeedDirectory":
        rows = json.loads(path.read_text())
        return cls(
            [
                Employee(r["oid"], r["name"], r["active"], r["role"], r["store"], r["region"])
                for r in rows
            ]
        )

    def get(self, oid: str) -> Employee | None:
        return self._by_oid.get(oid)

    def active(self) -> list[Employee]:
        return [e for e in self._by_oid.values() if e.active]


@dataclass
class InMemoryAnnouncementStore:
    _announcements: dict[str, Announcement] = field(default_factory=dict)
    _inbox: dict[str, dict[str, InboxItem]] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def publish(self, announcement: Announcement, recipients: list[str]) -> Announcement:
        with self._lock:
            existing = self._announcements.get(announcement.id)
            if existing is not None:
                return existing
            self._announcements[announcement.id] = announcement
            for oid in recipients:
                self._inbox.setdefault(oid, {})[announcement.id] = InboxItem(
                    announcement.id, oid, announcement.status
                )
            return announcement

    def get(self, announcement_id: str) -> Announcement | None:
        return self._announcements.get(announcement_id)

    def list_for(self, oid: str) -> list[tuple[Announcement, InboxItem]]:
        items = [
            (self._announcements[i.announcement_id], i)
            for i in self._inbox.get(oid, {}).values()
            if i.status == "published"
        ]
        return sorted(items, key=lambda pair: pair[0].published_at, reverse=True)

    def get_for(self, oid: str, announcement_id: str) -> tuple[Announcement, InboxItem] | None:
        item = self._inbox.get(oid, {}).get(announcement_id)
        if item is None or item.status != "published":
            return None
        return self._announcements[announcement_id], item

    def mark_read(self, oid: str, announcement_id: str, at: datetime) -> InboxItem | None:
        with self._lock:
            item = self._inbox.get(oid, {}).get(announcement_id)
            if item is None or item.status != "published":
                return None
            if item.read_at is None:
                item = replace(item, read_at=at)
                self._inbox[oid][announcement_id] = item
            return item

    def count(self) -> int:
        return len(self._announcements)


@dataclass
class InMemoryConfirmationStore:
    _proposals: dict[str, Proposal] = field(default_factory=dict)
    _tokens: dict[str, ConfirmationToken] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def save_proposal(self, proposal: Proposal) -> None:
        with self._lock:
            self._proposals[proposal.id] = proposal

    def get_proposal(self, proposal_id: str) -> Proposal | None:
        return self._proposals.get(proposal_id)

    def save_token(self, token: ConfirmationToken) -> None:
        with self._lock:
            self._tokens[token.token] = token

    def get_token(self, token: str) -> ConfirmationToken | None:
        return self._tokens.get(token)
