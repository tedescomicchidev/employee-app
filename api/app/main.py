from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.announcements.service import AnnouncementService
from app.auth.errors import ApiError
from app.auth.validator import JwksKeyProvider, TokenValidator
from app.config import load_settings
from app.directory.graph import GraphProfileClient, MsalGraphProfileClient
from app.directory.provisioning import Provisioner
from app.directory.settings import DirectorySettings, load_directory_settings
from app.repositories import (
    InMemoryAnnouncementStore,
    InMemoryConfirmationStore,
    SeedDirectory,
)
from app.routes import announcements, events, me, proposals, vacation
from app.telemetry import ApiCallLog, record_api_call
from app.vacation.service import VacationService
from app.vacation.store import InMemoryVacationStore


def create_app(
    validator: TokenValidator | None = None,
    announcement_service: AnnouncementService | None = None,
    vacation_service: VacationService | None = None,
    directory: SeedDirectory | None = None,
    directory_client: GraphProfileClient | None = None,
    directory_settings: DirectorySettings | None = None,
) -> FastAPI:
    app = FastAPI(title="Employee App API")
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
    app.state.provisioner = build_provisioner(directory, directory_client, directory_settings)
    app.state.event_sink = []  # TODO(EXP): replace with the events container (ADR-009)
    app.state.api_call_log = ApiCallLog()
    app.middleware("http")(record_api_call)

    @app.exception_handler(ApiError)
    def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(me.router)
    app.include_router(announcements.router)
    app.include_router(proposals.router)
    app.include_router(vacation.router)
    app.include_router(events.router)
    return app


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
