import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    tenant_id: str
    api_client_id: str
    api_audience: str
    # Resource app for agent tool calls (ADR-002); its tokens come from OBO, never from iOS.
    tools_client_id: str = ""
    tools_audience: str = ""

    @property
    def issuer(self) -> str:
        return f"https://login.microsoftonline.com/{self.tenant_id}/v2.0"

    @property
    def audiences(self) -> list[str]:
        """v2 access tokens carry the bare client id as `aud`, v1 tokens the application id URI."""
        return [a for a in dict.fromkeys([self.api_audience, self.api_client_id]) if a]

    @property
    def tools_audiences(self) -> list[str]:
        return [a for a in dict.fromkeys([self.tools_audience, self.tools_client_id]) if a]

    @property
    def issuers(self) -> list[str]:
        """v2.0 issuer, plus the v1 issuer in case the app registration still issues v1 tokens."""
        return [self.issuer, f"https://sts.windows.net/{self.tenant_id}/"]

    @property
    def jwks_uri(self) -> str:
        return f"https://login.microsoftonline.com/{self.tenant_id}/discovery/v2.0/keys"


def load_settings() -> Settings:
    client_id = os.environ.get("API_CLIENT_ID", "")
    tools_client_id = os.environ.get("TOOLS_CLIENT_ID", "")
    return Settings(
        tenant_id=os.environ.get("ENTRA_TENANT_ID", ""),
        api_client_id=client_id,
        api_audience=os.environ.get("API_AUDIENCE", f"api://{client_id}"),
        tools_client_id=tools_client_id,
        tools_audience=os.environ.get(
            "TOOLS_AUDIENCE", f"api://{tools_client_id}" if tools_client_id else ""
        ),
    )
