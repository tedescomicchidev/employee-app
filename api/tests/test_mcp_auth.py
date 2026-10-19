"""FR-AUTH-003 (agent acts as the calling user) and ADR-002 audience separation."""

from collections.abc import Iterator
from typing import Any

import pytest

from tests.conftest import TOOLS_SETTINGS
from tests.mcp_harness import CEO, EMP1, McpEnv, running, sign

RUN_ID = "5d1c6c1e-0f50-4a6e-9c5b-1f2f1a7d9b10"


@pytest.fixture
def env(private_key: Any) -> Iterator[McpEnv]:
    with running(private_key) as e:
        yield e


def test_fr_auth_003_missing_or_invalid_token_gets_no_data(env: McpEnv) -> None:
    assert env.rpc(None, "tools/list").status_code == 401
    assert env.rpc("not-a-jwt", "tools/list").status_code == 401


def test_fr_auth_003_app_only_token_is_rejected(env: McpEnv) -> None:
    """Managed identity / client credentials: audience is right, but no delegated user scope."""
    app_only = sign(env.key, TOOLS_SETTINGS.tools_audience, None, CEO, ["Communicator"])
    response = env.rpc(app_only, "tools/call", {"name": "list_announcements", "arguments": {}})
    assert response.status_code == 401 and "announcements" not in response.text
    assert len(env.app.state.mcp_audit.records) == 0  # rejected before any tool ran


def test_adr_002_audiences_are_not_interchangeable(env: McpEnv) -> None:
    assert env.rpc(env.user_token(CEO, "Communicator"), "tools/list").status_code == 401
    tools = {"Authorization": f"Bearer {env.tools_token(CEO, 'Communicator')}"}
    assert env.client.get("/v1/announcements", headers=tools).status_code == 401  # type: ignore[union-attr]
    assert env.client.get("/v1/me", headers=tools).status_code == 401  # type: ignore[union-attr]
    wrong_scope = env.tools_token(CEO, "Communicator", scp="access_as_user")
    assert env.rpc(wrong_scope, "tools/list").status_code == 401


def test_fr_auth_003_audit_record_has_user_tool_outcome_correlation_and_no_content(
    env: McpEnv,
) -> None:
    secret_body = "Quarterly numbers are confidential"
    token = env.tools_token(CEO, "Communicator", "Employee")
    draft = {"title": "T", "body": secret_body, "language": "en", "audience": "all"}
    env.call(token, "propose_announcement", draft, **{"X-Task-Run-Id": RUN_ID})
    env.call(env.tools_token(EMP1, "Employee"), "propose_announcement", draft)
    ok, denied = list(env.app.state.mcp_audit.records)
    assert (ok.user_id, ok.tool, ok.outcome, ok.correlation_id) == (
        CEO, "propose_announcement", "ok", RUN_ID,
    )  # fmt: skip
    assert (denied.user_id, denied.outcome) == (EMP1, "forbidden") and denied.correlation_id
    assert secret_body not in repr(list(env.app.state.mcp_audit.records))
    assert env.app.state.mcp_audit.safety_counters[(denied.correlation_id, "cross_user_block")] == 1


def test_fr_auth_003_audit_line_is_logged_without_content(env: McpEnv, caplog: Any) -> None:
    token = env.tools_token(CEO, "Communicator", "Employee")
    draft = {"title": "T", "body": "Confidential body text", "language": "en", "audience": "all"}
    with caplog.at_level("INFO", logger="app.mcp.audit"):
        env.call(token, "propose_announcement", draft, **{"X-Task-Run-Id": RUN_ID})
    lines = [r.getMessage() for r in caplog.records if r.name == "app.mcp.audit"]
    assert lines == [
        f"mcp_audit user={CEO} tool=propose_announcement outcome=ok correlation={RUN_ID}"
    ]
    assert "Confidential" not in caplog.text and token not in caplog.text


def test_safety_counter_counts_blocked_unconfirmed_write(env: McpEnv) -> None:
    token = env.tools_token(CEO, "Communicator", "Employee")
    draft = {"title": "T", "body": "B", "language": "en", "audience": "all"}
    env.call(
        token,
        "publish_announcement",
        {"confirmation_token": "", **draft},
        **{"X-Task-Run-Id": RUN_ID},
    )
    assert env.app.state.mcp_audit.safety_counters[(RUN_ID, "unconfirmed_write_blocked")] == 1


def test_tool_arguments_never_name_a_user(env: McpEnv) -> None:
    tools = env.rpc(env.tools_token(CEO, "Communicator"), "tools/list").json()["result"]["tools"]
    for tool in tools:
        assert not {"oid", "user", "user_id", "employee"} & set(tool["inputSchema"]["properties"])


def test_fr_auth_003_rejected_calls_are_audited_and_never_echo_the_input(env: McpEnv) -> None:
    token = env.tools_token(CEO, "Communicator", "Employee")
    secret = "Confidential fragment"
    wrong_type = env.call(token, "propose_announcement", {"title": ["a"], "body": secret})
    unknown = env.call(token, "create_vacation_request", {"days": 25})
    assert wrong_type[0] and "INVALID_ARGUMENTS" in wrong_type[1] and secret not in wrong_type[1]
    assert unknown[0] and "UNKNOWN_TOOL" in unknown[1]
    rows = [(r.user_id, r.tool, r.outcome) for r in env.app.state.mcp_audit.records]
    assert rows == [
        (CEO, "propose_announcement", "invalid_arguments"),
        (CEO, "(unknown)", "unknown_tool"),
    ]


def test_nfr_008_publish_without_a_token_argument_is_confirmation_required_like_rest(
    env: McpEnv,
) -> None:
    token = env.tools_token(CEO, "Communicator", "Employee")
    args = {"title": "T", "body": "B", "language": "en", "audience": "all"}
    is_error, text = env.call(token, "publish_announcement", args)  # no confirmation_token at all
    assert is_error and "CONFIRMATION_REQUIRED" in text
    (record,) = env.app.state.mcp_audit.records
    assert record.outcome == "confirmation_required"


def test_mcp_accepts_post_only(env: McpEnv) -> None:
    """A GET would open a stream and hold a connection; nothing here is served over one."""
    headers = {"Authorization": f"Bearer {env.tools_token(CEO, 'Communicator')}"}
    for method in ("GET", "DELETE", "PUT", "PATCH"):
        response = env.client.request(method, "/mcp", headers=headers)  # type: ignore[union-attr]
        assert response.status_code == 405 and response.headers["allow"] == "POST"
    assert env.client.get("/mcp").status_code == 405  # type: ignore[union-attr]


def test_fr_auth_003_concurrent_users_keep_their_own_identity(env: McpEnv) -> None:
    from concurrent.futures import ThreadPoolExecutor

    tokens = {
        CEO: env.tools_token(CEO, "Communicator", "Employee"),
        EMP1: env.tools_token(EMP1, "Employee"),
    }

    def call(oid: str) -> None:
        for _ in range(10):
            env.call(tokens[oid], "list_announcements")

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(call, [CEO, EMP1, CEO, EMP1]))
    records = list(env.app.state.mcp_audit.records)
    assert len(records) == 40 and {r.outcome for r in records} == {"ok"}
    assert sum(r.user_id == CEO for r in records) == 20
    assert sum(r.user_id == EMP1 for r in records) == 20
