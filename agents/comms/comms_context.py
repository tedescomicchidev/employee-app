"""Per-request context forwarded by api/ (ADR-002, application-managed OBO).

api/ calls this agent with `x-client-api-access-token` (the OBO token for the tools resource app) and
`x-client-task-run-id`. Foundry forwards `x-client-*` headers to the container but does not exchange
or interpret them. They are captured here, outside the model: the token goes only into the Authorization
header of the call to api/'s /mcp, never into a prompt, a tool argument or a log line.
"""

from contextvars import ContextVar

from starlette.types import ASGIApp, Receive, Scope, Send

TOOLS_TOKEN_HEADER = b"x-client-api-access-token"
TASK_RUN_HEADER = b"x-client-task-run-id"

_tools_token: ContextVar[str | None] = ContextVar("tools_token", default=None)
_task_run_id: ContextVar[str | None] = ContextVar("task_run_id", default=None)


class MissingToolsToken(RuntimeError):
    """The request carried no tools token, so the agent cannot act as the user. Fails closed."""


def tools_token() -> str:
    token = _tools_token.get()
    if not token:
        raise MissingToolsToken("no x-client-api-access-token on this request")
    return token


def task_run_id() -> str | None:
    return _task_run_id.get()


class ForwardedContextMiddleware:
    """Pure ASGI, so the context variables are set in the task that serves the request."""

    def __init__(self, app: ASGIApp) -> None:
        self._app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self._app(scope, receive, send)
            return
        headers = {k.lower(): v for k, v in scope.get("headers", [])}
        token = headers.get(TOOLS_TOKEN_HEADER, b"").decode("latin-1").strip() or None
        run_id = headers.get(TASK_RUN_HEADER, b"").decode("latin-1").strip() or None
        t1, t2 = _tools_token.set(token), _task_run_id.set(run_id)
        try:
            await self._app(scope, receive, send)
        finally:
            _tools_token.reset(t1)
            _task_run_id.reset(t2)
