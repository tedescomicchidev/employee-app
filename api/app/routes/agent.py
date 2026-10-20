import logging
import time
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse

from app.agents.foundry import AgentError, AgentResponder, AgentSettings, ToolsTokenClient
from app.agents.stream import turn_events, with_warmup
from app.agents.turns import (
    AgentRunLog,
    TurnRateLimiter,
    TurnRequest,
    ground_reply,
    parse_reply,
    run_record,
    tool_trace,
)
from app.auth.errors import ApiError, not_found
from app.auth.principal import Principal, current_principal
from app.telemetry import TASK_RUN_HEADER

router = APIRouter(prefix="/v1")
logger = logging.getLogger(__name__)

Caller = Annotated[Principal, Depends(current_principal)]


def _task_run_id(request: Request) -> UUID | None:
    try:
        return UUID(request.headers.get(TASK_RUN_HEADER, ""))
    except ValueError:
        return None


@router.post("/agent/{agent}/turns", response_model=None)
def agent_turn(
    agent: str, body: TurnRequest, principal: Caller, request: Request
) -> dict[str, Any] | StreamingResponse:
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
        raise ApiError(
            429,
            "RATE_LIMITED",
            "Too many requests; try again in a minute",
            headers={"Retry-After": str(limiter.retry_after(principal.oid))},
        )
    if len(body.messages) > settings.max_messages or any(
        len(m.content) > settings.max_message_chars for m in body.messages
    ):
        raise ApiError(413, "PAYLOAD_TOO_LARGE", "The conversation is too long")
    messages = [m.model_dump() for m in body.messages]
    if body.confirmation:
        # Own, unexpired proposal only (NOT_FOUND otherwise); the draft comes from the store.
        proposal_id = str(body.confirmation.proposal_id)
        if agent == "vacation":
            proposal = state.vacation_service.get_proposal(principal, proposal_id)
        elif agent == "briefing":
            proposal = state.briefing_service.get_proposal(principal, proposal_id)
        else:
            proposal = state.announcement_service.get_proposal(principal, proposal_id).proposal
        messages.append(body.confirmation.as_message(proposal.draft.canonical()))
    run_id = _task_run_id(request)
    started = time.perf_counter()
    run_ref = str(run_id) if run_id else None

    def finish(response: dict[str, Any]) -> dict[str, Any]:
        log: AgentRunLog = state.agent_runs
        latency = round((time.perf_counter() - started) * 1000)
        log.runs.append(run_record(response, run_id, latency))
        reply = ground_reply(parse_reply(response, agent), state, principal, response)
        return {"reply": reply.model_dump(mode="json"), "tool_calls": tool_trace(response)}

    def fail(exc: AgentError) -> ApiError:
        # The stable code only (never a token, prompt or reply): foundry_403, consent_required, ...
        logger.warning("agent turn failed: agent=%s code=%s", agent, exc.code)
        status = 403 if exc.code in ("consent_required", "interaction_required") else 502
        return ApiError(status, "AGENT_UNAVAILABLE", "The assistant could not be reached")

    if "text/event-stream" in request.headers.get("accept", ""):
        # Everything that can fail with a status code fails before the stream opens.
        try:
            tools_token = tools_tokens.acquire(principal.assertion)
        except AgentError as exc:
            raise fail(exc) from exc
        upstream = responder.stream(foundry_agent, principal.oid, tools_token, messages, run_ref)
        return StreamingResponse(
            turn_events(with_warmup(upstream), agent, finish),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
        )
    try:
        tools_token = tools_tokens.acquire(principal.assertion)
        response = responder.respond(
            foundry_agent,
            principal.oid,  # validated claim, never a client-supplied identity
            tools_token,
            messages,
            run_ref,
        )
    except AgentError as exc:
        raise fail(exc) from exc
    return finish(response)
