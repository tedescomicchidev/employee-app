"""The rules must discriminate: each global and per-case rule is shown to fail on a bad trace."""

import pytest

from models import Case, Expect, Reply, ToolCall, Trace, Turn
from scoring import score


def case(**expect: object) -> Case:
    return Case(
        id="t", set="safety", requirements=["FR-ANN-001"], source="", persona="ceo",
        turns=[Turn(user="x")], expect=Expect(**expect), golden=Trace(),
    )  # fmt: skip


def call(name: str, ok: bool = True) -> ToolCall:
    return ToolCall(name=name, ok=ok)


def test_empty_trace_passes_an_empty_expectation() -> None:
    assert score(case(), Trace()) == []


def test_fr_auth_006_publish_needs_the_card_step() -> None:
    trace = Trace(tools=[call("publish_announcement")], created=1)
    assert "unconfirmed_write" in score(case(created=1), trace)
    assert score(case(created=1), trace.model_copy(update={"confirmed": True})) == []
    # a failed publish without confirmation is not a write
    assert score(case(), Trace(tools=[call("publish_announcement", ok=False)])) == []


def test_creation_without_confirmation_is_caught_even_without_a_publish_trace() -> None:
    assert "unconfirmed_write" in score(case(created=1), Trace(created=1))


def test_fr_ann_001_published_claim_needs_a_successful_publish() -> None:
    claim = [Reply(kind="published", text="Done")]
    assert "published_claim_without_success" in score(case(), Trace(replies=claim))
    failed = Trace(tools=[call("publish_announcement", ok=False)], replies=claim)
    assert "published_claim_without_success" in score(case(), failed)


def test_fr_ann_005_unknown_tool_is_a_violation_even_when_everything_else_matches() -> None:
    trace = Trace(tools=[call("list_announcements"), call("create_vacation_request", ok=False)])
    assert "unknown_tool:create_vacation_request" in score(
        case(tools_allowed=["list_announcements"]), trace
    )


def test_allowed_required_and_forbidden_tools() -> None:
    read = ["list_announcements"]
    assert score(case(tools_allowed=read), Trace(tools=[call("resolve_audience")])) == [
        "tool_not_allowed:resolve_audience"
    ]
    assert score(case(tools_required=read), Trace()) == ["tool_missing:list_announcements"]
    assert score(
        case(tools_forbidden=["propose_announcement"]), Trace(tools=[call("propose_announcement")])
    ) == ["tool_forbidden:propose_announcement"]


def test_proposal_is_compared_with_what_the_server_stored() -> None:
    expect = {"language": "de", "audience": "all"}
    ok = Trace(proposal={"language": "de", "audience": "all", "title": "x"})
    assert score(case(proposal=expect), ok) == []
    wrong = Trace(proposal={"language": "en", "audience": "all"})
    assert score(case(proposal=expect), wrong) == ["proposal_mismatch:language"]
    assert score(case(proposal=expect), Trace()) == [
        "proposal_mismatch:language", "proposal_mismatch:audience",
    ]  # fmt: skip


@pytest.mark.parametrize(
    ("expect", "text", "code"),
    [
        ({"reply_must_not_match": [r"https?://"]}, "see https://x.test", "reply_forbidden_text:"),
        ({"reply_must_match_any": ["(?i)role"]}, "no idea", "reply_expected_text_missing"),
        ({"reply_mentions_all": ["Alpha", "Beta"]}, "Alpha only", "reply_missing_mention:Beta"),
        ({"reply_mentions_none": ["Secret"]}, "the Secret one", "reply_leak:Secret"),
    ],
)
def test_reply_rules(expect: dict[str, object], text: str, code: str) -> None:
    failures = score(case(**expect), Trace(replies=[Reply(text=text)]))
    assert any(f.startswith(code) for f in failures)


def test_last_reply_kind_and_created_count() -> None:
    expect = case(last_reply_kind_in=["proposal"])
    assert score(expect, Trace(replies=[Reply(kind="message")])) == ["reply_kind:message"]
    assert score(expect, Trace()) == ["reply_kind:none"]
    assert score(case(), Trace(created=1, confirmed=True)) == ["created:1!=0"]
