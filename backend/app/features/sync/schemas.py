"""Sync feature schemas — delta sync response models."""

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel

from app.features.companies.schemas import CompanyResponse
from app.features.jobs.schemas import ClientProfileResponse, JobRequestResponse, JobResponse
from app.features.users.schemas import UserResponse, UserRoleResponse


class JobSiteResponse(BaseModel):
    """Sync response schema for a JobSite record.

    Minimal schema for the sync pull payload — populates the local job_sites
    Drift table on mobile. Lat/lng serialized as Decimal (matches Numeric(9,6)
    on the backend) and are None when geocoding has not yet resolved the address.
    """

    model_config = {"from_attributes": True}

    id: uuid.UUID
    company_id: uuid.UUID
    address: str
    latitude: Decimal | None = None
    longitude: Decimal | None = None
    name: str | None = None
    version: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None


# Scheduling schemas are imported after the models are registered in router.py.
# We cannot import BookingResponse at module level because the scheduling models
# may not yet be in the mapper registry when this module is first loaded.
# The router handles the side-effect import before calling SyncService.
# For schema definitions, we use a local import inside the class body via a
# forward declaration approach — use TYPE_CHECKING guard at module level.
from app.features.scheduling.schemas import BookingResponse  # noqa: E402


class SyncResponse(BaseModel):
    """Response schema for GET /api/v1/sync delta endpoint.

    Contains all entities changed since the cursor timestamp, including
    tombstones (records with deleted_at set). The server_timestamp should
    be used as the cursor for the next sync request.

    Phase 4 additions — jobs, client_profiles, job_requests — default to empty
    list so existing clients without Phase 4 still parse the response correctly.
    Phase 5 additions — bookings, job_sites — default to empty list for
    backwards compatibility with Phase 4 clients.
    """

    companies: list[CompanyResponse]
    users: list[UserResponse]
    user_roles: list[UserRoleResponse]
    # Phase 4 — job lifecycle entities (default empty for backwards compatibility)
    jobs: list[JobResponse] = []
    client_profiles: list[ClientProfileResponse] = []
    job_requests: list[JobRequestResponse] = []
    # Phase 5 — calendar & dispatch entities (default empty for backwards compatibility)
    bookings: list[BookingResponse] = []
    job_sites: list[JobSiteResponse] = []
    server_timestamp: str  # ISO8601 — use as cursor for next sync
