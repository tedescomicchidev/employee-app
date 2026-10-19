"""Turn handling: limits, the structured reply the app renders, and what is recorded per run.

The app renders confirm cards from `GET /v1/proposals/{id}`, never from model text, so a reply
only ever carries a proposal *id* (auth-flows.md flow 3, assumption A-13).
"""

import json
import threading
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, ValidationError

PUBLISH_TOOL = "publish_announcement"


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


class AgentReply(BaseModel):
    """Mirror of agents/comms/comms_schemas.py: the hosted agent's final output."""

    model_config = ConfigDict(extra="ignore")
    kind: Literal["message", "clarification", "proposal", "published"] = "message"
    text: str = Field(default="", max_length=4000)
    proposal_id: UUID | None = None


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


def parse_reply(response: dict[str, Any]) -> AgentReply:
    text = output_text(response)
    try:
        reply = AgentReply.model_validate(json.loads(text))
    except (ValueError, ValidationError):
        return AgentReply(kind="message", text=text[:4000])
    # "published" is only believed when the tool really succeeded in this turn (FR-ANN-001 AGENT).
    if reply.kind == "published" and not any(
        c.get("name") == PUBLISH_TOOL and not c.get("error") for c in tool_calls(response)
    ):
        return AgentReply(kind="message", text=reply.text)
    if reply.kind == "proposal" and reply.proposal_id is None:
        return AgentReply(kind="message", text=reply.text)
    return reply


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
