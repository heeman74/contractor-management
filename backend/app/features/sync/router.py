"""Sync API router — delta sync endpoint for offline-first clients.

Endpoints:
  GET /api/v1/sync?cursor=<ISO8601>  — return all entities changed since cursor

The cursor parameter is an ISO8601 timestamp. If omitted, defaults to
2000-01-01T00:00:00Z, returning ALL records (full initial download).

RLS is enforced automatically by TenantMiddleware: only the current tenant's
users and user_roles are returned. Companies table has no RLS by design.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.features.sync import service
from app.features.sync.schemas import SyncResponse
from app.features.companies.schemas import CompanyResponse
from app.features.users.schemas import UserResponse, UserRoleResponse

router = APIRouter(prefix="/sync", tags=["sync"])

# Default cursor: epoch start — returns all records on first-launch full download
_EPOCH_START = datetime(2000, 1, 1, tzinfo=timezone.utc)


@router.get("", response_model=SyncResponse)
async def delta_sync(
    cursor: datetime | None = Query(
        default=None,
        description="ISO8601 timestamp. Returns records changed after this time. "
                    "Omit for full download (first launch).",
    ),
    db: AsyncSession = Depends(get_db),
) -> SyncResponse:
    """Return all entities changed since the cursor timestamp.

    Includes tombstones (records with deleted_at set) so offline clients
    can delete locally-cached records that were soft-deleted on the server.

    The returned server_timestamp should be stored and used as the cursor
    for the next sync request to avoid re-fetching unchanged records.
    """
    since = cursor if cursor is not None else _EPOCH_START

    companies = await service.get_companies_since(db, since)
    users = await service.get_users_since(db, since)
    user_roles = await service.get_user_roles_since(db, since)

    return SyncResponse(
        companies=[CompanyResponse.model_validate(c) for c in companies],
        users=[UserResponse.model_validate(u) for u in users],
        user_roles=[UserRoleResponse.model_validate(r) for r in user_roles],
        server_timestamp=datetime.now(timezone.utc).isoformat(),
    )
