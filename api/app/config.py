import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    tenant_id: str
    api_client_id: str
    api_audience: str

    @property
    def issuer(self) -> str:
        return f"https://login.microsoftonline.com/{self.tenant_id}/v2.0"

    @property
    def jwks_uri(self) -> str:
        return f"https://login.microsoftonline.com/{self.tenant_id}/discovery/v2.0/keys"


def load_settings() -> Settings:
    client_id = os.environ.get("API_CLIENT_ID", "")
    return Settings(
        tenant_id=os.environ.get("ENTRA_TENANT_ID", ""),
        api_client_id=client_id,
        api_audience=os.environ.get("API_AUDIENCE", f"api://{client_id}"),
    )
