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
    def audiences(self) -> list[str]:
        """v2 access tokens carry the bare client id as `aud`, v1 tokens the application id URI."""
        return [a for a in dict.fromkeys([self.api_audience, self.api_client_id]) if a]

    @property
    def issuers(self) -> list[str]:
        """v2.0 issuer, plus the v1 issuer in case the app registration still issues v1 tokens."""
        return [self.issuer, f"https://sts.windows.net/{self.tenant_id}/"]

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
