"""Base pure-ASGI middleware — avoids BaseHTTPMiddleware event loop issues.

All new middleware MUST inherit from ASGIMiddleware and override
process_request() and/or process_response() instead of using
Starlette's BaseHTTPMiddleware.
"""

from starlette.types import ASGIApp, Receive, Scope, Send


class ASGIMiddleware:
    """Base pure-ASGI middleware with override points for request/response."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        await self.process_request(scope)
        send = await self.process_response(scope, send)
        await self.app(scope, receive, send)

    async def process_request(self, scope: Scope) -> None:
        """Override to process the request before passing to the inner app."""

    async def process_response(self, scope: Scope, send: Send) -> Send:
        """Override to wrap the send callable for response modification."""
        return send
