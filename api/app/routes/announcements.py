from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request, Response

from app.announcements.models import Announcement, InboxItem
from app.announcements.service import AnnouncementService, validate_draft
from app.auth.errors import FieldError
from app.auth.principal import Principal, Role, current_principal, require_roles

router = APIRouter(prefix="/v1")

Publisher = Annotated[Principal, Depends(require_roles(Role.COMMUNICATOR))]
Body = dict[str, Any]


def get_service(request: Request) -> AnnouncementService:
    return request.app.state.announcement_service


Service = Annotated[AnnouncementService, Depends(get_service)]


def _draft(body: Body) -> Any:
    payload = body.get("payload")
    if not isinstance(payload, dict):
        raise FieldError("payload", "required")
    return validate_draft(
        payload.get("title"), payload.get("body"), payload.get("language"), payload.get("audience")
    )


def _announcement(a: Announcement) -> dict[str, Any]:
    return {
        "id": a.id,
        "title": a.title,
        "body": a.body,
        "language": a.language.value,
        "audience": a.audience.value,
        "author": a.author_name,
        "status": a.status,
        "published_at": a.published_at.isoformat(),
        "recipient_count": a.recipient_count,
    }


@router.post("/proposals")
def create_proposal(principal: Publisher, service: Service, body: Body) -> dict[str, Any]:
    draft = _draft(body)
    result = service.propose(principal, draft)
    return {
        "proposal_id": result.proposal.id,
        "type": "announcement",
        "payload": draft.canonical(),
        "recipient_count": result.recipient_count,
        "expires_at": result.proposal.expires_at.isoformat(),
    }


@router.post("/confirmations")
def create_confirmation(principal: Publisher, service: Service, body: Body) -> dict[str, Any]:
    proposal_id = body.get("proposal_id")
    if not isinstance(proposal_id, str):
        raise FieldError("proposal_id", "required")
    token = service.confirm(principal, proposal_id)
    return {"confirmation_token": token.token, "expires_at": token.expires_at.isoformat()}


@router.post("/announcements")
def publish_announcement(
    principal: Publisher, service: Service, body: Body, response: Response
) -> dict[str, Any]:
    draft = _draft(body)
    token = body.get("confirmation_token")
    result = service.publish(principal, draft, token if isinstance(token, str) else None)
    response.status_code = 201 if result.created else 200
    return {**_announcement(result.announcement), "created": result.created}


@router.get("/announcements")
def list_announcements(
    principal: Annotated[Principal, Depends(current_principal)], service: Service
) -> dict[str, Any]:
    items: list[tuple[Announcement, InboxItem]] = service.list_for(principal)
    return {
        "items": [{**_announcement(a), "read": inbox.read_at is not None} for a, inbox in items]
    }
