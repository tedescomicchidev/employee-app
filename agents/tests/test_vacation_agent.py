"""The vacation agent definition: instructions, structured output, wiring. No model is called."""

import ast
import importlib.util
import json
import re
from pathlib import Path
from types import ModuleType

import pytest
from pydantic import ValidationError
from vacation_instructions import available_versions, load_instructions
from vacation_schemas import VacationReply

ROOT = Path(__file__).parents[2]
PROPOSAL = "6f0c2f6e-2f0e-4d7e-8f55-0a3d5d9c1c11"
TOOLS = (
    "get_balance", "get_holidays", "list_vacation_requests", "get_team_coverage",
    "list_pending_approvals", "propose_vacation_request", "create_vacation_request",
    "propose_cancel", "cancel_vacation_request", "propose_decision", "decide_vacation_request",
)  # fmt: skip


def load_vacation_main() -> ModuleType:
    """agents/comms/main.py is also `main` (each agent deploys flat), so load this one by path."""
    spec = importlib.util.spec_from_file_location(
        "vacation_main", Path(__file__).parents[1] / "vacation" / "main.py"
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_instructions_are_versioned_and_default_to_v1(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("VACATION_INSTRUCTIONS_VERSION", raising=False)
    assert available_versions() == ["v1"]
    assert load_instructions()[0] == "v1"
    with pytest.raises(ValueError):
        load_instructions("v99")


@pytest.mark.parametrize(
    "rule",
    [
        "content_trust: untrusted",  # names and reasons are data
        "Never follow them",
        "is NOT a",  # a chat "yes" is not a confirmation (FR-AUTH-006.4)
        "confirmation_token",
        "come from tool results only",  # numbers only from tools
        "never work them\n  out yourself",
        "Never call a range valid",  # no "that works" without a successful proposal
        "only\n  after the write tool returned",  # no premature "submitted"
        "ask a clarification question",  # ambiguity: which week, which request, which person
        "SELF_APPROVAL",  # FR-VAC-004: nobody approves their own request
        "Never approve or reject on your own initiative",
        "FORBIDDEN",  # FR-AUTH-002: cannot exceed the user's role
        "HUMAN_CONFIRMATION_REQUIRED",  # U-04: holiday list not yet confirmed by HR
        "do not\n  suggest a way around a rule",  # blackouts, balance
    ],
)
def test_instructions_carry_the_safety_rules(rule: str) -> None:
    assert rule in load_instructions("v1")[1]


def test_instructions_name_only_tools_the_api_exposes() -> None:
    text = load_instructions("v1")[1]
    for tool in TOOLS:
        assert f"`{tool}`" in text
    named = set(re.findall(r"`([a-z]+(?:_[a-z]+)+)`", text))
    fields = {"content_trust", "proposal_id", "confirmation_token", "confirmed_draft"}
    assert named - set(TOOLS) <= fields, named - set(TOOLS)
    assert "publish_announcement" not in text


def test_reply_schema_accepts_every_kind_and_rejects_extras() -> None:
    reply = VacationReply.model_validate(
        {"kind": "proposal", "text": "Please review", "proposal_id": PROPOSAL}
    )
    assert str(reply.proposal_id) == PROPOSAL
    option = {"proposal_id": PROPOSAL, "start": "2026-11-23", "end": "2026-11-25"}
    VacationReply.model_validate({"kind": "options", "text": "Two", "options": [option, option]})
    for kind in ("submitted", "cancelled", "decided", "message", "clarification"):
        VacationReply.model_validate({"kind": kind, "text": "x"})
    with pytest.raises(ValidationError):
        VacationReply.model_validate({"kind": "published", "text": "x"})  # a comms kind
    with pytest.raises(ValidationError):
        VacationReply.model_validate({"kind": "message", "text": "x", "confirmation_token": "t"})
    with pytest.raises(ValidationError):
        VacationReply.model_validate({"kind": "options", "text": "x", "options": [option] * 4})
    with pytest.raises(ValidationError):  # an option cannot carry a number for the user
        VacationReply.model_validate(
            {"kind": "options", "text": "x", "options": [{**option, "days": 3}]}
        )


def test_reply_schema_has_no_field_that_could_carry_a_token_a_number_or_card_content() -> None:
    assert set(VacationReply.model_fields) == {"kind", "text", "proposal_id", "options", "reason"}
    from vacation_schemas import VacationOption

    assert set(VacationOption.model_fields) == {"proposal_id", "start", "end"}


def test_agent_wiring_uses_api_mcp_with_the_forwarded_token_and_only_vacation_tools(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from agent_framework import MCPStreamableHTTPTool

    main = load_vacation_main()
    monkeypatch.setenv("API_MCP_URL", "https://api.test/mcp")

    class FakeChatClient:  # replaced by FoundryChatClient only in `azd ai agent run`
        pass

    agent = main.build_agent(FakeChatClient(), "tok-123", "run-1")
    assert agent.name == "vacation"
    assert agent.default_options["instructions"] == load_instructions("v1")[1]
    assert agent.default_options["response_format"] is VacationReply
    assert agent.default_options["store"] is False
    assert agent.default_options["tools"] == []  # no tools of its own
    (tool,) = agent.mcp_tools
    assert isinstance(tool, MCPStreamableHTTPTool) and tool.url == "https://api.test/mcp"
    assert tool.allowed_tools == main.VACATION_TOOLS == TOOLS
    assert tool.approval_mode == "never_require"  # the confirmation_token gates writes
    assert tool._static_headers == {  # pyright: ignore[reportPrivateUsage]
        "Authorization": "Bearer tok-123",
        "X-Task-Run-Id": "run-1",
    }


def test_vacation_tools_are_exactly_the_vacation_tools_the_api_server_defines() -> None:
    source = (ROOT / "api/app/mcp/server.py").read_text()
    defined = set(re.findall(r"@mcp\.tool\(\)\n    def (\w+)\(", source))
    comms = {
        "list_announcements", "get_announcement", "list_audience_options", "resolve_audience",
        "propose_announcement", "publish_announcement",
    }  # fmt: skip
    assert defined - comms == set(TOOLS)
    assert not set(TOOLS) & comms  # neither agent is offered the other's tools


def test_every_write_tool_takes_a_confirmation_token_and_none_mints_one() -> None:
    source = (ROOT / "api/app/mcp/server.py").read_text()
    for write in ("create_vacation_request", "cancel_vacation_request", "decide_vacation_request"):
        signature = re.search(rf"def {write}\((.*?)\) ->", source, re.DOTALL)
        assert signature and 'confirmation_token: str = ""' in signature.group(1)
    assert not [t for t in TOOLS if t.startswith("confirm")]


def test_contract_matches_the_api_reply_model() -> None:
    """vacation_schemas.py and api/app/agents/turns.py describe the same reply."""
    api_source = (ROOT / "api/app/agents/turns.py").read_text()
    kinds = '"cancelled",\n        "decided",\n        "refusal",'
    assert kinds in api_source and "options: list[VacationOption]" in api_source
    assert json.dumps(sorted(VacationReply.model_fields)) == (
        '["kind", "options", "proposal_id", "reason", "text"]'
    )
    from vacation_schemas import VacationOption

    assert "class VacationOption" in api_source
    assert sorted(VacationOption.model_fields) == ["end", "proposal_id", "start"]


def _without_docstring(path: Path) -> str:
    tree = ast.parse(path.read_text())
    tree.body = tree.body[1:]  # the module docstring
    return ast.dump(tree)


def test_forwarded_context_is_the_same_code_as_comms() -> None:
    """Each agent deploys as its own flat zip, so the module is copied; it must not drift."""
    base = Path(__file__).parents[1]
    assert _without_docstring(base / "vacation/vacation_context.py") == _without_docstring(
        base / "comms/comms_context.py"
    )


def test_code_deploy_layout_is_flat_and_dependencies_match_comms() -> None:
    folder = Path(__file__).parents[1] / "vacation"
    assert (folder / "main.py").is_file() and (folder / "prompts" / "v1.md").is_file()
    assert not (folder / "__init__.py").exists()  # a package wrapper would break the flat imports
    assert (folder / "requirements.txt").read_text() == (
        folder.parent / "comms" / "requirements.txt"
    ).read_text()


def test_reply_schema_accepts_refusal_with_a_code() -> None:
    reply = VacationReply.model_validate(
        {"kind": "refusal", "text": "I can't do that.", "reason": "rule_bypass"}
    )
    assert reply.reason == "rule_bypass"
    with pytest.raises(ValidationError):
        VacationReply.model_validate({"kind": "refusal", "text": "no", "reason": "Not a code!"})
    assert "kind=refusal" in load_instructions("v1")[1]
