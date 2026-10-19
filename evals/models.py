"""Eval case, trace and result models. The dataset (comms/dataset.jsonl) is the spec."""

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

Persona = Literal["ceo", "mgr1", "mgr2", "emp1", "emp4"]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ToolCall(Strict):
    name: str
    ok: bool = True
    # Only present on recorded attack traces, which api/tests/test_agent_eval_replay.py replays
    # against the real MCP server. Live traces carry names only (the API returns no arguments).
    args: dict[str, Any] | None = None


class Reply(Strict):
    kind: Literal["message", "clarification", "proposal", "published"] = "message"
    text: str = ""
    proposal_id: str | None = None


class Trace(Strict):
    """What happened in one scenario, however it was produced (recording or live run)."""

    tools: list[ToolCall] = Field(default_factory=list)
    replies: list[Reply] = Field(default_factory=list)  # one per agent turn
    confirmed: bool = False  # the confirm-card step happened before the last turn
    proposal: dict[str, Any] | None = None  # the stored proposal payload, if any
    created: int = 0  # announcements the run created


class Fixture(Strict):
    """An announcement that exists before the scenario starts (published by `author`)."""

    author: Persona = "ceo"
    title: str
    body: str
    language: Literal["de", "fr", "it", "en"] = "de"
    audience: str | dict[str, list[str]] = "all"


class Turn(Strict):
    user: str | None = None  # a chat message
    confirm_card: bool = False  # the user taps Confirm on the card of the last proposal


class Expect(Strict):
    tools_allowed: list[str] | None = None  # when set, no other tool may be called
    tools_required: list[str] = Field(default_factory=list)
    tools_forbidden: list[str] = Field(default_factory=list)
    proposal: dict[str, Any] | None = None  # subset of the stored proposal payload
    last_reply_kind_in: list[str] | None = None
    reply_must_not_match: list[str] = Field(default_factory=list)  # regexes over all reply text
    reply_must_match_any: list[str] = Field(default_factory=list)
    reply_mentions_all: list[str] = Field(default_factory=list)
    reply_mentions_none: list[str] = Field(default_factory=list)
    created: int = 0


class Violation(Strict):
    """A recorded bad behaviour the scorer must catch (proves the rules discriminate)."""

    name: str
    fails_with: str  # failure code prefix the scorer must report
    trace: Trace


class Case(Strict):
    id: str
    set: Literal["safety", "functional"]
    requirements: list[str] = Field(min_length=1)
    source: str  # scenario title in docs/product/test-cases.md ("" for cases added by this slice)
    persona: Persona
    fixtures: list[Fixture] = Field(default_factory=list)
    turns: list[Turn] = Field(min_length=1)
    expect: Expect
    golden: Trace  # a trace that must pass
    violations: list[Violation] = Field(default_factory=list)


class CaseResult(Strict):
    id: str
    set: str
    failures: list[str]

    @property
    def passed(self) -> bool:
        return not self.failures
