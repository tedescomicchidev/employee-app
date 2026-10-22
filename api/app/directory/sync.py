"""The employee directory from Microsoft Graph, for the whole tenant (ADR-010, superseded in part).

ADR-010 first chose to read only the signed-in user's own profile (delegated). That leaves the
directory knowing only people who have opened the app, so audience counts and approver routing
cannot reach anyone else. This module lists the people who hold an app role on `employee-api`, with
their attributes and manager, using the container app's managed identity (no secret). It needs two
Graph **application** permissions, granted by a human: `User.Read.All` and `Application.Read.All`.

Scope of the exception: names, the enabled state, three configured HR attributes, the manager and
the app role. Never mail, calendar, files or Work IQ: those stay user-delegated (FR-AUTH-004).

Docs: learn.microsoft.com/graph/api/user-list, .../serviceprincipal-list-approleassignedto,
learn.microsoft.com/graph/json-batching, learn.microsoft.com/graph/paging,
learn.microsoft.com/entra/identity/managed-identities-azure-resources/assign-app-role-managed-identity-azure-cli.
"""

import asyncio
import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Protocol

import msal
import requests

from app.directory.graph import GRAPH, GraphError
from app.directory.provisioning import parse_canton, parse_region
from app.directory.settings import DirectorySettings
from app.repositories import Employee

log = logging.getLogger("app.directory.sync")

SOURCE_SYNC = "graph-sync"
TIMEOUT_SECONDS = 20
BATCH_SIZE = 20  # Graph's JSON batch limit
NO_ROLE = "00000000-0000-0000-0000-000000000000"  # assigned to the app without a specific app role
# The audience picker's names (Publisher, Manager, Employee), highest privilege first.
ROLE_NAMES = {"Communicator": "Publisher", "Manager": "Manager", "Employee": "Employee"}


@dataclass(frozen=True)
class GraphMember:
    oid: str
    display_name: str
    enabled: bool
    user_type: str
    attributes: dict[str, str] = field(default_factory=dict)
    manager_oid: str | None = None


class GraphDirectoryClient(Protocol):
    def list_members(self, attributes: list[str]) -> list[GraphMember]:
        """Every user in the tenant, with the given attributes and manager."""

    def role_assignments(self) -> tuple[dict[str, str], int]:
        """oid -> highest `employee-api` role (Publisher, Manager, Employee) for users assigned one,
        and how many assignments to groups were skipped (group members are not expanded)."""


def highest_role(values: list[str]) -> str:
    for value in ROLE_NAMES:  # ordered by privilege
        if value in values:
            return ROLE_NAMES[value]
    return "Employee"


class MsalGraphDirectoryClient:
    def __init__(self, api_client_id: str, managed_identity_client_id: str) -> None:
        self._api_client_id = api_client_id
        self._identity = msal.ManagedIdentityClient(
            msal.UserAssignedManagedIdentity(client_id=managed_identity_client_id),
            http_client=requests.Session(),
        )
        self._http = requests.Session()

    def _headers(self) -> dict[str, str]:
        result = self._identity.acquire_token_for_client(resource="https://graph.microsoft.com")
        token = result.get("access_token")
        if not token:
            raise GraphError("managed_identity")
        return {"Authorization": f"Bearer {token}"}

    def _get(self, url: str, call: str) -> dict[str, Any]:
        try:
            response = self._http.get(url, headers=self._headers(), timeout=TIMEOUT_SECONDS)
        except requests.RequestException:
            raise GraphError(f"graph_{call}_unreachable") from None
        if response.status_code != 200:
            raise GraphError(f"graph_{call}_{response.status_code}")
        body: dict[str, Any] = response.json()
        return body

    def _pages(self, url: str, call: str) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        while url:
            page = self._get(url, call)
            items += page.get("value") or []
            url = page.get("@odata.nextLink") or ""
        return items

    def list_members(self, attributes: list[str]) -> list[GraphMember]:
        select = ",".join(
            dict.fromkeys(["id", "displayName", "accountEnabled", "userType", *attributes])
        )
        rows = self._pages(f"{GRAPH}/users?$select={select}&$top=999", "users")
        managers = self._managers([str(r["id"]) for r in rows if r.get("id")])
        return [
            GraphMember(
                oid=str(r["id"]),
                display_name=str(r.get("displayName") or ""),
                enabled=bool(r.get("accountEnabled", True)),
                user_type=str(r.get("userType") or "Member"),
                attributes={a: str(r[a]) for a in attributes if r.get(a)},
                manager_oid=managers.get(str(r["id"])),
            )
            for r in rows
            if r.get("id")
        ]

    def _managers(self, oids: list[str]) -> dict[str, str]:
        """`GET /users/{id}/manager` for everyone, 20 to a batch (no manager is a 404)."""
        found: dict[str, str] = {}
        failed = 0
        for start in range(0, len(oids), BATCH_SIZE):
            chunk = oids[start : start + BATCH_SIZE]
            body = {
                "requests": [
                    {"id": str(i), "method": "GET", "url": f"/users/{oid}/manager?$select=id"}
                    for i, oid in enumerate(chunk)
                ]
            }
            try:
                response = self._http.post(
                    f"{GRAPH}/$batch", json=body, headers=self._headers(), timeout=TIMEOUT_SECONDS
                )
            except requests.RequestException:
                failed += len(chunk)
                continue
            if response.status_code != 200:
                failed += len(chunk)
                continue
            for item in response.json().get("responses") or []:
                index = int(item["id"])
                if item.get("status") == 200 and (item.get("body") or {}).get("id"):
                    found[chunk[index]] = str(item["body"]["id"])
                elif item.get("status") != 404:
                    failed += 1
        if failed:
            log.warning("directory sync manager lookups failed count=%d", failed)
        return found

    def role_assignments(self) -> tuple[dict[str, str], int]:
        sp = self._get(
            f"{GRAPH}/servicePrincipals(appId='{self._api_client_id}')?$select=id,appRoles", "sp"
        )
        names = {str(r["id"]): str(r["value"]) for r in sp.get("appRoles") or [] if r.get("value")}
        rows = self._pages(
            f"{GRAPH}/servicePrincipals/{sp['id']}/appRoleAssignedTo?$top=999", "assignments"
        )
        roles: dict[str, list[str]] = {}
        groups = 0
        for row in rows:
            if row.get("principalType") == "Group":
                groups += 1
            elif row.get("principalType") == "User":
                roles.setdefault(str(row["principalId"]), []).append(
                    names.get(str(row.get("appRoleId")), "Employee")
                )
        return {oid: highest_role(values) for oid, values in roles.items()}, groups


class SyncTarget(Protocol):
    def apply_sync(self, employees: list[Employee]) -> None: ...


class DirectorySync:
    """Reads the tenant's employees now and then, and replaces the synced part of the directory."""

    def __init__(
        self,
        directory: SyncTarget,
        client: GraphDirectoryClient,
        settings: DirectorySettings,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._directory = directory
        self._client = client
        self._settings = settings
        self._clock = clock
        self.last_count: int | None = None

    def run_once(self) -> bool:
        """True when the directory was replaced. A failure keeps the previous directory."""
        s = self._settings
        try:
            members = self._client.list_members(s.attributes)
            roles, groups = self._client.role_assignments()
        except GraphError as exc:
            log.warning("directory sync failed code=%s", exc.code)
            return False
        except Exception:  # noqa: BLE001 - a sync problem must never take the api down
            log.warning("directory sync failed code=unexpected")
            return False
        now = self._clock()
        employees = [
            Employee(
                oid=m.oid,
                name=m.display_name,
                active=m.enabled,
                role=roles[m.oid],
                store=m.attributes.get(s.store_attribute, ""),
                region=parse_region(m.attributes.get(s.region_attribute)),
                canton=parse_canton(m.attributes.get(s.canton_attribute)),
                manager_oid=m.manager_oid,
                source=SOURCE_SYNC,
                fetched_at=now,
            )
            for m in members
            # Only members who hold an app role of this app (they can sign in); guests never.
            if m.user_type.lower() == "member" and m.oid in roles
        ]
        self._directory.apply_sync(employees)
        self.last_count = len(employees)
        log.info(
            "directory sync employees=%d active=%d users_seen=%d group_assignments_skipped=%d",
            len(employees),
            sum(e.active for e in employees),
            len(members),
            groups,
        )
        return True

    async def run_forever(self) -> None:
        while True:
            await asyncio.to_thread(self.run_once)
            await asyncio.sleep(self._settings.sync_interval.total_seconds())
