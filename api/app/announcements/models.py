import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum

TITLE_MAX = 120
BODY_MAX = 5000
ACTION_PUBLISH = "publish_announcement"


class Language(StrEnum):
    DE = "de"
    FR = "fr"
    IT = "it"
    EN = "en"


class Audience(StrEnum):
    ALL = "all"


@dataclass(frozen=True)
class Draft:
    title: str
    body: str
    language: Language
    audience: Audience

    def canonical(self) -> dict[str, str]:
        return {
            "title": self.title,
            "body": self.body,
            "language": self.language.value,
            "audience": self.audience.value,
        }

    def payload_hash(self) -> str:
        """Hash of the exact payload; confirmation tokens are bound to it (FR-AUTH-006.1)."""
        raw = json.dumps(
            self.canonical(), sort_keys=True, ensure_ascii=False, separators=(",", ":")
        )
        return hashlib.sha256(raw.encode()).hexdigest()


@dataclass(frozen=True)
class Announcement:
    id: str
    title: str
    body: str
    language: Language
    audience: Audience
    author_oid: str
    author_name: str
    published_at: datetime
    recipient_count: int
    status: str = "published"


@dataclass(frozen=True)
class InboxItem:
    announcement_id: str
    oid: str
    status: str
    read_at: datetime | None = None
