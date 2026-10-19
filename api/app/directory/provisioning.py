"""Fills the employee directory from each signed-in user's own Graph profile (ADR-010).

Only the caller's own attributes and manager are read, with the caller's delegated permissions, so
there is no app-only directory access. Failures leave the user unprovisioned (`NOT_PROVISIONED`).
"""

import logging
import threading
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Protocol

from app.auth.principal import Principal, Role
from app.directory.graph import GraphError, GraphProfile, GraphProfileClient
from app.directory.settings import DirectorySettings
from app.repositories import Employee
from app.vacation.models import CANTONS

log = logging.getLogger("app.directory")

SOURCE_GRAPH = "graph"
SOURCE_MANAGER = "graph-manager"  # known only as someone's manager; replaced when they sign in


class WritableDirectory(Protocol):
    def get(self, oid: str) -> Employee | None: ...
    def upsert(self, employee: Employee) -> None: ...


def role_name(principal: Principal) -> str:
    """The names the audience picker uses (Publisher, Manager, Employee)."""
    if principal.has_role(Role.COMMUNICATOR):
        return "Publisher"
    return "Manager" if principal.has_role(Role.MANAGER) else "Employee"


def parse_canton(raw: str | None) -> str | None:
    """A canton code like `ZH`; anything else is unknown, so the app asks HR instead of guessing."""
    value = (raw or "").strip().upper()
    return value if value in CANTONS else None


def parse_region(raw: str | None) -> str:
    """`de-CH` -> `DE`; empty when unknown."""
    return (raw or "").strip().replace("_", "-").split("-")[0].upper()[:2]


class Provisioner:
    def __init__(
        self,
        directory: WritableDirectory,
        client: GraphProfileClient,
        settings: DirectorySettings,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._directory = directory
        self._client = client
        self._settings = settings
        self._clock = clock
        self._lock = threading.Lock()
        self._failed: dict[str, datetime] = {}

    def ensure(self, principal: Principal) -> None:
        """Best effort: refresh the caller's record when missing or older than the TTL.

        A failed lookup is remembered per user for `retry_after`, not repeated on every call.
        """
        if not self._settings.enabled or not principal.assertion:
            return
        if not self._needs_lookup(principal.oid, self._clock()):
            return
        with self._lock:
            now = self._clock()
            if not self._needs_lookup(principal.oid, now):  # another request just did it
                return
            if self._lookup(principal, now):
                self._failed.pop(principal.oid, None)
            else:
                self._failed[principal.oid] = now
                self._forget_old_failures(now)

    def _needs_lookup(self, oid: str, now: datetime) -> bool:
        failed_at = self._failed.get(oid)
        if failed_at is not None and now - failed_at < self._settings.retry_after:
            return False
        existing = self._directory.get(oid)
        return existing is None or not (existing.source == "seed" or self._fresh(existing, now))

    def _lookup(self, principal: Principal, now: datetime) -> bool:
        try:
            profile = self._client.fetch(principal.assertion, self._settings.attributes)
        except GraphError as exc:
            log.warning("directory lookup failed code=%s", exc.code)
            return False
        except Exception:  # noqa: BLE001 - never let a directory problem break the request
            log.warning("directory lookup failed code=unexpected")
            return False
        if profile.oid != principal.oid:
            log.warning("directory lookup ignored: profile does not match the token")
            return False
        self._store(principal, profile, now)
        return True

    def _forget_old_failures(self, now: datetime) -> None:
        """Keeps the failure memory small: entries past `retry_after` no longer matter."""
        retry_after = self._settings.retry_after
        for oid in [o for o, at in self._failed.items() if now - at >= retry_after]:
            del self._failed[oid]

    def _fresh(self, employee: Employee, now: datetime) -> bool:
        return (
            employee.source == SOURCE_GRAPH
            and employee.fetched_at is not None
            and now - employee.fetched_at < self._settings.ttl
        )

    def _store(self, principal: Principal, profile: GraphProfile, now: datetime) -> None:
        s = self._settings
        self._directory.upsert(
            Employee(
                oid=principal.oid,
                name=profile.display_name or principal.display_name,
                active=True,
                role=role_name(principal),
                store=profile.attributes.get(s.store_attribute, ""),
                region=parse_region(profile.attributes.get(s.region_attribute)),
                canton=parse_canton(profile.attributes.get(s.canton_attribute)),
                manager_oid=profile.manager_oid,
                source=SOURCE_GRAPH,
                fetched_at=now,
            )
        )
        manager = profile.manager_oid
        if manager and manager != principal.oid and self._directory.get(manager) is None:
            # Enough to route and show the approver; their own attributes arrive when they sign in.
            self._directory.upsert(
                Employee(
                    oid=manager,
                    name=profile.manager_name,
                    active=True,
                    role="",
                    source=SOURCE_MANAGER,
                )
            )
