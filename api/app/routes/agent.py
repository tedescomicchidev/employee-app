import time
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Request

from app.agents.foundry import AgentError, AgentResponder, AgentSettings, ToolsTokenClient
from app.agents.turns import (
    AgentRunLog,
    TurnRateLimiter,
    TurnRequest,
    parse_reply,
    run_record,
    tool_trace,
)
from app.auth.errors import ApiError, not_found
from app.auth.principal import Principal, current_principal
from app.telemetry import TASK_RUN_HEADER

router = APIRouter(prefix="/v1")

Caller = Annotated[Principal, Depends(current_principal)]


def _task_run_id(request: Request) -> UUID | None:
    try:
        return UUID(request.headers.get(TASK_RUN_HEADER, ""))
    except ValueError:
        return None


@router.post("/agent/{agent}/turns")
def agent_turn(
    agent: str, body: TurnRequest, principal: Caller, request: Request
) -> dict[str, Any]:
    state = request.app.state
    settings: AgentSettings = state.agent_settings
    foundry_agent = settings.agents.get(agent)
    if foundry_agent is None:
        raise not_found()
    responder: AgentResponder | None = state.agent_responder
    tools_tokens: ToolsTokenClient | None = state.tools_token_client
    if not settings.enabled or responder is None or tools_tokens is None:
        raise ApiError(503, "AGENT_NOT_CONFIGURED", "The assistant is not available")
    limiter: TurnRateLimiter = state.turn_limiter
    if not limiter.allow(principal.oid):
        raise ApiError(429, "RATE_LIMITED", "Too many requests; try again in a minute")
    if len(body.messages) > settings.max_messages or any(
        len(m.content) > settings.max_message_chars for m in body.messages
    ):
        raise ApiError(413, "PAYLOAD_TOO_LARGE", "The conversation is too long")
    messages = [m.model_dump() for m in body.messages]
    if body.confirmation:
        # Own, unexpired proposal only (NOT_FOUND otherwise); the draft comes from the store.
        card = state.announcement_service.get_proposal(
            principal, str(body.confirmation.proposal_id)
        )
        messages.append(body.confirmation.as_message(card.proposal.draft.canonical()))
    run_id = _task_run_id(request)
    started = time.perf_counter()
    try:
        tools_token = tools_tokens.acquire(principal.assertion)
        response = responder.respond(
            foundry_agent,
            principal.oid,  # validated claim, never a client-supplied identity
            tools_token,
            messages,
            str(run_id) if run_id else None,
        )
    except AgentError as exc:
        status = 403 if exc.code in ("consent_required", "interaction_required") else 502
        raise ApiError(status, "AGENT_UNAVAILABLE", "The assistant could not be reached") from exc
    log: AgentRunLog = state.agent_runs
    log.runs.append(run_record(response, run_id, round((time.perf_counter() - started) * 1000)))
    return {
        "reply": parse_reply(response).model_dump(mode="json"),
        "tool_calls": tool_trace(response),
    }
