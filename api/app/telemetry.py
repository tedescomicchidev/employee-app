"""EXP-005 (CLASSIC): API call count and latency per task run. docs/experiment/metrics.md.

Content-free by construction: only the route template, status, latency and the client's
`X-Task-Run-Id` are kept; never paths with ids, query strings, bodies, tokens or user identifiers.
"""

import time
from collections import Counter
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from uuid import UUID

from fastapi import Request, Response

TASK_RUN_HEADER = "X-Task-Run-Id"


@dataclass(frozen=True)
class ApiCall:
    task_run_id: UUID
    method: str
    endpoint: str  # route template, e.g. /v1/vacation/requests/{request_id}
    status: int
    latency_ms: int


class ApiCallLog:
    """In-memory until the events container lands (ADR-009), like the event sink."""

    def __init__(self) -> None:
        self.calls: list[ApiCall] = []

    def record(self, call: ApiCall) -> None:
        self.calls.append(call)

    def count_per_task(self) -> Counter[UUID]:
        return Counter(call.task_run_id for call in self.calls)

    def latency_ms(self, task_run_id: UUID) -> int:
        return sum(call.latency_ms for call in self.calls if call.task_run_id == task_run_id)


def _run_id(request: Request) -> UUID | None:
    raw = request.headers.get(TASK_RUN_HEADER)
    try:
        return UUID(raw) if raw else None
    except ValueError:
        return None


async def record_api_call(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    run_id = _run_id(request)
    started = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    if run_id is not None and route is not None and route.path != "/v1/events":
        request.app.state.api_call_log.record(
            ApiCall(
                task_run_id=run_id,
                method=request.method,
                endpoint=route.path,
                status=response.status_code,
                latency_ms=round((time.perf_counter() - started) * 1000),
            )
        )
    return response
