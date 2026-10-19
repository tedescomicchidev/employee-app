import os
from dataclasses import dataclass, field
from datetime import timedelta


@dataclass(frozen=True)
class DirectorySettings:
    """Which Graph user properties hold the HR attributes. Tenant specific, hence configuration."""

    enabled: bool = False
    managed_identity_client_id: str = ""
    canton_attribute: str = "state"
    store_attribute: str = "officeLocation"
    region_attribute: str = "preferredLanguage"
    ttl: timedelta = field(default_factory=lambda: timedelta(hours=12))

    @property
    def attributes(self) -> list[str]:
        names = [self.canton_attribute, self.store_attribute, self.region_attribute]
        return [n for n in dict.fromkeys(names) if n]


def load_directory_settings() -> DirectorySettings:
    """`GRAPH_DIRECTORY=true` turns on Graph-backed provisioning (needs the federated identity)."""
    env = os.environ
    return DirectorySettings(
        enabled=env.get("GRAPH_DIRECTORY", "").lower() in ("1", "true", "yes"),
        managed_identity_client_id=env.get("AZURE_CLIENT_ID", ""),
        canton_attribute=env.get("GRAPH_CANTON_ATTRIBUTE", "state"),
        store_attribute=env.get("GRAPH_STORE_ATTRIBUTE", "officeLocation"),
        region_attribute=env.get("GRAPH_REGION_ATTRIBUTE", "preferredLanguage"),
        ttl=timedelta(hours=float(env.get("GRAPH_DIRECTORY_TTL_HOURS", "12"))),
    )
