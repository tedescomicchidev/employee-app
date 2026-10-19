"""ADR-010 (revised): the directory is filled from each signed-in user's own Graph profile (OBO).

Uses a fake Graph client with made-up object ids; nothing here touches a tenant.
"""

import logging
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.auth.validator import TokenValidator
from app.directory.graph import GraphError, GraphProfile
from app.directory.settings import DirectorySettings, load_directory_settings
from app.main import create_app
from app.repositories import InMemoryConfirmationStore, SeedDirectory
from app.vacation.service import VacationService
from app.vacation.store import InMemoryVacationStore
from tests.conftest import SETTINGS, StaticKeys

NEW_USER = "11111111-aaaa-bbbb-cccc-000000000001"
MANAGER = "11111111-aaaa-bbbb-cccc-000000000002"
SEED_EMP2 = "00000000-0000-0000-0000-000000000012"
NOW = datetime(2026, 10, 19, 6, 0, tzinfo=UTC)
TokenFactory = Callable[..., str]


class FakeGraph:
    def __init__(self) -> None:
        self.calls: list[tuple[str, list[str]]] = []
        self.error: GraphError | None = None
        self.profile = GraphProfile(
            oid=NEW_USER,
            display_name="Test Person",
            attributes={
                "state": "ti",
                "officeLocation": "Store-Lugano",
                "preferredLanguage": "it-CH",
            },
            manager_oid=MANAGER,
            manager_name="Test Manager",
        )

    def fetch(self, user_assertion: str, attributes: list[str]) -> GraphProfile:
        self.calls.append((user_assertion, attributes))
        if self.error:
            raise self.error
        return self.profile


class Clock:
    def __init__(self) -> None:
        self.now = NOW

    def __call__(self) -> datetime:
        return self.now


class Env:
    def __init__(self, private_key: Any, make_token: TokenFactory, enabled: bool = True) -> None:
        self.graph = FakeGraph()
        self.clock = Clock()
        self.directory = SeedDirectory.from_file()
        vacation = VacationService(
            self.directory, InMemoryVacationStore(), InMemoryConfirmationStore(), clock=self.clock
        )
        validator = TokenValidator(SETTINGS, StaticKeys(private_key.public_key()))
        settings = DirectorySettings(enabled=enabled, ttl=timedelta(hours=12))
        app = create_app(
            validator,
            vacation_service=vacation,
            directory=self.directory,
            directory_client=self.graph,
            directory_settings=settings,
        )
        if app.state.provisioner is not None:
            app.state.provisioner._clock = self.clock
        self.client = TestClient(app)
        self._make_token = make_token

    def token(self, oid: str = NEW_USER, **claims: Any) -> str:
        return self._make_token(oid=oid, **claims)

    def get(self, path: str, oid: str = NEW_USER, **claims: Any) -> Any:
        headers = {"Authorization": f"Bearer {self.token(oid, **claims)}"}
        return self.client.get(path, headers=headers)


@pytest.fixture
def env(private_key: Any, make_token: TokenFactory) -> Env:
    return Env(private_key, make_token)


def test_unknown_tenant_user_is_provisioned_from_their_own_profile(env: Env) -> None:
    """The user is not in the seed, yet balance and canton holidays work after one lookup."""
    assert env.directory.get(NEW_USER) is None
    balance = env.get("/v1/vacation/balance")
    assert balance.status_code == 200 and balance.json()["remaining"] == 25
    holidays = env.get("/v1/vacation/holidays?year=2026").json()
    assert holidays["canton"] == "TI"  # `ti` from Graph, normalised
    employee = env.directory.get(NEW_USER)
    assert employee is not None
    assert (employee.store, employee.region, employee.role) == ("Store-Lugano", "IT", "Employee")
    assert employee.source == "graph" and employee.manager_oid == MANAGER


def test_the_users_own_token_is_the_assertion(env: Env) -> None:
    token = env.token()
    env.client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    assertion, attributes = env.graph.calls[0]
    assert assertion == token
    assert attributes == ["state", "officeLocation", "preferredLanguage"]


def test_manager_becomes_the_approver_without_ever_signing_in(env: Env) -> None:
    proposal = env.client.post(
        "/v1/proposals",
        json={"type": "vacation", "payload": {"start": "2026-11-23", "end": "2026-11-25"}},
        headers={"Authorization": f"Bearer {env.token()}"},
    )
    assert proposal.status_code == 200, proposal.text
    assert proposal.json()["review"]["approver"] == "Test Manager"
    stub = env.directory.get(MANAGER)
    assert stub is not None and stub.source == "graph-manager" and stub.role == ""


def test_manager_stub_is_replaced_when_the_manager_signs_in(env: Env) -> None:
    env.get("/v1/me")
    env.graph.profile = GraphProfile(
        oid=MANAGER,
        display_name="Test Manager",
        attributes={"state": "ZH"},
        manager_oid=None,
    )
    env.get("/v1/me", oid=MANAGER, roles=["Manager"])
    manager = env.directory.get(MANAGER)
    assert manager is not None and manager.source == "graph"
    assert (manager.role, manager.canton, manager.manager_oid) == ("Manager", "ZH", None)


def test_roles_come_from_the_token_not_from_graph(env: Env) -> None:
    env.get("/v1/me", roles=["Employee", "Communicator"])
    employee = env.directory.get(NEW_USER)
    assert employee is not None and employee.role == "Publisher"


def test_a_value_that_is_not_a_canton_is_unknown_and_asks_hr(env: Env) -> None:
    env.graph.profile = GraphProfile(
        oid=NEW_USER,
        display_name="Test Person",
        attributes={"state": "Zürich"},
        manager_oid=MANAGER,
    )
    assert env.get("/v1/vacation/balance").status_code == 200
    assert env.get("/v1/vacation/holidays").json()["code"] == "CANTON_MISSING"


def test_no_manager_in_the_directory_means_no_approver(env: Env) -> None:
    env.graph.profile = GraphProfile(
        oid=NEW_USER, display_name="Test Person", attributes={"state": "ZH"}, manager_oid=None
    )
    response = env.client.post(
        "/v1/proposals",
        json={"type": "vacation", "payload": {"start": "2026-11-23", "end": "2026-11-25"}},
        headers={"Authorization": f"Bearer {env.token()}"},
    )
    assert response.json()["code"] == "NO_APPROVER"


def test_graph_failure_never_breaks_the_request_and_logs_only_a_code(
    env: Env, caplog: pytest.LogCaptureFixture
) -> None:
    env.graph.error = GraphError("consent_required")
    with caplog.at_level(logging.WARNING, logger="app.directory"):
        assert env.get("/v1/me").status_code == 200
        blocked = env.get("/v1/vacation/balance")
    assert blocked.status_code == 403 and blocked.json()["code"] == "NOT_PROVISIONED"
    assert "consent_required" in caplog.text
    assert env.token() not in caplog.text and "Test Person" not in caplog.text


def test_a_failed_lookup_is_not_repeated_until_the_retry_window_passes(env: Env) -> None:
    env.graph.error = GraphError("invalid_client")
    for _ in range(5):
        assert env.get("/v1/vacation/balance").status_code == 403
    assert len(env.graph.calls) == 1
    env.clock.now = NOW + timedelta(seconds=61)
    env.get("/v1/me")
    assert len(env.graph.calls) == 2


def test_the_user_is_provisioned_as_soon_as_the_retry_window_passes_after_a_fix(env: Env) -> None:
    env.graph.error = GraphError("invalid_client")
    assert env.get("/v1/vacation/balance").status_code == 403
    env.graph.error = None  # the federated credential was fixed
    assert env.get("/v1/vacation/balance").status_code == 403  # still inside the window
    env.clock.now = NOW + timedelta(seconds=61)
    assert env.get("/v1/vacation/balance").status_code == 200


def test_one_users_failure_does_not_block_another_user(env: Env) -> None:
    env.graph.error = GraphError("graph_503")
    env.get("/v1/me")
    env.graph.error = None
    env.graph.profile = GraphProfile(oid=MANAGER, display_name="Other", attributes={"state": "ZH"})
    assert env.get("/v1/vacation/balance", oid=MANAGER).status_code == 200
    assert len(env.graph.calls) == 2


def test_a_mismatching_profile_also_waits_before_the_next_try(env: Env) -> None:
    env.graph.profile = GraphProfile(oid=MANAGER, display_name="Other", attributes={})
    env.get("/v1/me")
    env.get("/v1/me")
    assert len(env.graph.calls) == 1


def test_old_failures_are_forgotten(env: Env) -> None:
    env.graph.error = GraphError("graph_503")
    env.get("/v1/me")
    env.clock.now = NOW + timedelta(minutes=5)
    env.get("/v1/me", oid=MANAGER)
    provisioner = env.client.app.state.provisioner  # type: ignore[attr-defined]
    assert set(provisioner._failed) == {MANAGER}


def test_a_manager_failure_still_provisions_the_user_and_retries_soon(
    env: Env, caplog: pytest.LogCaptureFixture
) -> None:
    env.graph.profile = GraphProfile(
        oid=NEW_USER,
        display_name="Test Person",
        attributes={"state": "ZH"},
        manager_error="graph_manager_403",
    )
    with caplog.at_level(logging.WARNING, logger="app.directory"):
        assert env.get("/v1/vacation/balance").status_code == 200  # News and balance work
    assert "graph_manager_403" in caplog.text
    env.get("/v1/me")
    assert len(env.graph.calls) == 1  # not retried inside the window
    env.clock.now = NOW + timedelta(seconds=61)  # far short of the 12 h TTL
    env.graph.profile = GraphProfile(
        oid=NEW_USER, display_name="Test Person", attributes={"state": "ZH"}, manager_oid=MANAGER
    )
    env.get("/v1/me")
    assert len(env.graph.calls) == 2
    employee = env.directory.get(NEW_USER)
    assert employee is not None and employee.manager_oid == MANAGER


def test_unexpected_graph_errors_are_contained(env: Env) -> None:
    env.graph.error = RuntimeError("boom")  # type: ignore[assignment]
    assert env.get("/v1/me").status_code == 200


def test_a_profile_for_someone_else_is_ignored(env: Env) -> None:
    env.graph.profile = GraphProfile(oid=MANAGER, display_name="Other", attributes={"state": "ZH"})
    assert env.get("/v1/vacation/balance").json()["code"] == "NOT_PROVISIONED"
    assert env.directory.get(NEW_USER) is None


def test_lookup_is_cached_until_the_ttl_expires(env: Env) -> None:
    env.get("/v1/me")
    env.get("/v1/me")
    assert len(env.graph.calls) == 1
    env.clock.now = NOW + timedelta(hours=13)
    env.graph.profile = GraphProfile(
        oid=NEW_USER, display_name="Test Person", attributes={"state": "BE"}, manager_oid=MANAGER
    )
    env.get("/v1/me")
    assert len(env.graph.calls) == 2
    assert env.get("/v1/vacation/holidays").json()["canton"] == "BE"


def test_seed_users_are_never_looked_up_or_replaced(env: Env) -> None:
    env.graph.profile = GraphProfile(oid=SEED_EMP2, display_name="X", attributes={"state": "GE"})
    assert env.get("/v1/vacation/holidays", oid=SEED_EMP2).json()["canton"] == "ZH"
    assert env.graph.calls == []


def test_disabled_by_default_so_local_and_test_runs_need_no_graph(
    private_key: Any, make_token: TokenFactory
) -> None:
    off = Env(private_key, make_token, enabled=False)
    assert off.client.app.state.provisioner is None  # type: ignore[attr-defined]
    assert off.get("/v1/vacation/balance").json()["code"] == "NOT_PROVISIONED"
    assert off.graph.calls == []


def test_settings_come_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    assert not load_directory_settings().enabled
    monkeypatch.setenv("GRAPH_DIRECTORY", "true")
    monkeypatch.setenv("AZURE_CLIENT_ID", "mi-client")
    monkeypatch.setenv("GRAPH_CANTON_ATTRIBUTE", "officeLocation")
    monkeypatch.setenv("GRAPH_DIRECTORY_RETRY_SECONDS", "5")
    settings = load_directory_settings()
    assert settings.enabled and settings.managed_identity_client_id == "mi-client"
    assert settings.attributes == ["officeLocation", "preferredLanguage"]
    assert settings.retry_after == timedelta(seconds=5)
    monkeypatch.delenv("GRAPH_DIRECTORY_RETRY_SECONDS")
    assert load_directory_settings().retry_after == timedelta(seconds=60)


class _Response:
    def __init__(self, status: int, body: dict[str, Any]) -> None:
        self.status_code = status
        self._body = body

    def json(self) -> dict[str, Any]:
        return self._body


class TestMsalClient:
    """The real client with msal and requests replaced: error codes, no manager, no secret."""

    @pytest.fixture
    def client(self, monkeypatch: pytest.MonkeyPatch) -> Any:
        import msal

        from app.directory import graph

        class FakeIdentity:
            def __init__(self, *_: Any, **__: Any) -> None: ...

            def acquire_token_for_client(self, resource: str) -> dict[str, str]:
                assert resource == "api://AzureADTokenExchange"
                return {"access_token": "mi-token"}

        class FakeApp:
            result: dict[str, Any] = {"access_token": "graph-token"}
            kwargs: dict[str, Any] = {}

            def __init__(self, *args: Any, **kwargs: Any) -> None:
                FakeApp.kwargs = kwargs

            def acquire_token_on_behalf_of(self, assertion: str, scopes: list[str]) -> Any:
                assert scopes == ["https://graph.microsoft.com/User.Read"]
                return FakeApp.result

        monkeypatch.setattr(msal, "ManagedIdentityClient", FakeIdentity)
        monkeypatch.setattr(msal, "ConfidentialClientApplication", FakeApp)
        self.app = FakeApp
        return graph.MsalGraphProfileClient("tenant", "api-client", "mi-client")

    def test_no_secret_only_a_callable_assertion_from_the_identity(self, client: Any) -> None:
        credential = self.app.kwargs["client_credential"]
        assert set(credential) == {"client_assertion"}
        assert credential["client_assertion"]() == "mi-token"

    def test_profile_and_manager(self, client: Any, monkeypatch: pytest.MonkeyPatch) -> None:
        import requests

        def fake_get(url: str, headers: dict[str, str], timeout: int) -> _Response:
            assert headers == {"Authorization": "Bearer graph-token"}
            if "/me/manager" in url:
                return _Response(200, {"id": MANAGER, "displayName": "Boss"})
            assert "$select=id,displayName,state" in url
            return _Response(200, {"id": NEW_USER, "displayName": "Me", "state": "ZH"})

        monkeypatch.setattr(requests, "get", fake_get)
        profile = client.fetch("user-token", ["state", "officeLocation"])
        assert profile.attributes == {"state": "ZH"}  # unset attributes are simply absent
        assert (profile.manager_oid, profile.manager_name) == (MANAGER, "Boss")

    def test_no_manager_is_not_an_error(self, client: Any, monkeypatch: pytest.MonkeyPatch) -> None:
        import requests

        def fake_get(url: str, headers: dict[str, str], timeout: int) -> _Response:
            if "/me/manager" in url:
                return _Response(404, {})
            return _Response(200, {"id": NEW_USER, "displayName": "Me"})

        monkeypatch.setattr(requests, "get", fake_get)
        assert client.fetch("user-token", ["state"]).manager_oid is None

    def test_obo_failure_is_a_code_without_the_description(self, client: Any) -> None:
        self.app.result = {"error": "consent_required", "error_description": "AADSTS65001 detail"}
        with pytest.raises(GraphError) as caught:
            client.fetch("user-token", ["state"])
        assert caught.value.code == "consent_required" and "AADSTS" not in str(caught.value)

    def test_a_failing_manager_call_keeps_the_profile_and_names_the_call(
        self, client: Any, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        import requests

        def fake_get(url: str, headers: dict[str, str], timeout: int) -> _Response:
            if "/me/manager" in url:
                return _Response(403, {})
            return _Response(200, {"id": NEW_USER, "displayName": "Me", "state": "ZH"})

        monkeypatch.setattr(requests, "get", fake_get)
        profile = client.fetch("user-token", ["state"])
        assert profile.attributes == {"state": "ZH"}
        assert profile.manager_oid is None and profile.manager_error == "graph_manager_403"

    def test_graph_http_errors_are_codes(
        self, client: Any, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        import requests

        monkeypatch.setattr(requests, "get", lambda *a, **k: _Response(403, {}))
        with pytest.raises(GraphError) as caught:
            client.fetch("user-token", ["state"])
        assert caught.value.code == "graph_me_403"
