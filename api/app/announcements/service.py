import hmac
import logging
import secrets
import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from app.announcements.models import (
    ACTION_PUBLISH,
    BODY_MAX,
    TITLE_MAX,
    Announcement,
    Audience,
    Draft,
    InboxItem,
    Language,
)
from app.auth.errors import (
    FieldError,
    confirmation_required,
    invalid_confirmation,
    not_provisioned,
)
from app.auth.principal import Principal, Role, authorize
from app.repositories import (
    AnnouncementStore,
    ConfirmationStore,
    ConfirmationToken,
    Directory,
    Proposal,
)

log = logging.getLogger("app.announcements")
_TOKEN_NAMESPACE = uuid.UUID("6f1b6a7e-5d7e-4a8e-9a33-3c7f4f1d2b10")

Clock = Callable[[], datetime]


def utc_now() -> datetime:
    return datetime.now(UTC)


def validate_draft(title: object, body: object, language: object, audience: object) -> Draft:
    """All FR-ANN-001 field rules live here, shared by REST and (later) MCP."""
    if not isinstance(title, str) or not 1 <= len(title) <= TITLE_MAX:
        raise FieldError("title", f"1 to {TITLE_MAX} characters")
    if not isinstance(body, str) or not 1 <= len(body) <= BODY_MAX:
        raise FieldError("body", f"1 to {BODY_MAX} characters")
    try:
        lang = Language(language)
    except ValueError:
        raise FieldError("language", "one of de, fr, it, en") from None
    try:
        aud = Audience(audience)
    except ValueError:
        raise FieldError("audience", "only 'all' is supported") from None
    return Draft(title=title, body=body, language=lang, audience=aud)


@dataclass(frozen=True)
class ProposalResult:
    proposal: Proposal
    recipient_count: int


@dataclass(frozen=True)
class PublishResult:
    announcement: Announcement
    created: bool


class AnnouncementService:
    def __init__(
        self,
        directory: Directory,
        announcements: AnnouncementStore,
        confirmations: ConfirmationStore,
        clock: Clock = utc_now,
        confirmation_ttl: timedelta = timedelta(minutes=5),
    ) -> None:
        self._directory = directory
        self._announcements = announcements
        self._confirmations = confirmations
        self._clock = clock
        self._ttl = confirmation_ttl
        self._publish_lock = threading.Lock()

    def propose(self, principal: Principal, draft: Draft) -> ProposalResult:
        """Dry run of the write: same role and validation checks, stores nothing visible."""
        authorize(principal, Role.COMMUNICATOR)
        proposal = Proposal(
            id=str(uuid.uuid4()),
            oid=principal.oid,
            action=ACTION_PUBLISH,
            draft=draft,
            expires_at=self._clock() + self._ttl,
        )
        self._confirmations.save_proposal(proposal)
        return ProposalResult(proposal, len(self._directory.active()))

    def confirm(self, principal: Principal, proposal_id: str) -> ConfirmationToken:
        """Mint a single-use token for the user's own proposal (the user's tap on Review)."""
        authorize(principal, Role.COMMUNICATOR)
        proposal = self._confirmations.get_proposal(proposal_id)
        now = self._clock()
        if proposal is None or proposal.oid != principal.oid or proposal.expires_at <= now:
            raise invalid_confirmation()
        token = ConfirmationToken(
            token=secrets.token_urlsafe(32),
            oid=principal.oid,
            action=proposal.action,
            payload_hash=proposal.draft.payload_hash(),
            expires_at=now + self._ttl,
        )
        self._confirmations.save_token(token)
        return token

    def publish(self, principal: Principal, draft: Draft, token_value: str | None) -> PublishResult:
        authorize(principal, Role.COMMUNICATOR)
        if not token_value:
            raise confirmation_required()
        with self._publish_lock:
            token = self._confirmations.get_token(token_value)
            if (
                token is None
                or token.oid != principal.oid
                or token.action != ACTION_PUBLISH
                or not hmac.compare_digest(token.payload_hash, draft.payload_hash())
            ):
                raise invalid_confirmation()
            if token.announcement_id is not None:
                existing = self._announcements.get(token.announcement_id)
                if existing is not None:
                    return PublishResult(existing, created=False)
            if token.expires_at <= self._clock():
                raise invalid_confirmation()
            recipients = [e.oid for e in self._directory.active()]
            announcement = Announcement(
                id=str(uuid.uuid5(_TOKEN_NAMESPACE, token.token)),
                title=draft.title,
                body=draft.body,
                language=draft.language,
                audience=draft.audience,
                author_oid=principal.oid,
                author_name=principal.display_name,
                published_at=self._clock(),
                recipient_count=len(recipients),
            )
            stored = self._announcements.publish(announcement, recipients)
            token.announcement_id = stored.id
            log.info("announcement published id=%s recipients=%d", stored.id, len(recipients))
            return PublishResult(stored, created=stored is announcement)

    def list_for(self, principal: Principal) -> list[tuple[Announcement, InboxItem]]:
        employee = self._directory.get(principal.oid)
        if employee is None or not employee.active:
            raise not_provisioned()
        return self._announcements.list_for(principal.oid)
