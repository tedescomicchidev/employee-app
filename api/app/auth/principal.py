from collections.abc import Callable
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Annotated, Any

from fastapi import Depends, Request

from app.auth.errors import forbidden, unauthenticated
from app.auth.validator import TokenError, TokenValidator


class Role(StrEnum):
    COMMUNICATOR = "Communicator"
    MANAGER = "Manager"
    EMPLOYEE = "Employee"


@dataclass(frozen=True)
class Principal:
    oid: str
    display_name: str
    upn: str
    roles: tuple[str, ...]
    tenant_id: str
    # The validated access token, kept only for the on-behalf-of exchange. Never logged.
    assertion: str = field(default="", repr=False, compare=False)

    def has_role(self, role: Role) -> bool:
        return role.value in self.roles


def authorize(principal: Principal, *required: Role) -> None:
    """Single authorisation function shared by REST and MCP tools."""
    if required and not any(principal.has_role(r) for r in required):
        raise forbidden()


def principal_from_claims(claims: dict[str, Any], token: str) -> Principal:
    return Principal(
        oid=claims["oid"],
        display_name=claims.get("name", ""),
        upn=claims.get("preferred_username", ""),
        roles=tuple(claims.get("roles", [])),
        tenant_id=claims["tid"],
        assertion=token,
    )


def get_validator(request: Request) -> TokenValidator:
    return request.app.state.token_validator


def current_principal(
    request: Request, validator: Annotated[TokenValidator, Depends(get_validator)]
) -> Principal:
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise unauthenticated()
    try:
        claims = validator.validate(token, required_scope="access_as_user")
    except TokenError as exc:
        raise unauthenticated(str(exc)) from exc
    principal = principal_from_claims(claims, token)
    provisioner = getattr(request.app.state, "provisioner", None)
    if provisioner is not None:
        provisioner.ensure(principal)
    return principal


def require_roles(*required: Role) -> Callable[[Principal], Principal]:
    def dependency(principal: Annotated[Principal, Depends(current_principal)]) -> Principal:
        authorize(principal, *required)
        return principal

    return dependency
