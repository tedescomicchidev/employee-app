from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.auth.errors import ApiError
from app.auth.validator import JwksKeyProvider, TokenValidator
from app.config import load_settings
from app.routes import me


def create_app(validator: TokenValidator | None = None) -> FastAPI:
    app = FastAPI(title="Employee App API")
    if validator is None:
        settings = load_settings()
        validator = TokenValidator(settings, JwksKeyProvider(settings.jwks_uri))
    app.state.token_validator = validator

    @app.exception_handler(ApiError)
    def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=exc.detail)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(me.router)
    return app


app = create_app()
