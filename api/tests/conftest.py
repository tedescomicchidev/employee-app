import time
from collections.abc import Callable
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.auth.validator import TokenValidator
from app.config import Settings
from app.main import create_app

TENANT = "11111111-1111-1111-1111-111111111111"
CLIENT = "22222222-2222-2222-2222-222222222222"
SETTINGS = Settings(tenant_id=TENANT, api_client_id=CLIENT, api_audience=f"api://{CLIENT}")


class StaticKeys:
    def __init__(self, public_key: Any) -> None:
        self._key = public_key

    def signing_key(self, token: str) -> Any:
        return self._key


@pytest.fixture(scope="session")
def private_key() -> Any:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture(scope="session")
def other_key() -> Any:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture
def client(private_key: Any) -> TestClient:
    validator = TokenValidator(SETTINGS, StaticKeys(private_key.public_key()))
    return TestClient(create_app(validator))


@pytest.fixture
def make_token(private_key: Any) -> Callable[..., str]:
    def make(key: Any = None, **overrides: Any) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": SETTINGS.issuer,
            "aud": SETTINGS.api_audience,
            "iat": now,
            "nbf": now,
            "exp": now + 3600,
            "tid": TENANT,
            "oid": "00000000-0000-0000-0000-0000000000aa",
            "name": "Test User",
            "preferred_username": "emp1@example.test",
            "scp": "access_as_user",
            "roles": ["Employee"],
        }
        claims.update(overrides)
        claims = {k: v for k, v in claims.items() if v is not None}
        return jwt.encode(claims, key or private_key, algorithm="RS256")

    return make


TOOLS_CLIENT = "33333333-3333-3333-3333-333333333333"
TOOLS_SETTINGS = Settings(
    tenant_id=TENANT,
    api_client_id=CLIENT,
    api_audience=f"api://{CLIENT}",
    tools_client_id=TOOLS_CLIENT,
    tools_audience=f"api://{TOOLS_CLIENT}",
)
