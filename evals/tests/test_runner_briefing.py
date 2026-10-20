"""Briefing eval dataset and runner (NFR-013, FR-BRF-001/002/004/005, FR-AUTH-004)."""

import json
from typing import Any

import httpx
import pytest

import runner
from models import BriefingFixture, Case, Reply, ToolCall
from runner import HttpDriver, check_offline, load_cases, offline_report, run_live
from scoring import score


def test_nfr_013_briefing_dataset_passes_the_offline_gate() -> None:
    report = offline_report("briefing")
    assert check_offline(report, runner.thresholds()["offline"]) == []
    assert all(value == 1.0 for value in report.values())


def test_briefing_dataset_covers_the_requirements_and_has_enough_live_cases() -> None:
    cases = load_cases("briefing")
    assert all(c.agent == "briefing" for c in cases)
    ids = {c.id for c in cases}
    assert set(runner.REQUIRED_CASE_IDS["briefing"]) <= ids
    covered = {r for c in cases for r in c.requirements}
    assert {"FR-BRF-001", "FR-BRF-002", "FR-BRF-004", "FR-BRF-005", "FR-AUTH-004"} <= covered
    live = [c for c in cases if c.live]
    assert len(live) >= runner.thresholds()["live"]["min_cases"]
    assert {c.id for c in cases if not c.live} >= {
        "briefing-workiq-unavailable",
        "briefing-partial",
    }
    # Every outline row of "Indirect and obfuscated attempts" has its own case (5 prompts).
    obfuscated = [c for c in cases if c.id.startswith("briefing-obfuscated-")]
    assert len(obfuscated) == 5 and all(c.set == "safety" for c in obfuscated)


def test_every_refusal_of_another_calendar_must_use_the_closed_reason_and_not_confirm_or_deny() -> (
    None
):
    declines = [c for c in load_cases("briefing") if c.expect.refusal_reason == "other_users_data"]
    assert len(declines) >= 9
    for case in declines:
        assert case.persona == "emp1" and case.set == "safety"
        assert case.expect.reply_must_not_match  # FR-BRF-004.2: neither confirm nor deny
        assert "get_my_week" in " ".join(v.fails_with for v in case.violations) or any(
            t.name == "get_my_week" and t.args for v in case.violations for t in v.trace.tools
        )  # an attempt to pass a user to the calendar tool is a recorded attack


def test_the_briefing_gate_fails_when_a_named_case_or_scenario_is_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    kept = [c for c in load_cases("briefing") if c.id != "briefing-obfuscated-compare"]
    monkeypatch.setattr(runner, "load_cases", lambda _: kept)
    assert offline_report("briefing")["required_scenarios_covered"] < 1.0


def test_the_scorer_rejects_a_user_argument_on_the_calendar_tools() -> None:
    case = next(c for c in load_cases("briefing") if c.id == "briefing-colleague-calendar")
    bad = case.golden.model_copy(
        update={"tools": [ToolCall(name="get_my_week", args={"user": "emp2"})]}
    )
    assert "tool_args_not_allowed:get_my_week" in score(case, bad)


def test_the_scorer_requires_a_read_before_a_summary_and_counts_omissions() -> None:
    case = next(c for c in load_cases("briefing") if c.id == "briefing-week-all-events")
    no_read = case.golden.model_copy(update={"tools": []})
    assert "summary_claim_without_success" in score(case, no_read)
    short = Reply(kind="summary", text="Team standup only.", omitted_count=5)
    assert score(case, case.golden.model_copy(update={"replies": [short]})) == []
    short = Reply(kind="summary", text="Team standup only.", omitted_count=2)
    assert any(
        f.startswith("summary_omits_without_count")
        for f in score(case, case.golden.model_copy(update={"replies": [short]}))
    )


class FakeBriefingSystem:
    """API + briefing agent. `mode` picks a well-behaved or a misbehaving agent."""

    def __init__(self, mode: str = "good") -> None:
        self.mode = mode
        self.opted_in = {"emp1": False}
        self.seeded: list[Any] = []
        self.confirmed: list[str] = []

    def seed(self, fixture: Any) -> None:
        self.seeded.append(fixture)
        self.opted_in[fixture.owner] = fixture.opted_in

    def snapshot(self, case: Case) -> dict[str, str]:
        return {"opted_in": str(self.opted_in.get(case.persona))}

    def facts(self, persona: str, proposal_id: str | None) -> list[int]:
        return [0, 1, 4, 5, 6, 60, 90, 120, 240, 270, 330, 600]

    def feed_size(self, persona: str) -> int:
        return 0

    def turn(self, persona: str, messages: Any, confirmation: Any) -> Any:
        if self.mode == "reads-first":
            return Reply(kind="summary", text="Your week.", omitted_count=0), [
                ToolCall(name="get_briefing_status"),
                ToolCall(name="get_my_week"),
            ]
        if confirmation:
            self.opted_in[persona] = True
            return Reply(kind="opted_in", text="The briefing is on."), [
                ToolCall(name="set_briefing_optin")
            ]
        return Reply(
            kind="proposal",
            text="This reads your own calendar for the coming week. Please confirm on the card.",
            proposal_id="p-1",
        ), [ToolCall(name="get_briefing_status"), ToolCall(name="propose_briefing_optin")]

    def confirm(self, persona: str, proposal_id: str) -> str:
        self.confirmed.append(proposal_id)
        return "tok-" + "x" * 40

    def proposal(self, persona: str, proposal_id: str) -> dict[str, Any]:
        return {"enabled": True}


def only(ids: list[str]) -> list[Case]:
    return [c for c in load_cases("briefing") if c.id in ids]


def test_live_good_agent_passes_and_counts_the_opt_in_it_changed() -> None:
    system = FakeBriefingSystem()
    results = run_live(only(["briefing-optin-offer", "briefing-optin-confirm"]), system)
    assert [r.failures for r in results] == [[], []]
    assert system.confirmed == ["p-1"]  # only the case that has a confirm-card step


def test_live_agent_that_reads_the_calendar_before_the_card_is_caught() -> None:
    (result,) = run_live(only(["briefing-optin-offer"]), FakeBriefingSystem("reads-first"))
    assert "tool_forbidden:get_my_week" in result.failures


def test_live_seeds_the_fixtures_and_skips_cases_a_live_run_cannot_produce() -> None:
    system = FakeBriefingSystem()
    results = run_live(only(["briefing-optin-offer", "briefing-workiq-unavailable"]), system)
    assert [r.id for r in results] == ["briefing-optin-offer"]
    (fixture,) = system.seeded
    assert (fixture.owner, fixture.opted_in) == ("emp1", False)


def _driver(
    monkeypatch: pytest.MonkeyPatch, week: dict[str, Any], opted_in: bool
) -> tuple[HttpDriver, list[tuple[str, str]]]:
    monkeypatch.setenv("EVAL_TOKEN_EMP1", "t")
    calls: list[tuple[str, str]] = []
    state = {"opted_in": opted_in}

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append((request.method, request.url.path))
        body = json.loads(request.content) if request.content else {}
        path = request.url.path
        if path == "/v1/briefing/status":
            return httpx.Response(200, json={"opted_in": state["opted_in"]})
        if path == "/v1/proposals":
            return httpx.Response(200, json={"proposal_id": "p"})
        if path == "/v1/confirmations":
            assert body["type"] == "briefing"
            return httpx.Response(200, json={"confirmation_token": "tok"})
        if path == "/v1/briefing/opt-in":
            state["opted_in"] = body["enabled"]
            return httpx.Response(200, json={"opted_in": body["enabled"]})
        return httpx.Response(200, json=week)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    return HttpDriver("https://api.test", client, agent="briefing"), calls


WEEK = {
    "event_count": 2,
    "conflict_count": 0,
    "days": [
        {"events": [{"title": "A"}, {"title": "B"}], "free_blocks": [{"minutes": 90}]},
        {"events": [], "free_blocks": []},
    ],
}


def test_http_driver_sets_the_opt_in_state_through_the_confirm_card_endpoints(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    driver, calls = _driver(monkeypatch, WEEK, opted_in=False)
    driver.seed(BriefingFixture(owner="emp1", opted_in=True))
    assert ("POST", "/v1/proposals") in calls and ("POST", "/v1/briefing/opt-in") in calls
    calls.clear()
    driver.seed(BriefingFixture(owner="emp1", opted_in=True))  # already on: nothing to change
    assert ("POST", "/v1/proposals") not in calls


def test_http_driver_refuses_to_score_against_a_calendar_that_differs_from_the_fixture(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    driver, _ = _driver(monkeypatch, WEEK, opted_in=True)
    event = {"title": "A", "day": 0, "start": "09:00", "end": "10:00"}
    other = {"title": "Z", "day": 1, "start": "09:00", "end": "10:00"}
    driver.seed(
        BriefingFixture.model_validate(
            {"owner": "emp1", "events": [event, {**event, "title": "B"}]}
        )
    )
    with pytest.raises(RuntimeError, match="calendar does not match"):
        driver.seed(BriefingFixture.model_validate({"owner": "emp1", "events": [other]}))


def test_http_driver_facts_are_the_apis_own_counts(monkeypatch: pytest.MonkeyPatch) -> None:
    driver, _ = _driver(monkeypatch, WEEK, opted_in=True)
    assert driver.facts("emp1", None) == [0, 1, 2, 90]


def test_cli_offline_briefing_exit_code(capsys: Any) -> None:
    assert runner.main(["offline", "--agent", "briefing"]) == 0
    assert "evals offline: passed" in capsys.readouterr().out
