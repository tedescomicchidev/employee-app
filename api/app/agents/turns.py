"""Turn handling: limits, the structured reply the app renders, and what is recorded per run.

The app renders confirm cards from `GET /v1/proposals/{id}`, never from model text, so a reply
only ever carries a proposal *id* (auth-flows.md flow 3, assumption A-13).
"""

import json
import math
import re
import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import date
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from app.vacation.models import ACTION_REQUEST

PUBLISH_TOOL = "publish_announcement"
# A reply kind that claims a write is believed only if this turn really made that tool call.
CLAIM_TOOLS: dict[str, dict[str, str]] = {
    "comms": {"published": PUBLISH_TOOL},
    "vacation": {
        "submitted": "create_vacation_request",
        "cancelled": "cancel_vacation_request",
        "decided": "decide_vacation_request",
    },
    "briefing": {"opted_in": "set_briefing_optin", "summary": "get_my_week"},
}


class Message(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1)


class Confirmation(BaseModel):
    """The tap on the confirm card, sent by the app after POST /v1/confirmations (auth-flows.md
    flow 3). The format is checked here so the field cannot carry free text to the model."""

    model_config = ConfigDict(extra="forbid")
    proposal_id: UUID
    confirmation_token: str = Field(pattern=r"^[A-Za-z0-9_-]{20,64}$")

    def as_message(self, draft: dict[str, Any]) -> dict[str, str]:
        """`draft` is the stored proposal, so what is published is exactly what was confirmed."""
        return {
            "role": "user",
            "content": (
                f"The user confirmed proposal {self.proposal_id} on the confirm card. "
                f"confirmation_token={self.confirmation_token} "
                f"confirmed_draft={json.dumps(draft, ensure_ascii=False, sort_keys=True)}"
            ),
        }


class TurnRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    messages: list[Message] = Field(min_length=1)
    confirmation: Confirmation | None = None


COMMS_REASONS = (
    "write_without_confirmation", "role_not_allowed", "out_of_scope", "other_users_data",
    "untrusted_instructions", "unsupported_action",
)  # fmt: skip
VACATION_REASONS = (
    "write_without_confirmation", "role_not_allowed", "rule_bypass", "out_of_scope",
    "other_users_data", "untrusted_instructions", "unsupported_action",
)  # fmt: skip
BRIEFING_REASONS = (
    "write_without_confirmation", "other_users_data", "out_of_scope", "untrusted_instructions",
    "unsupported_action",
)  # fmt: skip
FALLBACK_REASON = "unsupported_action"
MAX_SOURCES = 10


def _known_reason(value: Any, allowed: tuple[str, ...]) -> Any:
    """A refusal reason is a closed set. An unknown code is still a refusal, so it is mapped to the
    generic one instead of failing the whole reply (which would show the model's raw output)."""
    if value is None or value in allowed:
        return value
    return FALLBACK_REASON


class Source(BaseModel):
    """An announcement the answer is based on. The title is replaced from the store."""

    model_config = ConfigDict(extra="ignore")
    announcement_id: UUID
    title: str = Field(default="", max_length=200)


class AgentReply(BaseModel):
    """Mirror of agents/comms/comms_schemas.py: the hosted agent's final output."""

    model_config = ConfigDict(extra="ignore")
    kind: Literal["message", "clarification", "proposal", "published", "refusal"] = "message"
    text: str = Field(default="", max_length=4000)
    proposal_id: UUID | None = None
    reason: str | None = None
    sources: list[Source] = Field(default_factory=list, max_length=MAX_SOURCES)

    @field_validator("reason", mode="before")
    @classmethod
    def _reason(cls, value: Any) -> Any:
        return _known_reason(value, COMMS_REASONS)


class VacationOption(BaseModel):
    """One candidate range. Dates only: the numbers on the card come from the stored proposal."""

    model_config = ConfigDict(extra="ignore")
    proposal_id: UUID
    start: date
    end: date


class VacationReply(BaseModel):
    """Mirror of agents/vacation/vacation_schemas.py: the hosted vacation agent's final output."""

    model_config = ConfigDict(extra="ignore")
    kind: Literal[
        "message",
        "clarification",
        "options",
        "proposal",
        "submitted",
        "cancelled",
        "decided",
        "refusal",
    ] = "message"
    text: str = Field(default="", max_length=4000)
    proposal_id: UUID | None = None
    options: list[VacationOption] = Field(default_factory=list, max_length=3)
    reason: str | None = None

    @field_validator("reason", mode="before")
    @classmethod
    def _reason(cls, value: Any) -> Any:
        return _known_reason(value, VACATION_REASONS)


class BriefingReply(BaseModel):
    """Mirror of agents/briefing/briefing_schemas.py: the hosted briefing agent's final output.

    `summary` is a conversational summary of the user's own week. It is believed only if
    `get_my_week` succeeded in this turn; the full list is the Briefing screen (`omitted_count`).
    """

    model_config = ConfigDict(extra="ignore")
    kind: Literal["message", "clarification", "proposal", "opted_in", "summary", "refusal"] = (
        "message"
    )
    text: str = Field(default="", max_length=4000)
    proposal_id: UUID | None = None
    omitted_count: int | None = Field(default=None, ge=0, le=1000)
    reason: str | None = None

    @field_validator("reason", mode="before")
    @classmethod
    def _reason(cls, value: Any) -> Any:
        return _known_reason(value, BRIEFING_REASONS)


MODELS: dict[str, type[BaseModel]] = {
    "comms": AgentReply,
    "vacation": VacationReply,
    "briefing": BriefingReply,
}


@dataclass(frozen=True)
class AgentRun:
    """EXP-005 `agent_run`, joined to the task by `task_run_id`. Counts only; no content."""

    task_run_id: UUID | None
    model_id: str
    input_tokens: int
    output_tokens: int
    tool_call_count: int
    latency_ms: int


class AgentRunLog:
    def __init__(self, limit: int = 50_000) -> None:
        self.runs: deque[AgentRun] = deque(maxlen=limit)


class TurnRateLimiter:
    """Per-user sliding window (NFR-011). In memory per replica; the edge limit is infra's job."""

    def __init__(self, per_minute: int, clock: Any = time.monotonic) -> None:
        self._per_minute = per_minute
        self._clock = clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, user: str) -> bool:
        with self._lock:
            now = self._clock()
            hits = self._hits[user]
            while hits and now - hits[0] >= 60:
                hits.popleft()
            if len(hits) >= self._per_minute:
                return False
            hits.append(now)
            return True

    def retry_after(self, user: str) -> int:
        """Whole seconds until the oldest hit leaves the window (at least 1)."""
        with self._lock:
            hits = self._hits[user]
            if not hits:
                return 1
            return max(1, math.ceil(60 - (self._clock() - hits[0])))


def _items(response: dict[str, Any]) -> list[dict[str, Any]]:
    return [i for i in response.get("output") or [] if isinstance(i, dict)]


def output_text(response: dict[str, Any]) -> str:
    parts = [
        str(c.get("text", ""))
        for item in _items(response)
        if item.get("type") == "message"
        for c in item.get("content") or []
        if isinstance(c, dict) and c.get("type") == "output_text"
    ]
    return "".join(parts)


def tool_calls(response: dict[str, Any]) -> list[dict[str, Any]]:
    return [i for i in _items(response) if str(i.get("type", "")).endswith("_call")]


def tool_trace(response: dict[str, Any]) -> list[dict[str, Any]]:
    """Which tools ran and whether each succeeded. Names only: no arguments, no results."""
    return [
        {"name": str(c.get("name", "")), "ok": not c.get("error")} for c in tool_calls(response)
    ]


def parse_reply(
    response: dict[str, Any], agent: str = "comms"
) -> AgentReply | VacationReply | BriefingReply:
    text = output_text(response)
    model: Any = MODELS.get(agent, AgentReply)
    try:
        data = json.loads(text)
    except ValueError:
        return model(kind="message", text=text[:4000])  # plain text, as the model wrote it
    try:
        reply = model.model_validate(data)
    except ValidationError:
        # A structured reply that broke the schema (too many sources, a bad kind, an extra field):
        # keep only its text. The raw JSON is never shown to the user.
        salvaged = data.get("text") if isinstance(data, dict) else None
        return model(kind="message", text=salvaged[:4000] if isinstance(salvaged, str) else "")
    # A claimed write is only believed when the tool really succeeded in this turn.
    claim_tool = CLAIM_TOOLS.get(agent, {}).get(reply.kind)
    if claim_tool and not any(
        c.get("name") == claim_tool and not c.get("error") for c in tool_calls(response)
    ):
        return model(kind="message", text=reply.text)
    if reply.kind == "proposal" and reply.proposal_id is None:
        return model(kind="message", text=reply.text)
    if isinstance(reply, VacationReply) and reply.kind == "options" and not reply.options:
        return VacationReply(kind="message", text=reply.text)
    return reply


def ground_vacation_reply(reply: VacationReply, service: Any, principal: Any) -> VacationReply:
    """Tie the reply to what the api stored for this user (FR-VAC-002).

    A proposal id must be the caller's own, unexpired proposal. Option dates are copied from the
    stored draft, never from the model, so a chooser cannot show one range over another's id.
    Anything that does not resolve downgrades the reply to a plain message.
    """

    def stored(proposal_id: UUID | None, action: str | None = None) -> Any:
        if proposal_id is None:
            return None
        try:
            proposal = service.get_proposal(principal, str(proposal_id))
        except Exception:  # ApiError: unknown, someone else's or expired look the same
            return None
        return proposal if action is None or proposal.action == action else None

    if reply.kind == "proposal" and stored(reply.proposal_id) is None:
        return VacationReply(kind="message", text=reply.text)
    if reply.kind not in ("proposal", "options"):
        # No card and no chooser for this kind: a stray id or range cannot become one.
        reply = reply.model_copy(update={"proposal_id": None, "options": []})
    if reply.kind != "refusal" and reply.reason is not None:
        reply = reply.model_copy(update={"reason": None})
    if reply.kind == "options":
        reply = reply.model_copy(update={"proposal_id": None})
        grounded = []
        for option in reply.options:
            proposal = stored(option.proposal_id, ACTION_REQUEST)
            if proposal is not None:
                grounded.append(
                    VacationOption(
                        proposal_id=option.proposal_id,
                        start=proposal.draft.start,
                        end=proposal.draft.end,
                    )
                )
        if not grounded:
            return VacationReply(kind="message", text=reply.text)
        return reply.model_copy(update={"options": grounded})
    return reply


TOOL_ID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
ANNOUNCEMENT_TOOLS = ("list_announcements", "get_announcement")


def announcement_ids_read(response: dict[str, Any]) -> set[str]:
    """Ids of the announcements this turn's read tools returned. An answer may only cite these, so
    the model cannot cite one it did not read (one it never opened, or one a tool result named)."""
    found: set[str] = set()
    for call in tool_calls(response):
        if call.get("name") not in ANNOUNCEMENT_TOOLS or call.get("error"):
            continue
        output = call.get("output")
        text = output if isinstance(output, str) else json.dumps(output, default=str)
        found.update(match.lower() for match in TOOL_ID.findall(text))
    return found


def ground_comms_reply(
    reply: AgentReply, service: Any, principal: Any, read_ids: set[str] | None = None
) -> AgentReply:
    """Tie the reply to what the api stored or shows this user (FR-ANN-001, FR-ANN-003).

    A proposal id must be the caller's own, unexpired proposal. A source must be an announcement the
    turn's tools returned AND this user can see; its title comes from the store, not from the model.
    Fields that do not belong to the reply's kind are cleared, so a stray id cannot become a card.
    Anything that does not resolve is dropped or downgraded.
    """
    if reply.kind == "proposal":
        try:
            service.get_proposal(principal, str(reply.proposal_id))
        except Exception:  # ApiError: unknown, someone else's or expired look the same
            return AgentReply(kind="message", text=reply.text)
    update: dict[str, Any] = {}
    if reply.kind != "proposal":
        update["proposal_id"] = None
    if reply.kind != "refusal":
        update["reason"] = None
    allowed = read_ids if read_ids is not None else set()
    sources: list[Source] = []
    for source in reply.sources if reply.kind == "message" else []:
        if str(source.announcement_id).lower() not in allowed:
            continue
        if any(s.announcement_id == source.announcement_id for s in sources):
            continue
        try:
            announcement, _ = service.get_for(principal, str(source.announcement_id))
        except Exception:
            continue
        sources.append(Source(announcement_id=source.announcement_id, title=announcement.title))
    update["sources"] = sources
    return reply.model_copy(update=update)


def ground_briefing_reply(reply: BriefingReply, service: Any, principal: Any) -> BriefingReply:
    """Tie the reply to what the api stored for this user (FR-BRF-001).

    A proposal id must be the caller's own, unexpired opt-in proposal. Fields that do not belong to
    the reply's kind are cleared, so a stray id or count cannot become a card or a claim.
    """
    if reply.kind == "proposal":
        try:
            service.get_proposal(principal, str(reply.proposal_id))
        except Exception:  # ApiError: unknown, someone else's or expired look the same
            return BriefingReply(kind="message", text=reply.text)
    update: dict[str, Any] = {}
    if reply.kind != "proposal":
        update["proposal_id"] = None
    if reply.kind != "refusal":
        update["reason"] = None
    if reply.kind != "summary":
        update["omitted_count"] = None
    return reply.model_copy(update=update)


def ground_reply(
    reply: AgentReply | VacationReply | BriefingReply,
    state: Any,
    principal: Any,
    response: dict[str, Any] | None = None,
) -> Any:
    if isinstance(reply, BriefingReply):
        return ground_briefing_reply(reply, state.briefing_service, principal)
    if isinstance(reply, VacationReply):
        return ground_vacation_reply(reply, state.vacation_service, principal)
    read_ids = announcement_ids_read(response) if response is not None else set()
    return ground_comms_reply(reply, state.announcement_service, principal, read_ids)


def run_record(response: dict[str, Any], task_run_id: UUID | None, latency_ms: int) -> AgentRun:
    usage = response.get("usage") or {}
    return AgentRun(
        task_run_id=task_run_id,
        model_id=str(response.get("model") or ""),
        input_tokens=int(usage.get("input_tokens") or 0),
        output_tokens=int(usage.get("output_tokens") or 0),
        tool_call_count=len(tool_calls(response)),
        latency_ms=latency_ms,
    )
