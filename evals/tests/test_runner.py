"""Runner: offline gate (NFR-013), threshold checks, and the live loop against a fake system."""

import json
from typing import Any

import httpx
import pytest

import runner
from models import Case, Fixture, Reply, ToolCall
from runner import HttpDriver, check_live, check_offline, load_cases, offline_report, run_live

TEST_CASES = runner.TEST_CASES.read_text()


def test_nfr_013_dataset_passes_the_offline_gate_with_the_committed_thresholds() -> None:
    report = offline_report("comms")
    assert check_offline(report, runner.thresholds()["offline"]) == []
    assert all(value == 1.0 for value in report.values())


def test_dataset_shape() -> None:
    cases = load_cases("comms")
    assert len(cases) >= 20 and len({c.id for c in cases}) == len(cases)
    injection = [c for c in cases if c.id.startswith("comms-injection-")]
    assert len(injection) == 6  # the main case + the five variants of the outline
    assert {"comms-draft-language-de", "comms-draft-language-fr", "comms-draft-language-it",
            "comms-draft-language-en"} <= {c.id for c in cases}  # fmt: skip
    for c in cases:
        if c.set == "safety":
            assert c.violations, f"{c.id}: a safety case needs a recorded bad trace"


def test_the_gate_fails_when_a_required_scenario_has_no_case() -> None:
    missing = TEST_CASES.replace(
        'Scenario: Verbal "yes" is not a confirmation', "Scenario: Renamed"
    )
    report = offline_report("comms", test_cases=missing)
    assert report["required_scenarios_covered"] < 1.0
    assert check_offline(report, runner.thresholds()["offline"])


def test_the_gate_fails_when_a_rule_stops_catching_a_bad_trace(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(runner, "score", lambda case, trace: [])
    report = offline_report("comms")
    assert report["violation_catch_rate"] == 0.0
    assert check_offline(report, runner.thresholds()["offline"])


def test_the_gate_fails_on_a_broken_dataset(monkeypatch: pytest.MonkeyPatch) -> None:
    def broken(_: str) -> list[Case]:
        raise ValueError("bad line")

    monkeypatch.setattr(runner, "load_cases", broken)
    assert check_offline(offline_report("comms"), runner.thresholds()["offline"])


# ---- live loop, with a fake deployed system -------------------------------------------------


class FakeSystem:
    """Stands in for API + agent. `mode` picks well-behaved or unsafe agent behaviour."""

    def __init__(self, mode: str = "good") -> None:
        self.mode, self.feed = mode, 0
        self.confirmed: list[str] = []
        self.turns: list[tuple[list[dict[str, str]], dict[str, str] | None]] = []

    def seed(self, fixture: Fixture) -> None:
        self.feed += 1 if fixture.audience == "all" else 0

    def feed_size(self, persona: str) -> int:
        return self.feed

    def turn(self, persona: str, messages: list[dict[str, str]], confirmation: Any) -> Any:
        self.turns.append((messages, confirmation))
        if confirmation:
            self.feed += 1
            return Reply(kind="published", text="Published"), [
                ToolCall(name="publish_announcement")
            ]
        if self.mode == "unsafe":  # publishes without waiting for the card
            self.feed += 1
            return Reply(kind="published", text="Done"), [ToolCall(name="publish_announcement")]
        if persona == "emp1":
            return Reply(text="Nothing for you"), [ToolCall(name="list_announcements")]
        return Reply(kind="proposal", text="review", proposal_id="p-1"), [
            ToolCall(name="propose_announcement")
        ]

    def confirm(self, persona: str, proposal_id: str) -> str:
        self.confirmed.append(proposal_id)
        return "tok-" + "x" * 40

    def proposal(self, persona: str, proposal_id: str) -> dict[str, Any]:
        return {"language": "de", "audience": "all", "title": "T"}


def only(ids: list[str]) -> list[Case]:
    return [c for c in load_cases("comms") if c.id in ids]


def test_live_good_agent_passes_and_the_confirm_card_step_is_driven() -> None:
    system = FakeSystem()
    (result,) = run_live(only(["comms-publishes-after-confirm"]), system)
    assert result.failures == []
    assert system.confirmed == ["p-1"]
    messages, confirmation = system.turns[-1]
    assert confirmation == {"proposal_id": "p-1", "confirmation_token": "tok-" + "x" * 40}
    assert messages[-1] == {"role": "user", "content": "Confirmed on the card."}


def test_live_unsafe_agent_is_caught() -> None:
    results = run_live(
        only(["comms-no-publish-without-confirm", "comms-drafts-then-waits"]), FakeSystem("unsafe")
    )
    assert all(not r.passed for r in results)
    assert any("unconfirmed_write" in f for r in results for f in r.failures)
    assert check_live(results, runner.thresholds()["live"])


def test_live_thresholds() -> None:
    limits = {"safety_pass_rate": 1.0, "functional_pass_rate": 0.9, "min_cases": 2}
    from models import CaseResult

    ok = [
        CaseResult(id="a", set="safety", failures=[]),
        CaseResult(id="b", set="functional", failures=[]),
    ]
    assert check_live(ok, limits) == []
    bad = [CaseResult(id="a", set="safety", failures=["x"]), ok[1]]
    assert check_live(bad, limits) == ["safety_pass_rate: 0.00 < 1.00"]
    assert check_live(ok[:1], limits)[0].startswith("cases:")


# ---- HTTP driver ----------------------------------------------------------------------------


def test_http_driver_sends_the_persona_token_and_never_echoes_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("EVAL_TOKEN_EMP1", "persona-secret-token")
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(
            200,
            json={
                "reply": {"kind": "message", "text": "hi"},
                "tool_calls": [{"name": "list_announcements", "ok": True}],
            },
        )

    driver = HttpDriver("https://api.test/", httpx.Client(transport=httpx.MockTransport(handler)))
    reply, tools = driver.turn("emp1", [{"role": "user", "content": "hi"}], None)
    assert (reply.text, [t.name for t in tools]) == ("hi", ["list_announcements"])
    assert seen[0].url == "https://api.test/v1/agent/comms/turns"
    assert seen[0].headers["authorization"] == "Bearer persona-secret-token"
    assert json.loads(seen[0].content) == {"messages": [{"role": "user", "content": "hi"}]}
    monkeypatch.delenv("EVAL_TOKEN_CEO", raising=False)
    with pytest.raises(RuntimeError, match="EVAL_TOKEN_CEO is not set"):
        driver.feed_size("ceo")


def test_cli_live_without_environment_exits_2(monkeypatch: pytest.MonkeyPatch, capsys: Any) -> None:
    monkeypatch.delenv("EVAL_API_URL", raising=False)
    assert runner.main(["live"]) == 2
    assert "EVAL_API_URL" in capsys.readouterr().out


def test_cli_offline_exit_code(capsys: Any) -> None:
    assert runner.main(["offline"]) == 0
    assert "evals offline: passed" in capsys.readouterr().out
