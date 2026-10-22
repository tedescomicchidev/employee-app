import hmac
import logging
import secrets
import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from app.auth.errors import (
    ApiError,
    confirmation_required,
    invalid_confirmation,
    not_found,
    not_provisioned,
    unauthenticated,
)
from app.auth.principal import Principal
from app.briefing import workiq
from app.briefing.models import (
    ACTION_OPT_IN,
    Briefing,
    OptInDraft,
    OptInState,
)
from app.briefing.store import BriefingSettingsStore
from app.briefing.week import WeekConfig, build_briefing, week_days, week_start
from app.repositories import ConfirmationStore, ConfirmationToken, Directory, Proposal

log = logging.getLogger("app.briefing")
Clock = Callable[[], datetime]
_APPLIED = "applied"


def utc_now() -> datetime:
    return datetime.now(UTC)


def not_opted_in() -> ApiError:
    return ApiError(
        403, "NOT_OPTED_IN", "The weekly briefing is off; turn it on to read your calendar"
    )


def _workiq_error(error: workiq.WorkIQError) -> ApiError:
    """FR-BRF-005.1: one specific, actionable code per cause, never any content."""
    match error.code:
        case workiq.CONSENT_REQUIRED:
            return ApiError(
                403, "CONSENT_REQUIRED", "Work IQ is not approved yet; ask your administrator"
            )
        case workiq.NO_LICENCE:
            return ApiError(403, "NO_LICENCE", "Your account does not have access to Work IQ")
        case workiq.REAUTH:
            return unauthenticated("Sign in again to read your calendar")
        case _:
            return ApiError(
                503, "WORKIQ_UNAVAILABLE", "Work IQ is temporarily unavailable, try again"
            )


@dataclass(frozen=True)
class OptInProposal:
    proposal: Proposal
    state: OptInState


class BriefingService:
    """FR-BRF-001..005 and FR-AUTH-004. REST and the MCP tools call exactly these methods."""

    def __init__(
        self,
        directory: Directory,
        settings: BriefingSettingsStore,
        confirmations: ConfirmationStore,
        work_iq: workiq.WorkIQClient,
        config: WeekConfig | None = None,
        clock: Clock = utc_now,
        confirmation_ttl: timedelta = timedelta(minutes=5),
    ) -> None:
        self._directory = directory
        self._settings = settings
        self._confirmations = confirmations
        self._work_iq = work_iq
        self._config = config or WeekConfig()
        self._clock = clock
        self._ttl = confirmation_ttl
        self._lock = threading.Lock()

    # FR-BRF-001 ---------------------------------------------------------------------------

    def status(self, principal: Principal) -> OptInState:
        self._employee(principal)
        at = self._settings.get(principal.oid)
        return OptInState(at is not None, at)

    def propose_opt_in(self, principal: Principal, enabled: bool) -> OptInProposal:
        """Dry run: stores only the proposal. The toggle itself is a write (FR-AUTH-006)."""
        state = self.status(principal)
        proposal = Proposal(
            id=str(uuid.uuid4()),
            oid=principal.oid,
            action=ACTION_OPT_IN,
            draft=OptInDraft(enabled),
            expires_at=self._clock() + self._ttl,
        )
        self._confirmations.save_proposal(proposal)
        return OptInProposal(proposal, state)

    def find_proposal(self, proposal_id: str) -> Proposal | None:
        proposal = self._confirmations.get_proposal(proposal_id)
        return proposal if proposal is not None and proposal.action == ACTION_OPT_IN else None

    def get_proposal(self, principal: Principal, proposal_id: str) -> Proposal:
        """What the confirm card shows: the caller's own unexpired proposal, else NOT_FOUND."""
        self._employee(principal)
        proposal = self.find_proposal(proposal_id)
        if proposal is None or proposal.oid != principal.oid:
            raise not_found()
        if proposal.expires_at <= self._clock():
            raise not_found()
        return proposal

    def confirm(self, principal: Principal, proposal_id: str) -> ConfirmationToken:
        """Single-use token for the user's own proposal (the tap on the confirm card)."""
        self._employee(principal)
        proposal = self.find_proposal(proposal_id)
        now = self._clock()
        if proposal is None or proposal.oid != principal.oid or proposal.expires_at <= now:
            raise invalid_confirmation()
        token = ConfirmationToken(
            token=secrets.token_urlsafe(32),
            oid=principal.oid,
            action=ACTION_OPT_IN,
            payload_hash=proposal.draft.payload_hash(),
            expires_at=now + self._ttl,
        )
        self._confirmations.save_token(token)
        return token

    def set_opt_in(
        self, principal: Principal, enabled: bool, token_value: str | None
    ) -> OptInState:
        """Opt in or out. Opt-out removes the stored record at once; Work IQ is not called again.

        A replayed token (a retry after a lost response) changes nothing and returns the state.
        """
        self._employee(principal)
        if not token_value:
            raise confirmation_required()
        with self._lock:
            token = self._confirmations.get_token(token_value)
            if (
                token is None
                or token.oid != principal.oid
                or token.action != ACTION_OPT_IN
                or not hmac.compare_digest(token.payload_hash, OptInDraft(enabled).payload_hash())
            ):
                raise invalid_confirmation()
            if token.request_id == _APPLIED:
                return self.status(principal)
            if token.expires_at <= self._clock():
                raise invalid_confirmation()
            if enabled:
                self._settings.opt_in(principal.oid, self._clock())
            else:
                self._settings.delete(principal.oid)
            token.request_id = _APPLIED
        return self.status(principal)

    # FR-BRF-002, FR-BRF-005, FR-AUTH-004 ------------------------------------------------------

    def week(self, principal: Principal) -> Briefing:
        """The caller's own week from Work IQ with the caller's delegated token, in memory only.

        There is no user parameter: another person's calendar cannot be asked for (FR-BRF-004).
        """
        self._employee(principal)
        if self._settings.get(principal.oid) is None:
            raise not_opted_in()  # no Work IQ call without the opt-in (FR-BRF-001.1)
        start = week_start(self._clock())
        try:
            fetch = self._work_iq.fetch_week(principal.assertion, week_days(start))
        except workiq.WorkIQError as exc:
            # A code and the stage it failed at: never a token, a response body or an event.
            log.warning("work iq week failed code=%s stage=%s", exc.code, exc.stage or "-")
            raise _workiq_error(exc) from None
        return build_briefing(start, fetch, self._config)

    def _employee(self, principal: Principal) -> None:
        employee = self._directory.get(principal.oid)
        if employee is None or not employee.active:
            raise not_provisioned()
