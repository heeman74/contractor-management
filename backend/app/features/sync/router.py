"""Sync API router — delta sync endpoint for offline-first clients.

Endpoints:
  GET /api/v1/sync?cursor=<ISO8601>  — return all entities changed since cursor

The cursor parameter is an ISO8601 timestamp. If omitted or empty string,
defaults to 2000-01-01T00:00:00Z, returning ALL records (full initial download).

RLS is enforced via JWT: company_id is extracted from the token by
get_current_user dependency, which sets the tenant context for RLS filtering.
"""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.companies.schemas import CompanyResponse
from app.features.sync.schemas import SyncResponse
from app.features.sync.service import SyncService
from app.features.users.schemas import UserResponse, UserRoleResponse

router = APIRouter(prefix="/sync", tags=["sync"])

# Default cursor: epoch start — returns all records on first-launch full download
_EPOCH_START = datetime(2000, 1, 1, tzinfo=UTC)


@router.get("", response_model=SyncResponse)
async def delta_sync(
    cursor: str | None = Query(
        default=None,
        description="ISO8601 timestamp. Returns records changed after this time. "
        "Omit or pass empty string for full download (first launch).",
    ),
    db: AsyncSession = Depends(get_db),
    _current_user: CurrentUser = Depends(get_current_user),
) -> SyncResponse:
    """Return all entities changed since the cursor timestamp.

    Includes tombstones (records with deleted_at set) so offline clients
    can delete locally-cached records that were soft-deleted on the server.
    """
    if cursor is None or cursor.strip() == "":
        since = _EPOCH_START
    else:
        try:
            # URL query params decode '+' as space; restore for ISO8601 tz offset
            since = datetime.fromisoformat(cursor.replace(" ", "+"))
        except ValueError as exc:
            raise HTTPException(
                status_code=422,
                detail=f"Invalid cursor format: '{cursor}'. Expected ISO8601 datetime.",
            ) from exc

    svc = SyncService(db)
    companies = await svc.get_companies_since(since)
    users = await svc.get_users_since(since)
    user_roles = await svc.get_user_roles_since(since)

    return SyncResponse(
        companies=[CompanyResponse.model_validate(c) for c in companies],
        users=[UserResponse.model_validate(u) for u in users],
        user_roles=[UserRoleResponse.model_validate(r) for r in user_roles],
        server_timestamp=datetime.now(UTC).isoformat(),
    )
