"""ADR-010 (superseded in part), FR-ANN-002, FR-VAC-004, FR-AUTH-002: the tenant-wide directory.

The Graph calls are replaced, so these tests check what is read, who is kept, how roles and managers
are derived, and that a failure never empties or breaks the directory.
"""

import time
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.auth.principal import Principal
from app.directory.graph import GraphError
from app.directory.settings import DirectorySettings, load_directory_settings
from app.directory.sync import (
    SOURCE_SYNC,
    DirectorySync,
    GraphMember,
    MsalGraphDirectoryClient,
    highest_role,
)
from app.main import create_app
from app.repositories import Employee, SeedDirectory

NOW = datetime(2026, 10, 20, 12, 0, tzinfo=UTC)
SETTINGS = DirectorySettings(sync_enabled=True)
ANNA, BEN, CARLA, GUEST, LEFT = "a", "b", "c", "g", "l"


def member(oid: str, name: str, **extra: Any) -> GraphMember:
    attributes = extra.pop(
        "attributes",
        {"state": "ZH", "officeLocation": "Store-Zurich", "preferredLanguage": "de-CH"},
    )
    return GraphMember(
        oid, name, extra.pop("enabled", True), extra.pop("user_type", "Member"), attributes, **extra
    )


class FakeLister:
    def __init__(self) -> None:
        self.members = [
            member(ANNA, "Anna", manager_oid=BEN),
            member(BEN, "Ben"),
            member(CARLA, "Carla", enabled=False),
            member(GUEST, "Guest", user_type="Guest"),
            member("nobody", "Has no app role"),
        ]
        self.roles = {ANNA: "Employee", BEN: "Manager", CARLA: "Employee", GUEST: "Employee"}
        self.groups = 2
        self.error: Exception | None = None
        self.calls = 0

    def list_members(self, attributes: list[str]) -> list[GraphMember]:
        self.calls += 1
        if self.error:
            raise self.error
        return self.members

    def role_assignments(self) -> tuple[dict[str, str], int]:
        return self.roles, self.groups


def make() -> tuple[SeedDirectory, FakeLister, DirectorySync]:
    directory, lister = SeedDirectory([]), FakeLister()
    return directory, lister, DirectorySync(directory, lister, SETTINGS, clock=lambda: NOW)


def test_adr_010_the_directory_is_the_tenants_employees_not_the_seed() -> None:
    directory, _, sync = make()
    assert directory.active() == []  # nothing is invented before the first read
    assert sync.run_once() is True
    names = sorted(e.name for e in directory.active())
    assert names == [
        "Anna",
        "Ben",
    ]  # the disabled account, the guest and the role-less user are not recipients
    assert sync.last_count == 3  # Anna, Ben and Carla are employees; Carla is simply inactive


def test_fr_ann_002_only_active_members_with_an_app_role_are_recipients() -> None:
    directory, _, sync = make()
    sync.run_once()
    assert directory.get(CARLA) is not None and directory.get(CARLA).active is False  # type: ignore[union-attr]
    assert directory.get(GUEST) is None and directory.get("nobody") is None


def test_fr_auth_002_roles_and_hr_attributes_come_from_graph() -> None:
    directory, lister, sync = make()
    lister.roles[ANNA] = "Publisher"
    lister.members[1] = member(
        BEN,
        "Ben",
        attributes={"state": "tessin", "officeLocation": "HQ", "preferredLanguage": "it"},
    )
    sync.run_once()
    anna, ben = directory.get(ANNA), directory.get(BEN)
    assert (
        anna and anna.role == "Publisher" and anna.canton == "ZH" and anna.store == "Store-Zurich"
    )
    assert anna.region == "DE" and anna.source == SOURCE_SYNC and anna.fetched_at == NOW
    assert (
        ben and ben.role == "Manager" and ben.canton is None
    )  # not a canton code: unknown, never guessed
    assert ben.region == "IT" and ben.store == "HQ"


def test_fr_vac_004_the_manager_comes_from_graph() -> None:
    directory, _, sync = make()
    sync.run_once()
    anna = directory.get(ANNA)
    assert anna and anna.manager_oid == BEN
    assert [e.oid for e in directory.active() if e.manager_oid == BEN] == [ANNA]


def test_adr_010_a_person_who_left_disappears_and_a_new_one_appears() -> None:
    directory, lister, sync = make()
    sync.run_once()
    lister.members = [m for m in lister.members if m.oid != ANNA] + [member("new", "Newcomer")]
    lister.roles = {**lister.roles, "new": "Employee"}
    sync.run_once()
    assert directory.get(ANNA) is None and directory.get("new") is not None


def test_adr_010_a_failed_read_keeps_the_directory_and_never_raises(
    caplog: pytest.LogCaptureFixture,
) -> None:
    directory, lister, sync = make()
    sync.run_once()
    before = sorted(e.oid for e in directory.active())
    for error in (GraphError("graph_users_403"), RuntimeError("secret detail ana@example.com")):
        lister.error = error
        assert sync.run_once() is False
    assert sorted(e.oid for e in directory.active()) == before
    assert "graph_users_403" in caplog.text and "ana@example.com" not in caplog.text


def test_adr_010_seed_entries_survive_a_sync_and_are_never_replaced() -> None:
    seed = Employee("seed-1", "Seeded", True, "Employee")
    directory = SeedDirectory([seed])
    lister = FakeLister()
    lister.members.append(member("seed-1", "Seeded in the tenant too"))
    lister.roles["seed-1"] = "Manager"
    DirectorySync(directory, lister, SETTINGS, clock=lambda: NOW).run_once()
    assert directory.get("seed-1") == seed


def test_adr_010_a_synced_record_counts_as_fresh_for_the_per_user_lookup() -> None:
    """A synced record is fresh: signing in must not cost a Graph call per request."""
    from app.directory.provisioning import Provisioner

    class Boom:
        def fetch(self, *_: Any) -> Any:
            raise AssertionError("a fresh synced record needs no delegated lookup")

    directory, _, sync = make()
    sync.run_once()
    provisioner = Provisioner(
        directory, Boom(), DirectorySettings(enabled=True, sync_enabled=True), clock=lambda: NOW
    )  # type: ignore[arg-type]
    provisioner.ensure(Principal(ANNA, "Anna", "a@x", ("Employee",), "t", assertion="tok"))


def test_adr_010_highest_role_wins_and_unknown_means_employee() -> None:
    assert highest_role(["Employee", "Communicator", "Manager"]) == "Publisher"
    assert highest_role(["Employee", "Manager"]) == "Manager"
    assert highest_role(["Employee"]) == highest_role(["Something else"]) == "Employee"


def test_adr_010_settings_read_the_switch_and_the_interval(monkeypatch: pytest.MonkeyPatch) -> None:
    assert load_directory_settings().sync_enabled is False  # off unless asked for
    monkeypatch.setenv("GRAPH_DIRECTORY_SYNC", "true")
    monkeypatch.setenv("GRAPH_DIRECTORY_SYNC_MINUTES", "5")
    settings = load_directory_settings()
    assert settings.sync_enabled and settings.sync_interval.total_seconds() == 300


# The Graph client ------------------------------------------------------------------------------


class Response:
    def __init__(self, body: Any, status: int = 200) -> None:
        self.status_code, self._body = status, body

    def json(self) -> Any:
        return self._body


class FakeGraph:
    """A tiny Graph: two pages of users, a manager batch, the service principal and its roles."""

    def __init__(self) -> None:
        self.gets: list[str] = []
        self.batches: list[int] = []

    def get(self, url: str, headers: Any, timeout: Any) -> Response:
        self.gets.append(url)
        if "/users?" in url:
            return Response(
                {
                    "value": [
                        {
                            "id": "u1",
                            "displayName": "One",
                            "accountEnabled": True,
                            "userType": "Member",
                            "state": "ZH",
                        }
                    ],
                    "@odata.nextLink": "https://graph.test/page2",
                }
            )
        if url == "https://graph.test/page2":
            return Response(
                {
                    "value": [
                        {
                            "id": "u2",
                            "displayName": "Two",
                            "accountEnabled": False,
                            "userType": "Guest",
                        }
                    ]
                }
            )
        if "/servicePrincipals(appId=" in url:
            return Response(
                {
                    "id": "sp-1",
                    "appRoles": [
                        {"id": "r-mgr", "value": "Manager"},
                        {"id": "r-emp", "value": "Employee"},
                    ],
                }
            )
        if url.endswith("/appRoleAssignedTo?$top=999"):
            return Response(
                {
                    "value": [
                        {"principalId": "u1", "principalType": "User", "appRoleId": "r-emp"},
                        {"principalId": "u1", "principalType": "User", "appRoleId": "r-mgr"},
                        {"principalId": "g1", "principalType": "Group", "appRoleId": "r-emp"},
                    ]
                }
            )
        return Response({}, 404)

    def post(self, url: str, json: Any, headers: Any, timeout: Any) -> Response:
        self.batches.append(len(json["requests"]))
        answers = []
        for item in json["requests"]:
            has_manager = "/users/u1/" in item["url"]
            answers.append(
                {
                    "id": item["id"],
                    "status": 200 if has_manager else 404,
                    "body": {"id": "boss"} if has_manager else {},
                }
            )
        return Response({"responses": answers})


def test_adr_010_the_graph_client_pages_batches_and_reads_roles() -> None:
    client = MsalGraphDirectoryClient.__new__(MsalGraphDirectoryClient)
    client._api_client_id = "api-app"  # noqa: SLF001
    client._http = FakeGraph()  # noqa: SLF001
    client._headers = lambda: {"Authorization": "Bearer x"}  # type: ignore[method-assign]  # noqa: SLF001
    members = client.list_members(["state", "officeLocation"])
    assert [m.oid for m in members] == ["u1", "u2"]  # both pages
    assert (
        members[0].manager_oid == "boss" and members[1].manager_oid is None
    )  # a 404 is "no manager"
    assert members[0].attributes == {"state": "ZH"} and members[1].enabled is False
    assert client._http.batches == [2]  # noqa: SLF001
    roles, groups = client.role_assignments()
    assert (
        roles == {"u1": "Manager"} and groups == 1
    )  # highest role; group assignments are not expanded
    assert any("appId='api-app'" in url for url in client._http.gets)  # noqa: SLF001


def test_adr_010_managers_are_asked_for_in_batches_of_twenty() -> None:
    client = MsalGraphDirectoryClient.__new__(MsalGraphDirectoryClient)
    client._http = FakeGraph()  # noqa: SLF001
    client._headers = lambda: {}  # type: ignore[method-assign]  # noqa: SLF001
    client._managers([f"u{i}" for i in range(45)])  # noqa: SLF001
    assert client._http.batches == [20, 20, 5]  # noqa: SLF001


def test_adr_010_a_graph_error_carries_a_code_and_no_content() -> None:
    client = MsalGraphDirectoryClient.__new__(MsalGraphDirectoryClient)

    class Denied(FakeGraph):
        def get(self, url: str, headers: Any, timeout: Any) -> Response:
            return Response({"error": {"message": "contains ana@example.com"}}, 403)

    client._http = Denied()  # noqa: SLF001
    client._headers = lambda: {}  # type: ignore[method-assign]  # noqa: SLF001
    with pytest.raises(GraphError) as exc:
        client.list_members(["state"])
    assert exc.value.code == "graph_users_403" and "ana" not in str(exc.value)


# The app --------------------------------------------------------------------------------------


def test_adr_010_the_app_loads_the_tenant_directory_and_not_the_seed(private_key: Any) -> None:
    from app.auth.validator import TokenValidator
    from tests.conftest import SETTINGS as AUTH_SETTINGS
    from tests.conftest import StaticKeys

    lister = FakeLister()
    validator = TokenValidator(AUTH_SETTINGS, StaticKeys(private_key.public_key()))
    app = create_app(validator, directory_settings=SETTINGS, directory_lister=lister)
    with TestClient(app):
        for _ in range(100):  # the first read runs beside startup
            if lister.calls:
                break
            time.sleep(0.05)
        time.sleep(0.2)
        directory = app.state.announcement_service._directory  # noqa: SLF001
        assert sorted(e.name for e in directory.active()) == ["Anna", "Ben"]
        assert directory.get("00000000-0000-0000-0000-000000000011") is None  # no seeded demo user


def test_adr_010_without_the_switch_the_seed_is_still_the_directory() -> None:
    app = create_app(directory_settings=DirectorySettings())
    assert len(app.state.announcement_service._directory.active()) == 11  # noqa: SLF001
