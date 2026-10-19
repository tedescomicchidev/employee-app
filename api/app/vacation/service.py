import hmac
import logging
import secrets
import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.auth.errors import (
    FieldError,
    canton_missing,
    confirmation_required,
    forbidden,
    invalid_confirmation,
    invalid_state,
    no_approver,
    not_found,
    not_provisioned,
    rule_violation,
    self_approval,
)
from app.auth.principal import Principal
from app.repositories import (
    ConfirmationStore,
    ConfirmationToken,
    Directory,
    Employee,
    Proposal,
)
from app.vacation import rules
from app.vacation.models import (
    ACTION_CANCEL,
    ACTION_DECIDE,
    ACTION_REQUEST,
    BLACKOUT,
    INSUFFICIENT_BALANCE,
    MAX_REASON,
    OVERLAP,
    Balance,
    CancelDraft,
    DayCount,
    DecisionDraft,
    Holiday,
    VacationDraft,
    VacationRequest,
    Violation,
)
from app.vacation.serialize import partial_review_json
from app.vacation.store import VacationConfig, VacationStore

log = logging.getLogger("app.vacation")
_TOKEN_NAMESPACE = uuid.UUID("0b7c6f3e-8f0a-4b8e-9d57-5a7e2f4c9a11")
ZURICH = ZoneInfo("Europe/Zurich")

Clock = Callable[[], datetime]


def utc_now() -> datetime:
    return datetime.now(UTC)


def parse_date(field: str, raw: object) -> date:
    if not isinstance(raw, str):
        raise FieldError(field, "required, ISO date YYYY-MM-DD")
    try:
        return date.fromisoformat(raw)
    except ValueError:
        raise FieldError(field, "ISO date YYYY-MM-DD") from None


def parse_decision(request_id: str, decision: object, reason: object) -> DecisionDraft:
    if decision not in ("approve", "reject"):
        raise FieldError("decision", "approve or reject")
    text: str | None = None
    if reason is not None:
        if not isinstance(reason, str):
            raise FieldError("reason", "text")
        if len(reason) > MAX_REASON:
            raise FieldError("reason", f"at most {MAX_REASON} characters")
        text = reason.strip() or None
    return DecisionDraft(request_id, str(decision), text if decision == "reject" else None)


def parse_draft(payload: object) -> VacationDraft:
    if not isinstance(payload, dict):
        raise FieldError("payload", "required")
    start = parse_date("start", payload.get("start"))
    return VacationDraft(start, parse_date("end", payload.get("end")))


@dataclass(frozen=True)
class Review:
    """What the user sees before confirming (FR-VAC-002.3)."""

    draft: VacationDraft
    count: DayCount
    balance: Balance
    remaining_after: int
    approver_name: str
    canton: str


@dataclass(frozen=True)
class ProposalResult:
    proposal: Proposal
    review: Review


@dataclass(frozen=True)
class CreateResult:
    request: VacationRequest
    created: bool


@dataclass(frozen=True)
class CancelProposal:
    proposal: Proposal
    request: VacationRequest


@dataclass(frozen=True)
class DecisionProposal:
    proposal: Proposal
    request: VacationRequest


class VacationService:
    """All FR-VAC-001/002/006 rules; REST and (Phase 6) MCP tools call the same methods."""

    def __init__(
        self,
        directory: Directory,
        store: VacationStore,
        confirmations: ConfirmationStore,
        config: VacationConfig | None = None,
        clock: Clock = utc_now,
        confirmation_ttl: timedelta = timedelta(minutes=5),
    ) -> None:
        self._directory = directory
        self._store = store
        self._confirmations = confirmations
        self._config = config or VacationConfig.from_files()
        self._clock = clock
        self._ttl = confirmation_ttl
        self._write_lock = threading.Lock()
        self._seed()

    def today(self) -> date:
        return self._clock().astimezone(ZURICH).date()

    # FR-VAC-006 ---------------------------------------------------------------------------

    def holidays(self, principal: Principal, year: int | None = None) -> list[Holiday]:
        """Holidays of the caller's own work canton only (FR-VAC-006.3)."""
        employee = self._employee(principal)
        canton = self._canton(employee)
        year = year or self.today().year
        rows = [h for h in self._config.holidays if h.canton == canton and h.date.year == year]
        return sorted(rows, key=lambda h: h.date)

    # FR-VAC-001 ---------------------------------------------------------------------------

    def balance(self, principal: Principal) -> Balance:
        """Always the caller's own, computed from their requests on every call (AC 1-3)."""
        self._employee(principal)
        return self._balance(principal.oid, self.today().year)

    def requests(self, principal: Principal) -> list[VacationRequest]:
        """Own requests of the current and the previous year (FR-VAC-007.1)."""
        self._employee(principal)
        first = self.today().year - 1
        return [r for r in self._store.for_owner(principal.oid) if r.end.year >= first]

    def inbox(self, principal: Principal) -> list[VacationRequest]:
        """Pending requests assigned to the caller as approver (FR-VAC-002.5)."""
        self._employee(principal)
        return self._store.pending_for_approver(principal.oid)

    def decisions(self, principal: Principal) -> list[VacationRequest]:
        """Every request assigned to the caller, same order and statuses as the owners (007.2)."""
        self._employee(principal)
        first = self.today().year - 1
        return [r for r in self._store.for_approver(principal.oid) if r.end.year >= first]

    # FR-VAC-002 ---------------------------------------------------------------------------

    def propose(self, principal: Principal, draft: VacationDraft) -> ProposalResult:
        """Dry run through the same validation as the write; stores only the proposal."""
        review = self._review(principal, draft)
        proposal = Proposal(
            id=str(uuid.uuid4()),
            oid=principal.oid,
            action=ACTION_REQUEST,
            draft=draft,
            expires_at=self._clock() + self._ttl,
        )
        self._confirmations.save_proposal(proposal)
        return ProposalResult(proposal, review)

    def confirm(
        self, principal: Principal, proposal_id: str, action: str = ACTION_REQUEST
    ) -> ConfirmationToken:
        """Single-use token for the user's own proposal (the tap on Submit, Cancel, Approve)."""
        self._employee(principal)
        proposal = self._confirmations.get_proposal(proposal_id)
        now = self._clock()
        if (
            proposal is None
            or proposal.oid != principal.oid
            or proposal.action != action
            or proposal.expires_at <= now
        ):
            raise invalid_confirmation()
        token = ConfirmationToken(
            token=secrets.token_urlsafe(32),
            oid=principal.oid,
            action=action,
            payload_hash=proposal.draft.payload_hash(),
            expires_at=now + self._ttl,
        )
        self._confirmations.save_token(token)
        return token

    def create(
        self, principal: Principal, draft: VacationDraft, token_value: str | None
    ) -> CreateResult:
        self._employee(principal)
        if not token_value:
            raise confirmation_required()
        with self._write_lock:
            token = self._confirmations.get_token(token_value)
            if (
                token is None
                or token.oid != principal.oid
                or token.action != ACTION_REQUEST
                or not hmac.compare_digest(token.payload_hash, draft.payload_hash())
            ):
                raise invalid_confirmation()
            if token.request_id is not None:
                existing = self._store.get(token.request_id)
                if existing is not None:
                    return CreateResult(existing, created=False)
            if token.expires_at <= self._clock():
                raise invalid_confirmation()
            review = self._review(principal, draft)  # R5-R8 again at write time
            employee = self._employee(principal)
            request = VacationRequest(
                id=str(uuid.uuid5(_TOKEN_NAMESPACE, token.token)),
                owner_oid=principal.oid,
                approver_oid=employee.manager_oid or "",
                approver_name=review.approver_name,
                start=draft.start,
                end=draft.end,
                counted_days=review.count.counted,
                per_year=dict(review.count.per_year),
                excluded=review.count.excluded,
                canton=review.canton,
                created_at=self._clock(),
                owner_name=employee.name,
            )
            stored = self._store.add(request)
            token.request_id = stored.id
            log.info("vacation request created id=%s days=%d", stored.id, stored.counted_days)
            return CreateResult(stored, created=stored is request)

    # FR-VAC-003 ---------------------------------------------------------------------------

    def get_request(self, principal: Principal, request_id: str) -> VacationRequest:
        """Detail for the owner or the assigned approver; anyone else gets NOT_FOUND (A-14)."""
        self._employee(principal)
        request = self._store.get(request_id)
        if request is None or principal.oid not in (request.owner_oid, request.approver_oid):
            raise not_found()
        return request

    def propose_cancel(self, principal: Principal, request_id: str) -> CancelProposal:
        """Dry run: only the owner can cancel, and only while pending (R11)."""
        request = self._own_pending(principal, request_id)
        draft = CancelDraft(request_id)
        proposal = Proposal(
            id=str(uuid.uuid4()),
            oid=principal.oid,
            action=ACTION_CANCEL,
            draft=draft,
            expires_at=self._clock() + self._ttl,
        )
        self._confirmations.save_proposal(proposal)
        return CancelProposal(proposal, request)

    def cancel(
        self, principal: Principal, request_id: str, token_value: str | None
    ) -> VacationRequest:
        """Pending -> cancelled; releases the reserved days and leaves the approver's inbox.

        Idempotent on the confirmation token: a replay returns the cancelled request.
        """
        self._employee(principal)
        if not token_value:
            raise confirmation_required()
        with self._write_lock:
            token = self._confirmations.get_token(token_value)
            if (
                token is None
                or token.oid != principal.oid
                or token.action != ACTION_CANCEL
                or not hmac.compare_digest(
                    token.payload_hash, CancelDraft(request_id).payload_hash()
                )
            ):
                raise invalid_confirmation()
            if token.request_id == request_id:
                done = self._store.get(request_id)
                if done is not None:
                    return done
            if token.expires_at <= self._clock():
                raise invalid_confirmation()
            request = self._own_pending(principal, request_id)
            now = self._clock()
            cancelled = self._store.replace_if_status(
                replace(request, status="cancelled", decided_at=now, decided_by=principal.oid),
                "pending",
            )
            if cancelled is None:
                raise invalid_state()
            token.request_id = request_id
            log.info("vacation request cancelled id=%s", request_id)
            return cancelled

    # FR-VAC-004 ---------------------------------------------------------------------------

    def owner_balance(self, principal: Principal, request: VacationRequest) -> Balance | None:
        """The report's balance, for their approver only (FR-VAC-001.3)."""
        if request.approver_oid != principal.oid:
            return None
        return self._balance(request.owner_oid, request.start.year)

    def propose_decision(
        self, principal: Principal, request_id: str, decision: str, reason: object
    ) -> DecisionProposal:
        """Dry run: assigned approver only, pending only, and an approval must still be valid."""
        draft = parse_decision(request_id, decision, reason)
        request = self._decidable(principal, request_id)
        if draft.decision == "approve":
            self._revalidate(request)
        proposal = Proposal(
            id=str(uuid.uuid4()),
            oid=principal.oid,
            action=ACTION_DECIDE,
            draft=draft,
            expires_at=self._clock() + self._ttl,
        )
        self._confirmations.save_proposal(proposal)
        return DecisionProposal(proposal, request)

    def decide(
        self,
        principal: Principal,
        request_id: str,
        decision: str,
        reason: object,
        token_value: str | None,
    ) -> VacationRequest:
        """Approve or reject; final and idempotent on the confirmation token (AC 1-3, 5)."""
        draft = parse_decision(request_id, decision, reason)
        self._employee(principal)
        if not token_value:
            raise confirmation_required()
        with self._write_lock:
            token = self._confirmations.get_token(token_value)
            if (
                token is None
                or token.oid != principal.oid
                or token.action != ACTION_DECIDE
                or not hmac.compare_digest(token.payload_hash, draft.payload_hash())
            ):
                raise invalid_confirmation()
            if token.request_id == request_id:
                done = self._store.get(request_id)
                if done is not None:
                    return done
            if token.expires_at <= self._clock():
                raise invalid_confirmation()
            request = self._decidable(principal, request_id)
            if draft.decision == "approve":
                self._revalidate(request)  # R5-R7 again; a failure leaves the request pending
            decided = self._store.replace_if_status(
                replace(
                    request,
                    status="approved" if draft.decision == "approve" else "rejected",
                    decided_at=self._clock(),
                    decided_by=principal.oid,
                    decision_reason=draft.reason,
                ),
                "pending",
            )
            if decided is None:
                raise invalid_state()
            token.request_id = request_id
            log.info("vacation request %s id=%s", decided.status, request_id)
            return decided

    def _decidable(self, principal: Principal, request_id: str) -> VacationRequest:
        self._employee(principal)
        request = self._store.get(request_id)
        if request is None:
            raise not_found()
        if request.owner_oid == principal.oid:
            raise self_approval()  # R10
        if request.approver_oid != principal.oid:
            raise forbidden()
        if request.status != "pending":
            raise invalid_state()
        return request

    def _revalidate(self, request: VacationRequest) -> None:
        """R5-R7 at decision time; the request's own reservation is not counted against itself."""
        owner = self._directory.get(request.owner_oid)
        if owner is None:
            raise not_found()
        others = [r for r in self._store.for_owner(owner.oid) if r.id != request.id]
        found = rules.validate(
            request.start,
            request.end,
            self.today(),
            DayCount(request.counted_days, request.per_year, request.excluded),
            [
                b
                for b in self._config.blackouts
                if rules.blackout_applies(b, owner.region, owner.store)
            ],
            others,
            lambda year: self._balance(owner.oid, year, others),
        )
        failing = [v for v in found if v.code in (BLACKOUT, OVERLAP, INSUFFICIENT_BALANCE)]
        if failing:
            raise rule_violation([_violation(v) for v in failing])

    def _own_pending(self, principal: Principal, request_id: str) -> VacationRequest:
        self._employee(principal)
        request = self._store.get(request_id)
        if request is None or request.owner_oid != principal.oid:
            raise not_found()  # unknown and someone else's look the same
        if request.status != "pending":
            raise invalid_state()
        return request

    # internals ----------------------------------------------------------------------------

    def _review(self, principal: Principal, draft: VacationDraft) -> Review:
        employee = self._employee(principal)
        canton = self._canton(employee)
        approver = self._approver(employee)
        count = None
        if draft.end >= draft.start:
            count = rules.count_days(draft.start, draft.end, self._holiday_map(canton))
        mine = self._store.for_owner(principal.oid)
        violations = rules.validate(
            draft.start,
            draft.end,
            self.today(),
            count,
            [
                b
                for b in self._config.blackouts
                if rules.blackout_applies(b, employee.region, employee.store)
            ],
            mine,
            lambda year: self._balance(principal.oid, year, mine),
        )
        if violations or count is None:
            partial = None
            if count is not None:
                year = draft.start.year
                partial = partial_review_json(count, self._balance(principal.oid, year, mine))
            raise rule_violation([_violation(v) for v in violations], partial)
        balance = self._balance(principal.oid, draft.start.year, mine)
        remaining_after = balance.remaining - count.per_year.get(balance.year, 0)
        return Review(draft, count, balance, remaining_after, approver.name, canton)

    def _balance(
        self, oid: str, year: int, requests: list[VacationRequest] | None = None
    ) -> Balance:
        base_year = self.today().year
        return rules.balance_for(
            max(year, base_year),
            self._config.entitlement,
            self._config.carry_over.get(oid, 0),
            base_year,
            self._store.for_owner(oid) if requests is None else requests,
        )

    def _holiday_map(self, canton: str) -> dict[date, Holiday]:
        return {h.date: h for h in self._config.holidays if h.canton == canton}

    def _employee(self, principal: Principal) -> Employee:
        employee = self._directory.get(principal.oid)
        if employee is None or not employee.active:
            raise not_provisioned()
        return employee

    @staticmethod
    def _canton(employee: Employee) -> str:
        if not employee.canton:
            raise canton_missing()
        return employee.canton

    def _approver(self, employee: Employee) -> Employee:
        """R10: direct manager; the CEO has none (U-12: NO_APPROVER)."""
        if employee.manager_oid is None:
            raise no_approver()
        if employee.manager_oid == employee.oid:
            raise self_approval()
        approver = self._directory.get(employee.manager_oid)
        if approver is None or not approver.active:
            raise no_approver()
        return approver

    def _seed(self) -> None:
        for seed in self._config.seed_requests:
            owner = self._directory.get(seed.owner)
            if owner is None or owner.canton is None or owner.manager_oid is None:
                continue
            approver = self._directory.get(owner.manager_oid)
            count = rules.count_days(seed.start, seed.end, self._holiday_map(owner.canton))
            self._store.add(
                VacationRequest(
                    id=seed.id,
                    owner_oid=owner.oid,
                    approver_oid=owner.manager_oid,
                    approver_name=approver.name if approver else "",
                    start=seed.start,
                    end=seed.end,
                    counted_days=count.counted,
                    per_year=dict(count.per_year),
                    excluded=count.excluded,
                    canton=owner.canton,
                    created_at=datetime(2026, 1, 1, tzinfo=UTC),
                    status=seed.status,
                    owner_name=owner.name,
                    decided_at=seed.decided_at,
                    decided_by=owner.manager_oid if seed.decided_at else None,
                    decision_reason=seed.reason,
                )
            )


def _violation(v: Violation) -> dict[str, object]:
    return {"code": v.code, **v.details}
