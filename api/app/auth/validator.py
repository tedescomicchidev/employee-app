from typing import Any, Protocol

import jwt
from jwt import PyJWKClient

from app.config import Settings


class TokenError(Exception):
    """Token rejected. The message is safe to return; it never contains the token."""


class KeyProvider(Protocol):
    def signing_key(self, token: str) -> Any: ...


class JwksKeyProvider:
    def __init__(self, jwks_uri: str) -> None:
        self._client = PyJWKClient(jwks_uri, cache_keys=True)

    def signing_key(self, token: str) -> Any:
        return self._client.get_signing_key_from_jwt(token).key


class TokenValidator:
    def __init__(self, settings: Settings, keys: KeyProvider) -> None:
        self._settings = settings
        self._keys = keys

    def validate(self, token: str, required_scope: str) -> dict[str, Any]:
        try:
            key = self._keys.signing_key(token)
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=self._settings.api_audience,
                issuer=self._settings.issuer,
                options={"require": ["exp", "iss", "aud"]},
            )
        except jwt.PyJWTError as exc:
            raise TokenError("Invalid access token") from exc
        if claims.get("tid") != self._settings.tenant_id or not claims.get("oid"):
            raise TokenError("Invalid access token")
        if required_scope not in str(claims.get("scp", "")).split():
            raise TokenError("Missing required scope")
        return claims
