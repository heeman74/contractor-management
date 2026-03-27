"""Request logging middleware -- logs every HTTP request with timing and trace context.

Generates a unique request_id (UUID4) per request, sets it in trace context,
includes it in response headers (X-Request-ID), and logs request start/completion.
"""

from __future__ import annotations

import time
import uuid

from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.logging_config import get_logger
from app.core.trace_context import clear_trace_context, set_trace_context

logger = get_logger(__name__)

# Paths to skip logging (health checks, docs, OpenAPI spec)
_SKIP_PATHS: frozenset[str] = frozenset(
    {
        "/health",
        "/docs",
        "/redoc",
        "/openapi.json",
    }
)

SLOW_REQUEST_THRESHOLD_MS = 1000


class RequestLoggingMiddleware:
    """Pure ASGI middleware that logs HTTP requests with timing and trace context.

    Follows the same ASGI pattern as ASGIMiddleware in base_middleware.py but
    implemented directly (not subclassed) because we need to wrap the entire
    call lifecycle including exception handling in the finally block.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        path = scope.get("path", "")

        # Skip noisy endpoints
        if path in _SKIP_PATHS:
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "")
        headers = dict(scope.get("headers", []))

        # Use incoming X-Request-ID if present (distributed tracing), else generate
        request_id = headers.get(b"x-request-id", b"").decode("utf-8", errors="replace") or str(
            uuid.uuid4()
        )

        # Extract client IP
        client = scope.get("client")
        client_ip = client[0] if client else "unknown"

        start_time = time.monotonic()

        # Set trace context for this request
        set_trace_context(
            request_id=request_id,
            method=method,
            path=path,
            start_time=start_time,
        )

        logger.info(
            "request_started",
            method=method,
            path=path,
            client_ip=client_ip,
        )

        # Capture the response status code from the response.start message
        status_code = 500  # Default if we never see a response

        async def send_with_request_id(message: dict) -> None:
            nonlocal status_code

            if message["type"] == "http.response.start":
                status_code = message.get("status", 500)
                # Inject X-Request-ID into response headers
                extra_headers = [
                    (b"x-request-id", request_id.encode("utf-8")),
                ]
                message = {
                    **message,
                    "headers": list(message.get("headers", [])) + extra_headers,
                }

            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        finally:
            duration_ms = round((time.monotonic() - start_time) * 1000, 2)

            log_kwargs = {
                "method": method,
                "path": path,
                "status_code": status_code,
                "duration_ms": duration_ms,
            }

            if duration_ms > SLOW_REQUEST_THRESHOLD_MS:
                logger.warning("request_slow", **log_kwargs)
            else:
                logger.info("request_completed", **log_kwargs)

            clear_trace_context()
