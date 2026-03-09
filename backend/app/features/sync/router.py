"""Sync API router — delta sync endpoint for offline-first clients.

Endpoints:
  GET /api/v1/sync?cursor=<ISO8601>  — return all entities changed since cursor

The cursor parameter is an ISO8601 timestamp. If omitted or empty string,
defaults to 2000-01-01T00:00:00Z, returning ALL records (full initial download).

RLS is enforced via JWT: company_id is extracted from the token by
get_current_user dependency, which sets the tenant context for RLS filtering.

Phase 4 additions: the sync response now includes jobs, client_profiles, and
job_requests alongside existing entity types. The delta sync cursor applies
equally to all entity types — a single high-water mark timestamp covers all.
"""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.companies.schemas import CompanyResponse
from app.features.jobs.schemas import ClientProfileResponse, JobRequestResponse, JobResponse
from app.features.scheduling.schemas import BookingResponse

# isort: split
# Scheduling models must be registered before job models are resolved (same pattern as jobs/router.py)
import app.features.scheduling.models  # noqa: F401

# isort: split
from app.features.sync.schemas import JobSiteResponse, SyncResponse
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

    Phase 4: also returns jobs, client_profiles, and job_requests changed
    since the cursor — same single high-water mark applies to all entity types.
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
    # Phase 4 entities
    jobs = await svc.get_jobs_since(since)
    client_profiles = await svc.get_client_profiles_since(since)
    job_requests = await svc.get_job_requests_since(since)
    # Phase 5 entities — calendar & dispatch
    bookings = await svc.get_bookings_since(since)
    job_sites = await svc.get_job_sites_since(since)

    return SyncResponse(
        companies=[CompanyResponse.model_validate(c) for c in companies],
        users=[UserResponse.model_validate(u) for u in users],
        user_roles=[UserRoleResponse.model_validate(r) for r in user_roles],
        jobs=[JobResponse.model_validate(j) for j in jobs],
        client_profiles=[ClientProfileResponse.model_validate(p) for p in client_profiles],
        job_requests=[JobRequestResponse.model_validate(r) for r in job_requests],
        bookings=[BookingResponse.model_validate(b) for b in bookings],
        job_sites=[JobSiteResponse.model_validate(s) for s in job_sites],
        server_timestamp=datetime.now(UTC).isoformat(),
    )
