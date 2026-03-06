"""Sync API router — delta sync endpoint for offline-first clients.

Endpoints:
  GET /api/v1/sync?cursor=<ISO8601>  — return all entities changed since cursor

The cursor parameter is an ISO8601 timestamp. If omitted or empty string,
defaults to 2000-01-01T00:00:00Z, returning ALL records (full initial download).

RLS is enforced automatically by TenantMiddleware: only the current tenant's
users and user_roles are returned. Companies table has no RLS by design.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
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
    cursor: str | None = Query(
        default=None,
        description="ISO8601 timestamp. Returns records changed after this time. "
                    "Omit or pass empty string for full download (first launch).",
    ),
    db: AsyncSession = Depends(get_db),
) -> SyncResponse:
    """Return all entities changed since the cursor timestamp.

    Includes tombstones (records with deleted_at set) so offline clients
    can delete locally-cached records that were soft-deleted on the server.

    The returned server_timestamp should be stored and used as the cursor
    for the next sync request to avoid re-fetching unchanged records.

    Cursor handling:
      - Absent (no cursor param): defaults to epoch — full download
      - Empty string (?cursor=): treated as epoch — full download
      - Valid ISO8601 string: parsed to datetime — delta sync from that point
      - Invalid non-empty string: returns 422 with descriptive error
    """
    if cursor is None or cursor.strip() == "":
        since = _EPOCH_START
    else:
        try:
            since = datetime.fromisoformat(cursor)
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail=f"Invalid cursor format: '{cursor}'. Expected ISO8601 datetime.",
            )

    companies = await service.get_companies_since(db, since)
    users = await service.get_users_since(db, since)
    user_roles = await service.get_user_roles_since(db, since)

    return SyncResponse(
        companies=[CompanyResponse.model_validate(c) for c in companies],
        users=[UserResponse.model_validate(u) for u in users],
        user_roles=[UserRoleResponse.model_validate(r) for r in user_roles],
        server_timestamp=datetime.now(timezone.utc).isoformat(),
    )
