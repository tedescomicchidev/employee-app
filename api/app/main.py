from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.announcements.service import AnnouncementService
from app.auth.errors import ApiError
from app.auth.validator import JwksKeyProvider, TokenValidator
from app.config import load_settings
from app.repositories import (
    InMemoryAnnouncementStore,
    InMemoryConfirmationStore,
    SeedDirectory,
)
from app.routes import announcements, events, me


def create_app(
    validator: TokenValidator | None = None,
    announcement_service: AnnouncementService | None = None,
) -> FastAPI:
    app = FastAPI(title="Employee App API")
    if validator is None:
        settings = load_settings()
        validator = TokenValidator(settings, JwksKeyProvider(settings.jwks_uri))
    app.state.token_validator = validator
    # In-memory stores until the Cosmos repositories land (ADR-007).
    app.state.announcement_service = announcement_service or AnnouncementService(
        SeedDirectory.from_file(), InMemoryAnnouncementStore(), InMemoryConfirmationStore()
    )
    app.state.event_sink = []  # TODO(EXP): replace with the events container (ADR-009)

    @app.exception_handler(ApiError)
    def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(me.router)
    app.include_router(announcements.router)
    app.include_router(events.router)
    return app


app = create_app()
