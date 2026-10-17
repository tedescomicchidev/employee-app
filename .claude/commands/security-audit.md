Audit this repository. Run me in a fresh session; ignore prior context.
For each check report PASS / PARTIAL / FAIL, severity, location, CWE, fix.
iOS: no secrets in source, plist, xcconfig or built .app; MSAL tokens only
in Keychain; ATS without blanket exceptions; no PII/tokens in logs;
PrivacyInfo.xcprivacy complete; debug menus compiled out of Release.
Identity: Entra token validation (issuer, audience, roles) in api/; OBO
flow correct; no app-only Work IQ calls; role checks shared by REST and
MCP tools.
Agents: prompt injection via announcement text; tools scoped per agent;
no write without confirmation_token; no cross-user data in briefings.
Azure: managed identity everywhere, Key Vault for the Work IQ secret, no
keys in azure.yaml or Bicep outputs, least-privilege role assignments,
rate limits on agent endpoints.
Supply chain: pinned dependencies, no nonexistent packages.
Then fix every FAIL and PARTIAL, re-run checks, list any new issue your
fixes introduced, open a PR.
