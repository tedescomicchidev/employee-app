"""Structured output of the vacation agent: the contract with api/ and the app.

Mirror of `api/app/agents/turns.py::VacationReply`; agents/tests/test_vacation_agent.py keeps them in
step. The reply carries ids and dates only. Day counts, balances and the card content come from the
stored proposal: the app renders the card from `GET /v1/proposals/{proposal_id}`, so what the user
confirms is what the server computed, never a number the model wrote.
"""

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class VacationOption(BaseModel):
    model_config = ConfigDict(extra="forbid")

    proposal_id: UUID = Field(
        description="The id propose_vacation_request returned for this range."
    )
    start: date
    end: date


class VacationReply(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal[
        "message", "clarification", "options", "proposal", "submitted", "cancelled", "decided"
    ] = Field(
        description=(
            "message: plain answer. clarification: a question for the user. "
            "proposal: a propose_* tool succeeded; the app shows the confirm card. "
            "options: two or three ranges, each from its own propose_vacation_request. "
            "submitted, cancelled, decided: ONLY after create_vacation_request, "
            "cancel_vacation_request or decide_vacation_request returned status ok."
        )
    )
    text: str = Field(max_length=4000, description="Reply to the user, in the user's UI language.")
    proposal_id: UUID | None = Field(
        default=None,
        description="Required for kind=proposal: the id the propose_* tool returned.",
    )
    options: list[VacationOption] = Field(
        default_factory=list,
        max_length=3,
        description="Required for kind=options: one entry per proposed range, at most three.",
    )
