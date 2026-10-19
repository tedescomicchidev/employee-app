import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any

TITLE_MAX = 120
BODY_MAX = 5000
ACTION_PUBLISH = "publish_announcement"


class Language(StrEnum):
    DE = "de"
    FR = "fr"
    IT = "it"
    EN = "en"


ALL = "all"
AUDIENCE_DIMENSIONS = ("regions", "stores", "roles")
AUDIENCE_VALUE_MAX = 64
AUDIENCE_VALUES_MAX = 50


@dataclass(frozen=True)
class Audience:
    """`all` or a union of regions, stores/HQ and roles (FR-ANN-002.1). Values are stored sorted."""

    everyone: bool = False
    regions: tuple[str, ...] = ()
    stores: tuple[str, ...] = ()
    roles: tuple[str, ...] = ()

    def canonical(self) -> str | dict[str, list[str]]:
        if self.everyone:
            return ALL
        return {
            "regions": list(self.regions),
            "stores": list(self.stores),
            "roles": list(self.roles),
        }

    def matches(self, region: str, store: str, role: str) -> bool:
        if self.everyone:
            return True
        return region in self.regions or store in self.stores or role in self.roles


@dataclass(frozen=True)
class Draft:
    title: str
    body: str
    language: Language
    audience: Audience

    def canonical(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "body": self.body,
            "language": self.language.value,
            "audience": self.audience.canonical(),
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
