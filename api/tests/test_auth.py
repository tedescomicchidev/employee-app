import time
from collections.abc import Callable
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.auth.errors import ApiError
from app.auth.principal import Principal, Role, authorize

TokenFactory = Callable[..., str]


def get_me(client: TestClient, token: str | None) -> Any:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return client.get("/v1/me", headers=headers)


def test_fr_auth_001_valid_token_returns_identity(
    client: TestClient, make_token: TokenFactory
) -> None:
    response = get_me(client, make_token(roles=["Employee", "Manager"]))
    assert response.status_code == 200
    body = response.json()
    assert body["display_name"] == "Test User"
    assert body["roles"] == ["Employee", "Manager"]
    assert body["oid"] == "00000000-0000-0000-0000-0000000000aa"


def test_fr_auth_001_missing_token_is_unauthenticated(client: TestClient) -> None:
    response = get_me(client, None)
    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"


@pytest.mark.parametrize(
    "overrides",
    [
        {"aud": "api://someone-else"},
        {"iss": "https://login.microsoftonline.com/other/v2.0"},
        {"exp": int(time.time()) - 60},
        {"tid": "99999999-9999-9999-9999-999999999999"},
        {"scp": "Tools.Invoke"},
        {"scp": None},
        {"oid": None},
    ],
    ids=["audience", "issuer", "expired", "tenant", "wrong-scope", "no-scope", "no-oid"],
)
def test_fr_auth_001_rejected_tokens(
    client: TestClient, make_token: TokenFactory, overrides: dict[str, Any]
) -> None:
    response = get_me(client, make_token(**overrides))
    assert response.status_code == 401
    assert response.json()["code"] == "UNAUTHENTICATED"


def test_fr_auth_001_invalid_signature(
    client: TestClient, make_token: TokenFactory, other_key: Any
) -> None:
    assert get_me(client, make_token(key=other_key)).status_code == 401


def test_fr_auth_001_health_is_open(client: TestClient) -> None:
    assert client.get("/health").status_code == 200


def principal(*roles: str) -> Principal:
    return Principal(oid="o", display_name="n", upn="u", roles=roles, tenant_id="t")


def test_fr_auth_002_authorize_allows_matching_role() -> None:
    authorize(principal("Communicator"), Role.COMMUNICATOR)
    authorize(principal("Employee"), Role.EMPLOYEE, Role.MANAGER)


def test_fr_auth_002_authorize_denies_missing_role() -> None:
    with pytest.raises(ApiError) as exc:
        authorize(principal("Employee"), Role.COMMUNICATOR)
    assert exc.value.status_code == 403
    assert exc.value.detail["code"] == "FORBIDDEN"
