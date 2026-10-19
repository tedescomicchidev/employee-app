from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query, Request, Response

from app.auth.principal import Principal, Role, authorize, current_principal
from app.vacation.models import DayCount, VacationRequest
from app.vacation.serialize import count_json, holiday_json
from app.vacation.service import Review, VacationService, parse_date, parse_draft

router = APIRouter(prefix="/v1/vacation")

Caller = Annotated[Principal, Depends(current_principal)]
Body = dict[str, Any]


def get_service(request: Request) -> VacationService:
    return request.app.state.vacation_service


Service = Annotated[VacationService, Depends(get_service)]


def review_json(review: Review) -> dict[str, Any]:
    return {
        **count_json(review.count),
        "remaining": review.balance.remaining,
        "remaining_after": review.remaining_after,
        "balance_year": review.balance.year,
        "approver": review.approver_name,
        "canton": review.canton,
    }


def _request(r: VacationRequest) -> dict[str, Any]:
    return {
        "id": r.id,
        "status": r.status,
        "start": r.start.isoformat(),
        "end": r.end.isoformat(),
        **count_json(DayCount(r.counted_days, r.per_year, r.excluded)),
        "approver": r.approver_name,
        "owner_oid": r.owner_oid,
        "owner_name": r.owner_name,
        "created_at": r.created_at.isoformat(),
        "decided_at": r.decided_at.isoformat() if r.decided_at else None,
        "reason": r.decision_reason,
    }


@router.get("/balance")
def get_balance(principal: Caller, service: Service) -> dict[str, Any]:
    b = service.balance(principal)
    return {
        "year": b.year,
        "entitlement": b.entitlement,
        "carried_over": b.carried_over,
        "approved": b.approved,
        "pending": b.pending,
        "remaining": b.remaining,
    }


@router.get("/holidays")
def get_holidays(
    principal: Caller,
    service: Service,
    year: Annotated[int | None, Query(ge=2000, le=2100)] = None,
    lang: Annotated[str | None, Query(max_length=2)] = None,
) -> dict[str, Any]:
    rows = service.holidays(principal, year)
    return {
        "year": year or service.today().year,
        "canton": rows[0].canton if rows else None,
        "status": "HUMAN_CONFIRMATION_REQUIRED",
        "holidays": [holiday_json(h, lang) for h in rows],
    }


@router.get("/requests")
def list_requests(principal: Caller, service: Service) -> dict[str, Any]:
    return {"items": [_request(r) for r in service.requests(principal)]}


@router.post("/requests")
def create_request(principal: Caller, service: Service, body: Body, response: Response) -> Any:
    token = body.get("confirmation_token")
    result = service.create(principal, parse_draft(body), token if isinstance(token, str) else None)
    response.status_code = 201 if result.created else 200
    return {**_request(result.request), "created": result.created}


@router.get("/requests/{request_id}")
def get_request(request_id: str, principal: Caller, service: Service) -> dict[str, Any]:
    request = service.get_request(principal, request_id)
    row = _request(request)
    balance = service.owner_balance(principal, request)
    if balance is not None:
        row["owner_balance"] = {
            "year": balance.year,
            "entitlement": balance.entitlement,
            "carried_over": balance.carried_over,
            "approved": balance.approved,
            "pending": balance.pending,
            "remaining": balance.remaining,
        }
    return row


@router.post("/requests/{request_id}/decision")
def decide_request(request_id: str, principal: Caller, service: Service, body: Body) -> Any:
    token = body.get("confirmation_token")
    return _request(
        service.decide(
            principal,
            request_id,
            body.get("decision", ""),
            body.get("reason"),
            token if isinstance(token, str) else None,
        )
    )


@router.post("/requests/{request_id}/cancel")
def cancel_request(request_id: str, principal: Caller, service: Service, body: Body) -> Any:
    token = body.get("confirmation_token")
    return _request(
        service.cancel(principal, request_id, token if isinstance(token, str) else None)
    )


@router.get("/inbox")
def get_inbox(principal: Caller, service: Service) -> dict[str, Any]:
    authorize(principal, Role.MANAGER)
    return {"items": [_request(r) for r in service.inbox(principal)]}


@router.get("/coverage")
def get_coverage(
    principal: Caller,
    service: Service,
    start: Annotated[str | None, Query()] = None,
    end: Annotated[str | None, Query()] = None,
) -> dict[str, Any]:
    first = parse_date("start", start) if start else None
    last = parse_date("end", end) if end else None
    days = service.coverage(principal, first, last)
    return {
        "start": (first or service.today()).isoformat(),
        "end": days[-1].date.isoformat() if days else None,
        "days": [
            {
                "date": d.date.isoformat(),
                "present": d.present,
                "total": d.total,
                "absent": [
                    {
                        "request_id": a.request_id,
                        "name": a.name,
                        "status": a.status,
                        "start": a.start.isoformat(),
                        "end": a.end.isoformat(),
                    }
                    for a in d.absent
                ],
            }
            for d in days
        ],
    }


@router.get("/decisions")
def get_decisions(principal: Caller, service: Service) -> dict[str, Any]:
    authorize(principal, Role.MANAGER)
    return {"items": [_request(r) for r in service.decisions(principal)]}
