"""Structured output of the comms agent: the contract with api/ and the app.

Mirror of `api/app/agents/turns.py::AgentReply`; agents/tests/test_comms_agent.py keeps them in step.
The reply never carries draft content for the confirm card: the app renders the card from
`GET /v1/proposals/{proposal_id}` so what the user confirms is what the server stored.
"""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

Reason = Literal[
    "write_without_confirmation",
    "role_not_allowed",
    "out_of_scope",
    "other_users_data",
    "untrusted_instructions",
    "unsupported_action",
]


class Source(BaseModel):
    model_config = ConfigDict(extra="forbid")

    announcement_id: UUID = Field(
        description="The id list_announcements or get_announcement returned in this turn."
    )
    title: str = Field(max_length=200, description="The title the tool returned.")


class AgentReply(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["message", "clarification", "proposal", "published", "refusal"] = Field(
        description=(
            "message: plain answer. clarification: a question for the user. "
            "proposal: propose_announcement succeeded; the app shows the confirm card. "
            "published: ONLY after publish_announcement returned status published. "
            "refusal: you decline to do what was asked (see reason)."
        )
    )
    text: str = Field(max_length=4000, description="Reply to the user, in the user's UI language.")
    proposal_id: UUID | None = Field(
        default=None,
        description="Required for kind=proposal: the id propose_announcement returned.",
    )
    reason: Reason | None = Field(
        default=None,
        description="Required for kind=refusal and only then: why you decline, one code from the list.",
    )
    sources: list[Source] = Field(
        default_factory=list,
        max_length=10,
        description=(
            "For kind=message: the announcements the answer is based on, only ones a tool "
            "returned in this turn. The api checks each one; it replaces the title."
        ),
    )
