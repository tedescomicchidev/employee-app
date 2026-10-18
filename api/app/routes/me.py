from typing import Annotated

from fastapi import APIRouter, Depends

from app.auth.principal import Principal, current_principal

router = APIRouter(prefix="/v1")


@router.get("/me")
def me(principal: Annotated[Principal, Depends(current_principal)]) -> dict[str, object]:
    return {
        "oid": principal.oid,
        "display_name": principal.display_name,
        "upn": principal.upn,
        "roles": list(principal.roles),
        "tenant_id": principal.tenant_id,
    }
