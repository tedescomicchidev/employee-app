"""Agent eval runner.

  python runner.py offline [--agent comms]   CI gate, no Azure and no model needed
  python runner.py live    [--agent comms]   against a deployed dev API + agent (human, inner loop)

Offline proves the dataset and the scoring rules: every required @agent-eval scenario is covered,
every golden trace passes, and every recorded bad trace is caught. It does NOT run a model. The
recorded attack traces are additionally replayed against the real MCP server by
api/tests/test_agent_eval_replay.py. Live is the only mode that exercises the model and the
instructions.
"""

import argparse
import json
import os
import re
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any, Protocol

import httpx
from pydantic import ValidationError

from models import Case, CaseResult, Persona, Reply, ToolCall, Trace
from scoring import run_case, score

ROOT = Path(__file__).resolve().parent
TEST_CASES = ROOT.parent / "docs" / "product" / "test-cases.md"
THRESHOLDS = ROOT / "thresholds.json"

# @agent-eval scenarios of docs/product/test-cases.md that the comms agent must cover.
REQUIRED_SCENARIOS = [
    "Agent drafts then waits for the confirm card",
    "CEO asks agent to publish without confirming",
    'Verbal "yes" is not a confirmation',
    "Ambiguous audience prompts a question",
    "Employee outside audience cannot read or discover it",
    'Agent "what\'s new" matches the feed',
    "Injected instructions inside an announcement are not followed",
    "Injection variants",
    "Agent cannot exceed the user's role",
    "PRIV-005 Agent sees only calling user's tool data",
]
INJECTION_VARIANTS = 5  # rows of the "Injection variants" outline


def load_cases(agent: str) -> list[Case]:
    path = ROOT / agent / "dataset.jsonl"
    return [
        Case.model_validate_json(line) for line in path.read_text().splitlines() if line.strip()
    ]


def thresholds() -> dict[str, Any]:
    return json.loads(THRESHOLDS.read_text())


# ---------------------------------------------------------------- offline


def offline_report(agent: str, test_cases: str | None = None) -> dict[str, float]:
    """Each metric is a rate in [0, 1]; the caller compares it with thresholds.json."""
    try:
        cases = load_cases(agent)
    except (ValidationError, ValueError, OSError):
        return {"dataset_valid": 0.0}
    ids = [c.id for c in cases]
    valid = len(ids) == len(set(ids)) and bool(cases)

    text = test_cases if test_cases is not None else TEST_CASES.read_text()
    sources = [c.source for c in cases]
    wanted = [
        s for s in REQUIRED_SCENARIOS
        if re.search(rf"^Scenario(?: Outline)?: {re.escape(s)}\s*$", text, re.M) and s in sources
    ]  # fmt: skip
    covered = len(wanted) / len(REQUIRED_SCENARIOS)
    variants = len(
        [c for c in cases if c.id.startswith("comms-injection-") and c.id != "comms-injection-main"]
    )
    if variants < INJECTION_VARIANTS:
        covered = min(covered, variants / INJECTION_VARIANTS)

    golden = [not score(c, c.golden) for c in cases]
    caught = [
        any(f.startswith(v.fails_with) for f in score(c, v.trace))
        for c in cases for v in c.violations
    ]  # fmt: skip
    safety = [c for c in cases if c.set == "safety"]
    return {
        "dataset_valid": 1.0 if valid else 0.0,
        "required_scenarios_covered": covered,
        "golden_pass_rate": sum(golden) / len(golden) if golden else 0.0,
        "violation_catch_rate": sum(caught) / len(caught) if caught else 0.0,
        "safety_cases_with_violation": (
            sum(1 for c in safety if c.violations) / len(safety) if safety else 0.0
        ),
    }


def check_offline(report: dict[str, float], limits: dict[str, float]) -> list[str]:
    return [
        f"{name}: {report.get(name, 0.0):.2f} < {minimum:.2f}"
        for name, minimum in limits.items()
        if report.get(name, 0.0) < minimum
    ]


# ---------------------------------------------------------------- live


class Driver(Protocol):
    """What the live runner needs from a deployed system. Tokens never pass through the runner."""

    def seed(self, fixture: Any) -> None: ...
    def feed_size(self, persona: Persona) -> int: ...
    def turn(
        self, persona: Persona, messages: list[dict[str, str]], confirmation: dict[str, str] | None
    ) -> tuple[Reply, list[ToolCall]]: ...
    def confirm(self, persona: Persona, proposal_id: str) -> str: ...
    def proposal(self, persona: Persona, proposal_id: str) -> dict[str, Any] | None: ...


def run_live_case(case: Case, driver: Driver) -> Trace:
    for fixture in case.fixtures:
        driver.seed(fixture)
    before = driver.feed_size("ceo")
    messages: list[dict[str, str]] = []
    trace = Trace()
    proposal_id: str | None = None
    for turn in case.turns:
        confirmation = None
        if turn.confirm_card:
            if proposal_id is None:
                raise RuntimeError("confirm_card step without a proposal")
            token = driver.confirm(case.persona, proposal_id)
            confirmation = {"proposal_id": proposal_id, "confirmation_token": token}
            messages.append({"role": "user", "content": "Confirmed on the card."})
            trace.confirmed = True
        else:
            messages.append({"role": "user", "content": turn.user or ""})
        reply, tools = driver.turn(case.persona, list(messages), confirmation)
        messages.append({"role": "assistant", "content": reply.text})
        trace.replies.append(reply)
        trace.tools += tools
        proposal_id = reply.proposal_id or proposal_id
    if proposal_id:
        trace.proposal = driver.proposal(case.persona, proposal_id)
    visible_fixtures = sum(1 for f in case.fixtures if f.audience == "all")
    trace.created = max(0, driver.feed_size("ceo") - before - visible_fixtures)
    return trace


def run_live(cases: Sequence[Case], driver: Driver) -> list[CaseResult]:
    results = []
    for case in cases:
        try:
            results.append(run_case(case, run_live_case(case, driver)))
        except (httpx.HTTPError, RuntimeError) as exc:
            results.append(
                CaseResult(id=case.id, set=case.set, failures=[f"run_error:{type(exc).__name__}"])
            )
    return results


def check_live(results: Sequence[CaseResult], limits: dict[str, float]) -> list[str]:
    def rate(kind: str) -> float:
        sel = [r for r in results if r.set == kind]
        return sum(r.passed for r in sel) / len(sel) if sel else 0.0

    problems = []
    if len(results) < limits["min_cases"]:
        problems.append(f"cases: {len(results)} < {limits['min_cases']:.0f}")
    for kind in ("safety", "functional"):
        if rate(kind) < limits[f"{kind}_pass_rate"]:
            problems.append(
                f"{kind}_pass_rate: {rate(kind):.2f} < {limits[f'{kind}_pass_rate']:.2f}"
            )
    return problems


class HttpDriver:
    """Talks to the deployed API as each persona. Persona tokens come from the environment of the
    human who runs this (EVAL_TOKEN_CEO, EVAL_TOKEN_EMP1, ...), never from files or this repo."""

    def __init__(self, base_url: str, client: httpx.Client | None = None) -> None:
        self._base = base_url.rstrip("/")
        self._client = client or httpx.Client(timeout=120)

    @staticmethod
    def _headers(persona: str) -> dict[str, str]:
        token = os.environ.get(f"EVAL_TOKEN_{persona.upper()}")
        if not token:
            raise RuntimeError(f"EVAL_TOKEN_{persona.upper()} is not set")
        return {"Authorization": f"Bearer {token}"}

    def _call(self, method: str, path: str, persona: str, body: Any = None) -> dict[str, Any]:
        response = self._client.request(
            method, self._base + path, json=body, headers=self._headers(persona)
        )
        response.raise_for_status()
        data: dict[str, Any] = response.json()
        return data

    def seed(self, fixture: Any) -> None:
        payload = {k: getattr(fixture, k) for k in ("title", "body", "language", "audience")}
        proposal = self._call("POST", "/v1/proposals", fixture.author, {"payload": payload})
        token = self._call(
            "POST", "/v1/confirmations", fixture.author, {"proposal_id": proposal["proposal_id"]}
        )["confirmation_token"]
        self._call(
            "POST", "/v1/announcements", fixture.author,
            {"payload": payload, "confirmation_token": token},
        )  # fmt: skip

    def feed_size(self, persona: Persona) -> int:
        return len(self._call("GET", "/v1/announcements", persona)["items"])

    def turn(
        self, persona: Persona, messages: list[dict[str, str]], confirmation: dict[str, str] | None
    ) -> tuple[Reply, list[ToolCall]]:
        body: dict[str, Any] = {"messages": messages}
        if confirmation:
            body["confirmation"] = confirmation
        data = self._call("POST", "/v1/agent/comms/turns", persona, body)
        return Reply.model_validate(data["reply"]), [ToolCall(**t) for t in data["tool_calls"]]

    def confirm(self, persona: Persona, proposal_id: str) -> str:
        data = self._call("POST", "/v1/confirmations", persona, {"proposal_id": proposal_id})
        return str(data["confirmation_token"])

    def proposal(self, persona: Persona, proposal_id: str) -> dict[str, Any] | None:
        try:
            data = self._call("GET", f"/v1/proposals/{proposal_id}", persona)
        except httpx.HTTPStatusError:
            return None
        payload: dict[str, Any] = data["payload"]
        return payload


# ---------------------------------------------------------------- cli


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("mode", choices=["offline", "live"])
    parser.add_argument("--agent", default="comms")
    args = parser.parse_args(argv)
    limits = thresholds()[args.mode]

    if args.mode == "offline":
        report = offline_report(args.agent)
        for name, value in report.items():
            print(f"  {name}: {value:.2f}")
        problems = check_offline(report, limits)
    else:
        base = os.environ.get("EVAL_API_URL")
        if not base:
            print("live evals need EVAL_API_URL and EVAL_TOKEN_<PERSONA> in the environment")
            return 2
        results = run_live(load_cases(args.agent), HttpDriver(base))
        for r in results:
            print(f"  {'PASS' if r.passed else 'FAIL'} {r.id} {' '.join(r.failures)}")
        problems = check_live(results, limits)
    for problem in problems:
        print(f"evals {args.mode}: threshold not met: {problem}")
    print(f"evals {args.mode}: {'FAILED' if problems else 'passed'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
