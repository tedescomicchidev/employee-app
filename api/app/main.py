import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.routing import Route

from app.agents.foundry import (
    AgentResponder,
    AgentSettings,
    HttpAgentResponder,
    MsalToolsTokenClient,
    ToolsTokenClient,
    load_agent_settings,
)
from app.agents.turns import AgentRunLog, TurnRateLimiter
from app.announcements.service import AnnouncementService
from app.auth.errors import ApiError
from app.auth.validator import JwksKeyProvider, TokenValidator
from app.briefing import workiq
from app.briefing.service import BriefingService
from app.briefing.store import InMemoryBriefingSettingsStore
from app.config import load_settings
from app.directory.graph import GraphProfileClient, MsalGraphProfileClient
from app.directory.provisioning import Provisioner
from app.directory.settings import DirectorySettings, load_directory_settings
from app.mcp.audit import McpAuditLog
from app.mcp.server import McpGateway, build_mcp_server
from app.repositories import (
    InMemoryAnnouncementStore,
    InMemoryConfirmationStore,
    SeedDirectory,
)
from app.routes import agent, announcements, briefing, events, me, proposals, vacation
from app.telemetry import ApiCallLog, record_api_call
from app.vacation.service import VacationService
from app.vacation.store import InMemoryVacationStore


def create_app(
    validator: TokenValidator | None = None,
    announcement_service: AnnouncementService | None = None,
    vacation_service: VacationService | None = None,
    briefing_service: BriefingService | None = None,
    work_iq_client: workiq.WorkIQClient | None = None,
    directory: SeedDirectory | None = None,
    directory_client: GraphProfileClient | None = None,
    directory_settings: DirectorySettings | None = None,
    agent_settings: AgentSettings | None = None,
    tools_token_client: ToolsTokenClient | None = None,
    agent_responder: AgentResponder | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        async with mcp.session_manager.run():
            yield

    app = FastAPI(title="Employee App API", lifespan=lifespan)
    if validator is None:
        settings = load_settings()
        validator = TokenValidator(settings, JwksKeyProvider(settings.jwks_uri))
    app.state.token_validator = validator
    # In-memory stores until the Cosmos repositories land (ADR-007). One directory is shared by
    # every service and by the provisioner that adds signed-in users to it (ADR-010).
    directory = directory or SeedDirectory.from_file()
    app.state.announcement_service = announcement_service or AnnouncementService(
        directory, InMemoryAnnouncementStore(), InMemoryConfirmationStore()
    )
    app.state.vacation_service = vacation_service or VacationService(
        directory, InMemoryVacationStore(), InMemoryConfirmationStore()
    )
    app.state.briefing_service = briefing_service or BriefingService(
        directory,
        InMemoryBriefingSettingsStore(),
        InMemoryConfirmationStore(),
        work_iq_client or build_work_iq_client(),
    )
    app.state.provisioner = build_provisioner(directory, directory_client, directory_settings)
    app.state.event_sink = []  # TODO(EXP): replace with the events container (ADR-009)
    app.state.api_call_log = ApiCallLog()
    app.state.mcp_audit = McpAuditLog()
    agent_settings = agent_settings or load_agent_settings()
    app.state.agent_settings = agent_settings
    app.state.agent_runs = AgentRunLog()
    app.state.turn_limiter = TurnRateLimiter(agent_settings.turns_per_minute)
    app.state.tools_token_client = tools_token_client or build_tools_token_client(agent_settings)
    app.state.agent_responder = agent_responder or (
        HttpAgentResponder(agent_settings) if agent_settings.enabled else None
    )
    # MCP tool server (ADR-005): same Container App, same services, its own audience (ADR-002).
    mcp = build_mcp_server(app)
    gateway = McpGateway(mcp.streamable_http_app(), app)
    for path in ("/mcp", "/mcp/"):  # exact routes: Mount would redirect and capture other paths
        app.router.routes.append(Route(path, endpoint=gateway))
    app.middleware("http")(record_api_call)

    @app.exception_handler(ApiError)
    def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=exc.detail, headers=exc.headers)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(me.router)
    app.include_router(announcements.router)
    app.include_router(proposals.router)
    app.include_router(vacation.router)
    app.include_router(briefing.router)
    app.include_router(events.router)
    app.include_router(agent.router)
    return app


def build_tools_token_client(settings: AgentSettings) -> ToolsTokenClient | None:
    api = load_settings()
    if not (settings.enabled and api.tools_audience and settings.managed_identity_client_id):
        return None
    return MsalToolsTokenClient(
        api.tenant_id, api.api_client_id, api.tools_audience, settings.managed_identity_client_id
    )


def build_work_iq_client() -> workiq.WorkIQClient:
    """Work IQ is reached only on behalf of the user (ADR-004); without the app registrations and
    the managed identity there is no client, and the briefing answers WORKIQ_UNAVAILABLE."""
    api = load_settings()
    identity = os.environ.get("AZURE_CLIENT_ID", "")
    apps = [
        workiq.WorkIQApp(client_id, tuple(audiences))
        for client_id, audiences in (
            (api.api_client_id, api.audiences),
            (api.tools_client_id, api.tools_audiences),
        )
        if client_id
    ]
    if not (api.tenant_id and apps and identity):
        return workiq.UnconfiguredWorkIQClient()
    return workiq.MsalWorkIQClient(api.tenant_id, apps, identity)


def build_provisioner(
    directory: SeedDirectory,
    client: GraphProfileClient | None,
    settings: DirectorySettings | None,
) -> Provisioner | None:
    settings = settings or load_directory_settings()
    if not settings.enabled:
        return None
    if client is None:
        api = load_settings()
        client = MsalGraphProfileClient(
            api.tenant_id, api.api_client_id, settings.managed_identity_client_id
        )
    return Provisioner(directory, client, settings)


app = create_app()
