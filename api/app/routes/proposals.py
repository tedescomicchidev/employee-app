"""Shared dry-run and confirmation endpoints; `type` selects the domain (default: announcement)."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from app.announcements.service import AnnouncementService
from app.auth.errors import FieldError
from app.auth.principal import Principal, Role, authorize, current_principal
from app.routes.announcements import Body, _draft
from app.routes.vacation import _request, review_json
from app.vacation.models import ACTION_CANCEL
from app.vacation.service import VacationService, parse_draft

router = APIRouter(prefix="/v1")

Caller = Annotated[Principal, Depends(current_principal)]


def _type(body: Body) -> str:
    kind = body.get("type", "announcement")
    if kind not in ("announcement", "vacation", "vacation_cancel"):
        raise FieldError("type", "announcement, vacation or vacation_cancel")
    return kind


@router.post("/proposals")
def create_proposal(principal: Caller, request: Request, body: Body) -> dict[str, Any]:
    if _type(body) == "vacation_cancel":
        payload = body.get("payload")
        request_id = payload.get("request_id") if isinstance(payload, dict) else None
        if not isinstance(request_id, str):
            raise FieldError("payload.request_id", "required")
        service: VacationService = request.app.state.vacation_service
        cancel = service.propose_cancel(principal, request_id)
        return {
            "proposal_id": cancel.proposal.id,
            "type": "vacation_cancel",
            "payload": {"request_id": request_id},
            "request": _request(cancel.request),
            "expires_at": cancel.proposal.expires_at.isoformat(),
        }
    if _type(body) == "vacation":
        vacation: VacationService = request.app.state.vacation_service
        draft = parse_draft(body.get("payload"))
        result = vacation.propose(principal, draft)
        return {
            "proposal_id": result.proposal.id,
            "type": "vacation",
            "payload": draft.canonical(),
            "review": review_json(result.review),
            "expires_at": result.proposal.expires_at.isoformat(),
        }
    authorize(principal, Role.COMMUNICATOR)
    announcements: AnnouncementService = request.app.state.announcement_service
    ann_draft = _draft(body)
    ann = announcements.propose(principal, ann_draft)
    return {
        "proposal_id": ann.proposal.id,
        "type": "announcement",
        "payload": ann_draft.canonical(),
        "recipient_count": ann.recipient_count,
        "expires_at": ann.proposal.expires_at.isoformat(),
    }


@router.post("/confirmations")
def create_confirmation(principal: Caller, request: Request, body: Body) -> dict[str, Any]:
    kind = _type(body)
    if kind == "announcement":
        authorize(principal, Role.COMMUNICATOR)
    proposal_id = body.get("proposal_id")
    if not isinstance(proposal_id, str):
        raise FieldError("proposal_id", "required")
    if kind == "vacation_cancel":
        token = request.app.state.vacation_service.confirm(principal, proposal_id, ACTION_CANCEL)
    elif kind == "vacation":
        token = request.app.state.vacation_service.confirm(principal, proposal_id)
    else:
        token = request.app.state.announcement_service.confirm(principal, proposal_id)
    return {"confirmation_token": token.token, "expires_at": token.expires_at.isoformat()}
