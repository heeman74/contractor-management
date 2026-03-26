"""Global exception handler -- catches unhandled exceptions and logs with full trace context.

Returns a clean 500 JSON response to clients while logging the full traceback
with request context for debugging.
"""

from __future__ import annotations

import json

from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException
from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.logging_config import get_logger
from app.core.trace_context import get_trace_context

logger = get_logger(__name__)


class ExceptionHandlerMiddleware:
    """Outermost ASGI middleware that catches unhandled exceptions.

    Follows the pure ASGI pattern. Lets HTTPException and RequestValidationError
    pass through to FastAPI's built-in handlers. All other exceptions are logged
    at ERROR level with full traceback and trace context, then a clean 500 JSON
    response is returned to the client.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        # Track whether response headers have already been sent
        response_started = False

        async def send_wrapper(message: dict) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        except (HTTPException, RequestValidationError):
            # Let FastAPI handle these natively
            raise
        except Exception:
            ctx = get_trace_context()
            request_id = ctx.get("request_id", "unknown")
            method = ctx.get("method", scope.get("method", ""))
            path = ctx.get("path", scope.get("path", ""))

            logger.error(
                "unhandled_exception",
                method=method,
                path=path,
                exc_info=True,
            )

            # Only send error response if headers haven't been sent yet
            if not response_started:
                body = json.dumps(
                    {
                        "detail": "Internal server error",
                        "request_id": request_id,
                    }
                ).encode("utf-8")

                await send(
                    {
                        "type": "http.response.start",
                        "status": 500,
                        "headers": [
                            (b"content-type", b"application/json"),
                            (b"content-length", str(len(body)).encode("utf-8")),
                            (b"x-request-id", request_id.encode("utf-8")),
                        ],
                    }
                )
                await send(
                    {
                        "type": "http.response.body",
                        "body": body,
                    }
                )
