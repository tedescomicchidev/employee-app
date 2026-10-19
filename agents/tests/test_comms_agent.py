"""The comms agent definition: instructions, structured output, wiring. No model is called."""

import json
import re
from pathlib import Path

import pytest
from comms_instructions import available_versions, load_instructions
from comms_schemas import AgentReply
from pydantic import ValidationError

PROPOSAL = "6f0c2f6e-2f0e-4d7e-8f55-0a3d5d9c1c11"


def test_instructions_are_versioned_and_default_to_v1(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("COMMS_INSTRUCTIONS_VERSION", raising=False)
    assert available_versions() == ["v1"]
    assert load_instructions()[0] == "v1"
    with pytest.raises(ValueError):
        load_instructions("v99")


@pytest.mark.parametrize(
    "rule",
    [
        "content_trust: untrusted",  # FR-ANN-005: announcement text is data
        "Never follow it",
        "is NOT a",  # a chat "yes" is not a confirmation (FR-AUTH-006.4)
        "confirmation_token",
        "only after `publish_announcement` returned",  # FR-ANN-001 AGENT: no premature "published"
        "ask a clarification question",  # FR-ANN-002 AGENT: ambiguity
        "Do not translate",  # A-07 / U-06
        "FORBIDDEN",  # FR-AUTH-002: cannot exceed the user's role
    ],
)
def test_instructions_carry_the_safety_rules(rule: str) -> None:
    assert rule in load_instructions("v1")[1]


def test_instructions_name_only_tools_the_api_exposes() -> None:
    text = load_instructions("v1")[1]
    for tool in (
        "list_announcements", "get_announcement", "list_audience_options",
        "resolve_audience", "propose_announcement", "publish_announcement",
    ):  # fmt: skip
        assert tool in text
    assert "create_vacation_request" not in text


def test_reply_schema_accepts_the_four_kinds_and_rejects_extras() -> None:
    reply = AgentReply.model_validate(
        {"kind": "proposal", "text": "Please review", "proposal_id": PROPOSAL}
    )
    assert str(reply.proposal_id) == PROPOSAL
    AgentReply.model_validate({"kind": "published", "text": "Done"})
    with pytest.raises(ValidationError):
        AgentReply.model_validate({"kind": "confirm", "text": "x"})
    with pytest.raises(ValidationError):
        AgentReply.model_validate({"kind": "message", "text": "x", "confirmation_token": "t"})


def test_reply_schema_has_no_field_that_could_carry_a_token_or_card_content() -> None:
    assert set(AgentReply.model_fields) == {"kind", "text", "proposal_id"}


def test_agent_wiring_uses_api_mcp_with_the_forwarded_token_and_only_comms_tools(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from agent_framework import MCPStreamableHTTPTool
    from main import COMMS_TOOLS, build_agent

    monkeypatch.setenv("API_MCP_URL", "https://api.test/mcp")

    class FakeChatClient:  # replaced by FoundryChatClient only in `azd ai agent run`
        pass

    agent = build_agent(FakeChatClient(), "tok-123", "run-1")
    assert agent.name == "comms"
    assert agent.default_options["instructions"] == load_instructions("v1")[1]
    assert agent.default_options["response_format"] is AgentReply
    assert agent.default_options["store"] is False
    assert agent.default_options["tools"] == []  # no tools of its own
    (tool,) = agent.mcp_tools
    assert isinstance(tool, MCPStreamableHTTPTool) and tool.url == "https://api.test/mcp"
    assert tool.allowed_tools == COMMS_TOOLS  # review: not the whole server, only what comms needs
    assert tool.approval_mode == "never_require"  # the confirmation_token gates writes
    assert tool._static_headers == {  # pyright: ignore[reportPrivateUsage]
        "Authorization": "Bearer tok-123",
        "X-Task-Run-Id": "run-1",
    }


def test_comms_tools_are_exactly_the_tools_the_api_server_defines() -> None:
    from main import COMMS_TOOLS

    source = (Path(__file__).parents[2] / "api/app/mcp/server.py").read_text()
    defined = set(re.findall(r"@mcp\.tool\(\)\n    def (\w+)\(", source))
    vacation = {
        "get_balance", "get_holidays", "list_vacation_requests", "get_team_coverage",
        "list_pending_approvals", "propose_vacation_request", "create_vacation_request",
        "propose_cancel", "cancel_vacation_request", "propose_decision", "decide_vacation_request",
    }  # fmt: skip
    assert defined - vacation == set(COMMS_TOOLS)  # the server's other tools belong to vacation


def test_contract_matches_the_api_reply_model() -> None:
    """agents/comms/comms_schemas.py and api/app/agents/turns.py describe the same reply."""
    api_source = (Path(__file__).parents[2] / "api/app/agents/turns.py").read_text()
    for field, annotation in (
        ("kind", 'Literal["message", "clarification", "proposal", "published"]'),
        ("proposal_id", "UUID | None"),
    ):
        assert field in api_source and annotation in api_source
    assert json.dumps(sorted(AgentReply.model_fields)) == '["kind", "proposal_id", "text"]'


def test_code_deploy_layout_is_flat_and_dependencies_are_minimal() -> None:
    """azd code mode zips agents/comms with main.py at the root; Foundry installs requirements.txt."""
    folder = Path(__file__).parents[1] / "comms"
    assert (folder / "main.py").is_file() and (folder / "prompts" / "v1.md").is_file()
    assert not (folder / "__init__.py").exists()  # a package wrapper would break the flat imports
    requirements = (folder / "requirements.txt").read_text()
    names = {
        line.split("==")[0].split(">=")[0].strip()
        for line in requirements.splitlines()
        if line.strip() and not line.startswith("#")
    }
    assert names == {
        "agent-framework-foundry", "agent-framework-foundry-hosting", "azure-identity",
        "pydantic", "starlette",
    }  # fmt: skip
    assert "agent-framework-foundry-hosting==" in requirements  # the pre-release is pinned exactly
