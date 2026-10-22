"""Eval case, trace and result models. The datasets (comms/, vacation/, briefing/) are the spec."""

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

Persona = Literal["ceo", "mgr1", "mgr2", "emp1", "emp2", "emp4"]
AgentName = Literal["comms", "vacation", "briefing"]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ToolCall(Strict):
    name: str
    ok: bool = True
    # Only present on recorded attack traces, which api/tests/test_agent_eval_replay.py replays
    # against the real MCP server. Live traces carry names only (the API returns no arguments).
    args: dict[str, Any] | None = None


class ReplyOption(Strict):
    proposal_id: str
    start: str
    end: str


class ReplySource(Strict):
    announcement_id: str
    title: str = ""


class Reply(Strict):
    kind: Literal[
        "message", "clarification", "proposal", "published",  # comms
        "options", "submitted", "cancelled", "decided",  # vacation
        "opted_in", "summary",  # briefing
        "refusal",  # all
    ] = "message"  # fmt: skip
    text: str = ""
    proposal_id: str | None = None
    options: list[ReplyOption] = Field(default_factory=list)
    reason: str | None = None
    sources: list[ReplySource] = Field(default_factory=list)
    omitted_count: int | None = None  # briefing summary: events left out of the text


class Trace(Strict):
    """What happened in one scenario, however it was produced (recording or live run)."""

    tools: list[ToolCall] = Field(default_factory=list)
    replies: list[Reply] = Field(default_factory=list)  # one per agent turn
    confirmed: bool = False  # the confirm-card step happened before the last turn
    proposal: dict[str, Any] | None = None  # the stored proposal payload, if any
    created: int = 0  # records the run created or changed: announcements, or vacation requests
    # Numbers the api itself holds for this scenario (vacation: balance, review of the stored
    # proposal, plus any number a tool result carried in a recorded trace). A day count in a reply
    # that is in no fact, no user message and no `expect.facts` was invented by the model.
    facts: list[int] = Field(default_factory=list)


class Fixture(Strict):
    """An announcement that exists before the scenario starts (published by `author`)."""

    author: Persona = "ceo"
    title: str
    body: str
    language: Literal["de", "fr", "it", "en"] = "de"
    audience: str | dict[str, list[str]] = "all"


class VacationFixture(Strict):
    """A vacation request that exists before the scenario starts (booked by `owner`)."""

    owner: Persona
    start: str  # ISO date
    end: str
    status: Literal["pending", "approved", "rejected"] = "pending"
    reason: str | None = None  # the manager's reject reason (untrusted text in tool results)


class CalendarEvent(Strict):
    title: str
    day: int = Field(ge=0, le=6)  # offset from the week's Monday
    start: str  # HH:MM Europe/Zurich
    end: str
    attendees: int = 0


class BriefingFixture(Strict):
    """The state before a briefing scenario: whether `owner` opted in, and the calendar they have.

    Live runs cannot write a calendar (the api only reads it), so `events` is what the human has
    seeded in the dev tenant; the runner checks it against GET /v1/briefing/week and fails the case
    (`run_error`) when it differs, rather than scoring an agent against the wrong data.
    """

    owner: Persona
    opted_in: bool = True
    events: list[CalendarEvent] = Field(default_factory=list)


class Turn(Strict):
    user: str | None = None  # a chat message
    confirm_card: bool = False  # the user taps Confirm on the card of the last proposal


class Expect(Strict):
    tools_allowed: list[str] | None = None  # when set, no other tool may be called
    tools_required: list[str] = Field(default_factory=list)
    tools_forbidden: list[str] = Field(default_factory=list)
    proposal: dict[str, Any] | None = None  # subset of the stored proposal payload
    last_reply_kind_in: list[str] | None = None
    refusal_reason: str | None = None  # when set, a refusal must carry exactly this reason
    reply_must_not_match: list[str] = Field(default_factory=list)  # regexes over all reply text
    reply_must_match_any: list[str] = Field(default_factory=list)
    reply_mentions_all: list[str] = Field(default_factory=list)
    reply_mentions_none: list[str] = Field(default_factory=list)
    created: int = 0
    facts: list[int] = Field(default_factory=list)  # numbers the scenario's data legitimately has
    # Briefing: titles of the persona's events. A summary must name each of them or count it in
    # `omitted_count`; it must not mention any title listed in `reply_mentions_none`.
    events: list[str] = Field(default_factory=list)


class Violation(Strict):
    """A recorded bad behaviour the scorer must catch (proves the rules discriminate)."""

    name: str
    fails_with: str  # failure code prefix the scorer must report
    trace: Trace


class Case(Strict):
    id: str
    agent: AgentName = "comms"
    set: Literal["safety", "functional"]
    requirements: list[str] = Field(min_length=1)
    source: str  # scenario title in docs/product/test-cases.md ("" for cases added by this slice)
    persona: Persona
    fixtures: list[Fixture | VacationFixture | BriefingFixture] = Field(default_factory=list)
    turns: list[Turn] = Field(min_length=1)
    expect: Expect
    golden: Trace  # a trace that must pass
    violations: list[Violation] = Field(default_factory=list)
    # False for a condition a live run cannot produce (Work IQ failing, a partial week). Those cases
    # are scored offline and their attack traces replayed against api/; live skips them.
    live: bool = True


class CaseResult(Strict):
    id: str
    set: str
    failures: list[str]

    @property
    def passed(self) -> bool:
        return not self.failures
