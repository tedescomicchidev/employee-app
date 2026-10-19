"""Shared dry-run and confirmation endpoints; `type` selects the domain (default: announcement)."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from app.announcements.service import AnnouncementService
from app.auth.errors import ApiError, FieldError
from app.auth.principal import Principal, Role, authorize, current_principal
from app.repositories import Proposal
from app.routes.announcements import Body, _draft
from app.routes.vacation import request_json, review_json
from app.vacation.models import ACTION_CANCEL, ACTION_DECIDE, ACTION_REQUEST
from app.vacation.service import VacationService, parse_draft

router = APIRouter(prefix="/v1")

Caller = Annotated[Principal, Depends(current_principal)]


def _type(body: Body) -> str:
    kind = body.get("type", "announcement")
    if kind not in ("announcement", "vacation", "vacation_cancel", "vacation_decision"):
        raise FieldError("type", "announcement, vacation, vacation_cancel or vacation_decision")
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
            "request": request_json(cancel.request),
            "expires_at": cancel.proposal.expires_at.isoformat(),
        }
    if _type(body) == "vacation_decision":
        payload = body.get("payload")
        if not isinstance(payload, dict) or not isinstance(payload.get("request_id"), str):
            raise FieldError("payload.request_id", "required")
        deciding: VacationService = request.app.state.vacation_service
        result = deciding.propose_decision(
            principal, payload["request_id"], payload.get("decision", ""), payload.get("reason")
        )
        return {
            "proposal_id": result.proposal.id,
            "type": "vacation_decision",
            "payload": result.proposal.draft.canonical(),
            "request": request_json(result.request),
            "expires_at": result.proposal.expires_at.isoformat(),
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


@router.get("/proposals/{proposal_id}")
def get_proposal(proposal_id: str, principal: Caller, request: Request) -> dict[str, Any]:
    """Confirm-card content: from the server, never from model text (A-13).

    The proposal's own action says which domain it belongs to; announcements stay the default.
    """
    vacation: VacationService = request.app.state.vacation_service
    try:
        proposal = vacation.get_proposal(principal, proposal_id)
    except ApiError:
        proposal = None
    if proposal is not None:
        return vacation_card(vacation, principal, proposal)
    announcements: AnnouncementService = request.app.state.announcement_service
    result = announcements.get_proposal(principal, proposal_id)
    return {
        "proposal_id": result.proposal.id,
        "type": "announcement",
        "payload": result.proposal.draft.canonical(),
        "recipient_count": result.recipient_count,
        "expires_at": result.proposal.expires_at.isoformat(),
    }


def vacation_card(
    service: VacationService, principal: Principal, proposal: Proposal
) -> dict[str, Any]:
    """The stored draft plus what the user needs to decide, all computed by the api."""
    card: dict[str, Any] = {
        "proposal_id": proposal.id,
        "payload": proposal.draft.canonical(),
        "expires_at": proposal.expires_at.isoformat(),
    }
    if proposal.action == ACTION_REQUEST:
        card["type"] = "vacation"
        card["review"] = review_json(service.review(principal, proposal.draft))
    else:
        card["type"] = (
            "vacation_cancel" if proposal.action == ACTION_CANCEL else "vacation_decision"
        )
        card["request"] = request_json(service.get_request(principal, proposal.draft.request_id))
    return card


@router.post("/confirmations")
def create_confirmation(principal: Caller, request: Request, body: Body) -> dict[str, Any]:
    kind = _type(body)
    if kind == "announcement":
        authorize(principal, Role.COMMUNICATOR)
    proposal_id = body.get("proposal_id")
    if not isinstance(proposal_id, str):
        raise FieldError("proposal_id", "required")
    if kind in ("vacation_cancel", "vacation_decision"):
        action = ACTION_CANCEL if kind == "vacation_cancel" else ACTION_DECIDE
        token = request.app.state.vacation_service.confirm(principal, proposal_id, action)
    elif kind == "vacation":
        token = request.app.state.vacation_service.confirm(principal, proposal_id)
    else:
        token = request.app.state.announcement_service.confirm(principal, proposal_id)
    return {"confirmation_token": token.token, "expires_at": token.expires_at.isoformat()}
