"""Comms hosted agent (Microsoft Agent Framework, Responses protocol, Foundry toolbox tools).

Deployed as source code (azd codeConfiguration, entry point `python main.py`): the folder is zipped flat,
so modules sit next to this file and import each other by plain name.

Docs: learn.microsoft.com/agent-framework/hosting/foundry-hosted-agent (ResponsesHostServer),
learn.microsoft.com/agent-framework/integrations/by-component/tools/foundry-toolbox (FoundryToolbox),
learn.microsoft.com/azure/foundry/agents/how-to/tools/use-toolbox-hosted-agent.

The agent has no tools of its own: every tool comes from the `core-tools` toolbox, which fronts the
api/ MCP server. The role checks, the confirmation token and the audit trail live in api/ (ADR-005).
"""

import os
from typing import Any

from comms_instructions import load_instructions
from comms_schemas import AgentReply

TOOLBOX_NAME_DEFAULT = "core-tools"


def build_agent(credential: Any, chat_client: Any | None = None) -> Any:
    """`chat_client` is injectable so tests never call a model."""
    from agent_framework import Agent
    from agent_framework.foundry import FoundryChatClient, FoundryToolbox

    _, instructions = load_instructions()
    # The toolbox endpoint is built from FOUNDRY_PROJECT_ENDPOINT + TOOLBOX_NAME (or TOOLBOX_ENDPOINT).
    os.environ.setdefault("TOOLBOX_NAME", TOOLBOX_NAME_DEFAULT)
    toolbox = FoundryToolbox(credential)
    client = chat_client or FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ.get("FOUNDRY_MODEL") or os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )
    return Agent(
        client=client,
        name="comms",
        instructions=instructions,
        tools=toolbox,
        # store=false: the app keeps the history (PRIV-004). The reply is the structured contract.
        default_options={"store": False, "response_format": AgentReply},
    )


def main() -> None:
    from agent_framework_foundry_hosting import ResponsesHostServer
    from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

    hosted = bool(os.environ.get("FOUNDRY_AGENT_INSTANCE_CLIENT_ID"))
    credential = (
        ManagedIdentityCredential(client_id=os.environ["FOUNDRY_AGENT_INSTANCE_CLIENT_ID"])
        if hosted
        else DefaultAzureCredential()
    )
    ResponsesHostServer(build_agent(credential)).run()


if __name__ == "__main__":
    main()
