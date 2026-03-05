from contextvars import ContextVar
from uuid import UUID

from fastapi import Request
from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.middleware.base import BaseHTTPMiddleware

# Per-request context variable — automatically isolated per async task
_current_tenant_id: ContextVar[UUID | None] = ContextVar(
    "current_tenant_id", default=None
)


def get_current_tenant_id() -> UUID | None:
    """Return the current request's tenant ID from the ContextVar."""
    return _current_tenant_id.get()


def set_current_tenant_id(tenant_id: UUID) -> None:
    """Set the current request's tenant ID in the ContextVar."""
    _current_tenant_id.set(tenant_id)


class TenantMiddleware(BaseHTTPMiddleware):
    """Extract tenant ID from X-Company-Id header and set ContextVar.

    Phase 1 stub: reads tenant from header directly.
    Phase 2 (auth): will decode JWT and extract company_id claim.
    """

    async def dispatch(self, request: Request, call_next):
        company_id_str = request.headers.get("X-Company-Id")
        if company_id_str:
            try:
                set_current_tenant_id(UUID(company_id_str))
            except ValueError:
                # Invalid UUID — ignore and proceed without tenant context
                pass
        return await call_next(request)


# SQLAlchemy event: set RLS variable at the start of EVERY transaction
# CRITICAL: execute on the connection object (SQLAlchemy 2.0.17+ requirement)
# CRITICAL: use SET LOCAL (transaction-scoped), never SET (session-scoped)
@event.listens_for(AsyncSession, "after_begin")
async def receive_after_begin(session, transaction, connection):
    """Inject tenant_id into PostgreSQL RLS context at transaction start."""
    tenant_id = get_current_tenant_id()
    if tenant_id is not None:
        await connection.execute(
            text("SET LOCAL app.current_company_id = :cid"),
            {"cid": str(tenant_id)},
        )
