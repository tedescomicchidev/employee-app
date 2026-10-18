from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, Field

from app.auth.principal import Principal, current_principal

router = APIRouter(prefix="/v1")

TaskId = Literal[
    "T-ANN-PUB", "T-ANN-READ", "T-VAC-BAL", "T-VAC-REQ", "T-VAC-REJ", "T-VAC-APR", "T-VAC-COV",
    "T-BRF-VIEW",
]  # fmt: skip


class ExperimentEvent(BaseModel):
    """docs/experiment/metrics.md. Unknown fields are rejected; no content fields exist."""

    model_config = ConfigDict(extra="forbid")

    event: Literal[
        "task_started", "task_completed", "task_abandoned", "task_error",
        "confirm_shown", "confirm_accepted", "confirm_rejected", "agent_turn",
        "satisfaction", "session_comparison", "withdrawal",
    ]  # fmt: skip
    participant_id: UUID
    session_id: UUID
    task_run_id: UUID
    task_id: TaskId
    feature: Literal["ann", "vac", "brf"]
    mode: Literal["classic", "agent"]
    order_index: int = Field(ge=0)
    app_version: str = Field(max_length=32)
    os_version: str = Field(max_length=32)
    locale: str = Field(max_length=16)
    ts: datetime
    elapsed_ms: int | None = Field(default=None, ge=0)
    tap_count: int | None = Field(default=None, ge=0)
    message_count: int | None = Field(default=None, ge=0)
    outcome_valid: bool | None = None
    last_state: str | None = Field(default=None, max_length=32)
    code: str | None = Field(default=None, max_length=48)
    recovered: bool | None = None
    action: Literal["publish", "request", "cancel", "decide", "opt_in"] | None = None
    latency_ms: int | None = Field(default=None, ge=0)
    score: int | None = Field(default=None, ge=1, le=5)


class EventBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    events: list[ExperimentEvent] = Field(max_length=200)


@router.post("/events", status_code=202)
def ingest_events(
    batch: EventBatch,
    request: Request,
    _: Annotated[Principal, Depends(current_principal)],
) -> dict[str, int]:
    request.app.state.event_sink.extend(batch.events)
    return {"accepted": len(batch.events)}
