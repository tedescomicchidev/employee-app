"""The caller's own directory attributes from Microsoft Graph, user-delegated (OBO) only.

Docs: learn.microsoft.com/entra/identity-platform/v2-oauth2-on-behalf-of-flow,
learn.microsoft.com/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity,
learn.microsoft.com/graph/api/user-get and .../user-list-manager (`/me`, `/me/manager`, User.Read).
No client secret: the API app registration trusts the container app's managed identity.
"""

from dataclasses import dataclass
from typing import Any, Protocol

import msal
import requests

GRAPH = "https://graph.microsoft.com/v1.0"
SCOPES = ["https://graph.microsoft.com/User.Read"]
TIMEOUT_SECONDS = 10


class GraphError(Exception):
    """Lookup failed. `code` is short and stable; it never holds tokens or profile data."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class GraphProfile:
    oid: str
    display_name: str
    attributes: dict[str, str]
    manager_oid: str | None = None
    manager_name: str = ""


class GraphProfileClient(Protocol):
    def fetch(self, user_assertion: str, attributes: list[str]) -> GraphProfile: ...


class MsalGraphProfileClient:
    def __init__(self, tenant_id: str, api_client_id: str, managed_identity_client_id: str) -> None:
        self._identity = msal.ManagedIdentityClient(
            msal.UserAssignedManagedIdentity(client_id=managed_identity_client_id),
            http_client=requests.Session(),
        )
        self._app = msal.ConfidentialClientApplication(
            api_client_id,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
            client_credential={"client_assertion": self._assertion},
        )

    def _assertion(self) -> str:
        result = self._identity.acquire_token_for_client(resource="api://AzureADTokenExchange")
        token = result.get("access_token")
        if not token:
            raise GraphError("managed_identity")
        return str(token)

    def fetch(self, user_assertion: str, attributes: list[str]) -> GraphProfile:
        result = self._app.acquire_token_on_behalf_of(user_assertion, scopes=SCOPES)
        token = result.get("access_token")
        if not token:
            # consent_required, interaction_required, invalid_grant: a code, never the description.
            raise GraphError(str(result.get("error") or "obo_failed"))
        headers = {"Authorization": f"Bearer {token}"}
        select = ",".join(dict.fromkeys(["id", "displayName", *attributes]))
        me = self._get(f"{GRAPH}/me?$select={select}", headers)
        manager = self._get(f"{GRAPH}/me/manager?$select=id,displayName", headers, missing_ok=True)
        return GraphProfile(
            oid=str(me.get("id", "")),
            display_name=str(me.get("displayName") or ""),
            attributes={a: str(me[a]) for a in attributes if me.get(a)},
            manager_oid=str(manager["id"]) if manager and manager.get("id") else None,
            manager_name=str((manager or {}).get("displayName") or ""),
        )

    @staticmethod
    def _get(url: str, headers: dict[str, str], missing_ok: bool = False) -> dict[str, Any]:
        try:
            response = requests.get(url, headers=headers, timeout=TIMEOUT_SECONDS)
        except requests.RequestException:
            raise GraphError("graph_unreachable") from None
        if response.status_code == 404 and missing_ok:  # no manager assigned
            return {}
        if response.status_code != 200:
            raise GraphError(f"graph_{response.status_code}")
        body: dict[str, Any] = response.json()
        return body
