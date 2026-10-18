import logging
from typing import Any, NoReturn, Protocol

import jwt
from jwt import PyJWKClient

from app.config import Settings

logger = logging.getLogger(__name__)

_REASONS: list[tuple[type[Exception], str]] = [
    (jwt.ExpiredSignatureError, "expired"),
    (jwt.InvalidAudienceError, "audience"),
    (jwt.InvalidIssuerError, "issuer"),
    (jwt.InvalidSignatureError, "signature"),
    (jwt.MissingRequiredClaimError, "missing_claim"),
]


def _reason(exc: Exception) -> str:
    return next((name for kind, name in _REASONS if isinstance(exc, kind)), "invalid")


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
                audience=self._settings.audiences,
                issuer=self._settings.issuers,
                options={"require": ["exp", "iss", "aud"]},
            )
        except jwt.PyJWTError as exc:
            self._reject(_reason(exc))
        if claims.get("tid") != self._settings.tenant_id or not claims.get("oid"):
            self._reject("tenant_or_oid")
        if required_scope not in str(claims.get("scp", "")).split():
            self._reject("scope")
        return claims

    def _reject(self, reason: str) -> NoReturn:
        # Reason code only: never the token or its claims (NFR-012).
        if not self._settings.tenant_id or not self._settings.api_client_id:
            reason = "api_not_configured"
        logger.warning("access token rejected: %s", reason)
        raise TokenError("Invalid access token" if reason != "scope" else "Missing required scope")
