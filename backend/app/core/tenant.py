"""Tenant context management for multi-tenant RLS enforcement.

The tenant context is set by the get_current_user FastAPI dependency (security.py)
which extracts company_id from the JWT token. The TenantMiddleware is retained as
a reset mechanism to ensure the ContextVar is cleared between requests.

The SQLAlchemy after_begin event listener injects the tenant context into
PostgreSQL's RLS via SET LOCAL at the start of every transaction.
"""

from contextvars import ContextVar
from uuid import UUID

from sqlalchemy import event, text
from sqlalchemy.orm import Session
from starlette.types import Scope

from app.core.base_middleware import ASGIMiddleware

# Per-request context variable — automatically isolated per async task
_current_tenant_id: ContextVar[UUID | None] = ContextVar("current_tenant_id", default=None)


def get_current_tenant_id() -> UUID | None:
    """Return the current request's tenant ID from the ContextVar."""
    return _current_tenant_id.get()


def set_current_tenant_id(tenant_id: UUID) -> None:
    """Set the current request's tenant ID in the ContextVar."""
    _current_tenant_id.set(tenant_id)


class TenantMiddleware(ASGIMiddleware):
    """Pure ASGI middleware to reset tenant context between requests.

    The actual tenant ID is set by get_current_user (from JWT company_id claim).
    This middleware ensures the ContextVar is reset to None at the start of each
    request so that unauthenticated endpoints don't leak a previous tenant context.

    Uses pure ASGI interface instead of BaseHTTPMiddleware to avoid event loop
    issues in async test environments.
    """

    async def process_request(self, scope: Scope) -> None:
        if scope["type"] in ("http", "websocket"):
            _current_tenant_id.set(None)


# SQLAlchemy event: set RLS variable at the start of EVERY transaction
# CRITICAL: execute on the connection object (SQLAlchemy 2.0.17+ requirement)
# CRITICAL: use SET LOCAL (transaction-scoped), never SET (session-scoped)
@event.listens_for(Session, "after_begin")
def receive_after_begin(session, transaction, connection):
    """Inject tenant_id into PostgreSQL RLS context at transaction start."""
    tenant_id = get_current_tenant_id()
    if tenant_id is not None:
        # asyncpg does not support parameterized SET commands, so we use
        # string formatting. This is safe because tenant_id is a UUID from
        # our JWT decode, never from user input.
        connection.execute(
            text(f"SET LOCAL app.current_company_id = '{tenant_id}'"),
        )
