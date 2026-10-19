"""FR-AUTH-003: one content-free audit record per tool call, plus EXP-005 safety counters.

A record holds user id, tool name, outcome and correlation id; never arguments, announcement text
or tokens (NFR-012). In memory until the events container lands (ADR-009), like the event sink.
"""

import logging
from collections import Counter, deque
from dataclasses import dataclass
from datetime import UTC, datetime

MAX_RECORDS = 50_000

log = logging.getLogger(__name__)

# Outcomes that count as a blocked attempt (docs/experiment/metrics.md `safety_counter`).
UNCONFIRMED_WRITE_BLOCKED = "unconfirmed_write_blocked"
CROSS_USER_BLOCK = "cross_user_block"
_COUNTER_FOR_OUTCOME = {
    "confirmation_required": UNCONFIRMED_WRITE_BLOCKED,
    "invalid_confirmation": UNCONFIRMED_WRITE_BLOCKED,
    "forbidden": CROSS_USER_BLOCK,
    "not_found": CROSS_USER_BLOCK,
}


@dataclass(frozen=True)
class AuditRecord:
    user_id: str
    tool: str
    outcome: str  # "ok" or the lower-cased ApiError code
    correlation_id: str
    ts: datetime


class McpAuditLog:
    def __init__(self, limit: int = MAX_RECORDS) -> None:
        self.records: deque[AuditRecord] = deque(maxlen=limit)
        self.safety_counters: Counter[tuple[str, str]] = Counter()  # (correlation_id, counter)

    def record(self, user_id: str, tool: str, outcome: str, correlation_id: str) -> None:
        self.records.append(AuditRecord(user_id, tool, outcome, correlation_id, datetime.now(UTC)))
        # The durable trail until the events container lands: one structured line, no content.
        log.info(
            "mcp_audit user=%s tool=%s outcome=%s correlation=%s",
            user_id,
            tool,
            outcome,
            correlation_id,
        )
        counter = _COUNTER_FOR_OUTCOME.get(outcome)
        if counter:
            self.safety_counters[(correlation_id, counter)] += 1
