"""Structured output of the briefing agent: the contract with api/ and the app.

Mirror of `api/app/agents/turns.py::BriefingReply`; agents/tests/test_briefing_agent.py keeps them in
step. The reply carries an id and a count only. The opt-in card is rendered by the app from
`GET /v1/proposals/{proposal_id}`, and the full week is the app's Briefing screen, so what the user
confirms and what the list shows come from api/, never from text the model wrote.
"""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

Reason = Literal[
    "write_without_confirmation",
    "other_users_data",
    "out_of_scope",
    "untrusted_instructions",
    "unsupported_action",
]


class BriefingReply(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["message", "clarification", "proposal", "opted_in", "summary", "refusal"] = Field(
        description=(
            "message: plain answer. clarification: a question for the user. "
            "proposal: propose_briefing_optin succeeded; the app shows the confirm card. "
            "opted_in: ONLY after set_briefing_optin returned status ok. "
            "summary: your week, ONLY after get_my_week succeeded in this turn. "
            "refusal: you decline to do what was asked (see reason)."
        )
    )
    text: str = Field(max_length=4000, description="Reply to the user, in the user's UI language.")
    proposal_id: UUID | None = Field(
        default=None,
        description="Required for kind=proposal: the id propose_briefing_optin returned.",
    )
    omitted_count: int | None = Field(
        default=None,
        ge=0,
        le=1000,
        description=(
            "For kind=summary: how many events from get_my_week you left out of `text`; 0 if the "
            "text covers every one. The app links the full list."
        ),
    )
    reason: Reason | None = Field(
        default=None,
        description="Required for kind=refusal and only then: why you decline, one code from the list.",
    )
