from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from app.auth.errors import FieldError
from app.auth.principal import Principal, current_principal
from app.briefing.models import BriefDay, BriefEvent, Briefing, FreeBlock, OptInState
from app.briefing.service import BriefingService

router = APIRouter(prefix="/v1/briefing")

Body = dict[str, Any]
Caller = Annotated[Principal, Depends(current_principal)]


def get_service(request: Request) -> BriefingService:
    return request.app.state.briefing_service


Service = Annotated[BriefingService, Depends(get_service)]


def state_json(state: OptInState) -> dict[str, Any]:
    return {
        "opted_in": state.opted_in,
        "opted_in_at": state.opted_in_at.isoformat() if state.opted_in_at else None,
    }


def event_json(e: BriefEvent) -> dict[str, Any]:
    return {
        "id": e.id,
        "title": e.title,
        "start": e.start.isoformat(),
        "end": e.end.isoformat(),
        "all_day": e.all_day,
        "location": e.location,
        "online": e.online,
        "attendee_count": e.attendee_count,
        "conflicts_with": list(e.conflicts_with),
    }


def free_json(b: FreeBlock) -> dict[str, Any]:
    return {"start": b.start.isoformat(), "end": b.end.isoformat(), "minutes": b.minutes}


def day_json(d: BriefDay) -> dict[str, Any]:
    return {
        "date": d.day.isoformat(),
        "events": [event_json(e) for e in d.events],
        "free_blocks": [free_json(b) for b in d.free_blocks],
    }


def briefing_json(b: Briefing) -> dict[str, Any]:
    """The same shape for REST and the MCP tool. `partial` names the days Work IQ did not answer."""
    return {
        "week_start": b.week_start.isoformat(),
        "week_end": b.week_end.isoformat(),
        "timezone": "Europe/Zurich",
        "event_count": b.event_count,
        "conflict_count": b.conflict_count,
        "partial": b.partial,
        "missing_days": [d.isoformat() for d in b.missing_days],
        "days": [day_json(d) for d in b.days],
    }


@router.get("/status")
def status(principal: Caller, service: Service) -> dict[str, Any]:
    return state_json(service.status(principal))


@router.get("/week")
def week(principal: Caller, service: Service) -> dict[str, Any]:
    """The caller's own week. No user parameter exists (FR-BRF-004); never cached or stored."""
    return briefing_json(service.week(principal))


@router.post("/opt-in")
def set_opt_in(principal: Caller, service: Service, body: Body) -> dict[str, Any]:
    """Turn the briefing on or off. A write: needs the confirmation_token from the confirm card."""
    enabled = body.get("enabled")
    if not isinstance(enabled, bool):
        raise FieldError("enabled", "true or false")
    token = body.get("confirmation_token")
    return state_json(
        service.set_opt_in(principal, enabled, token if isinstance(token, str) else None)
    )
