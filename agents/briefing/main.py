"""Briefing hosted agent (Microsoft Agent Framework, Responses protocol).

Docs: learn.microsoft.com/agent-framework/hosting/foundry-hosted-agent (ResponsesHostServer),
learn.microsoft.com/azure/foundry/agents/how-to/use-on-behalf-of-flow (x-client-* forwarding),
learn.microsoft.com/azure/foundry/agents/how-to/deploy-hosted-agent-code (source-code deploy).

Deployed as source code (azd codeConfiguration, entry point `main.py`): the folder is zipped flat, so
modules sit next to this file and import each other by plain name.

Tools: the agent calls api/'s MCP server (`API_MCP_URL`) directly, as the user, with the OBO token that api/
forwards on each turn. A Foundry toolbox connection cannot carry that identity (UserEntraToken needs a user
token for Foundry, which api/ deliberately does not hold, ADR-002), so there is no toolbox. The role checks,
the confirmation token and the audit trail live in api/ (ADR-005). Only the four briefing tools are exposed.

Work IQ: this agent never calls Work IQ. api/ does, on behalf of the user (ADR-004), so there is no Work IQ
connection, no toolbox and no secret here.
"""

import os
from typing import Any

from briefing_context import ForwardedContextMiddleware, task_run_id, tools_token
from briefing_instructions import load_instructions
from briefing_schemas import BriefingReply

BRIEFING_TOOLS = (
    "get_briefing_status",
    "get_my_week",
    "propose_briefing_optin",
    "set_briefing_optin",
)


def mcp_headers(token: str, run_id: str | None) -> dict[str, str]:
    headers = {"Authorization": f"Bearer {token}"}
    if run_id:
        headers["X-Task-Run-Id"] = run_id  # joins api/'s MCP audit to the experiment task run
    return headers


def build_agent(chat_client: Any, token: str, run_id: str | None = None) -> Any:
    """One agent per request: its MCP tool carries this request's user token and nothing else."""
    from agent_framework import Agent, MCPStreamableHTTPTool

    _, instructions = load_instructions()
    tools = MCPStreamableHTTPTool(
        name="employee-api",
        url=os.environ["API_MCP_URL"],
        static_headers=mcp_headers(token, run_id),
        allowed_tools=BRIEFING_TOOLS,
        approval_mode="never_require",  # writes are gated by the confirmation_token, not a prompt
        load_prompts=False,
    )
    return Agent(
        client=chat_client,
        name="briefing",
        instructions=instructions,
        tools=tools,
        # store=false: the app keeps the history (PRIV-004). The reply is the structured contract.
        default_options={"store": False, "response_format": BriefingReply},
    )


def create_server(chat_client: Any) -> Any:
    from agent_framework_foundry_hosting import ResponsesHostServer

    def agent_factory() -> Any:
        return build_agent(chat_client, tools_token(), task_run_id())

    server = ResponsesHostServer(agent_factory)
    server.add_middleware(ForwardedContextMiddleware)
    return server


def main() -> None:
    from agent_framework.foundry import FoundryChatClient
    from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

    hosted = bool(os.environ.get("FOUNDRY_AGENT_INSTANCE_CLIENT_ID"))
    credential = (
        ManagedIdentityCredential(client_id=os.environ["FOUNDRY_AGENT_INSTANCE_CLIENT_ID"])
        if hosted
        else DefaultAzureCredential()
    )
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ.get("FOUNDRY_MODEL") or os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )
    create_server(client).run()


if __name__ == "__main__":
    main()
