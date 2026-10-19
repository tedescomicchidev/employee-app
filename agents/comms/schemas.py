"""Structured output of the comms agent: the contract with api/ and the app.

Mirror of `api/app/agents/turns.py::AgentReply`; tests/test_comms_contract.py keeps them in step.
The reply never carries draft content for the confirm card: the app renders the card from
`GET /v1/proposals/{proposal_id}` so what the user confirms is what the server stored.
"""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class AgentReply(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["message", "clarification", "proposal", "published"] = Field(
        description=(
            "message: plain answer. clarification: a question for the user. "
            "proposal: propose_announcement succeeded; the app shows the confirm card. "
            "published: ONLY after publish_announcement returned status published."
        )
    )
    text: str = Field(max_length=4000, description="Reply to the user, in the user's UI language.")
    proposal_id: UUID | None = Field(
        default=None,
        description="Required for kind=proposal: the id propose_announcement returned.",
    )
