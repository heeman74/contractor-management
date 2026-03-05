"""Sync feature schemas — delta sync response models."""

from pydantic import BaseModel

from app.features.companies.schemas import CompanyResponse
from app.features.users.schemas import UserResponse, UserRoleResponse


class SyncResponse(BaseModel):
    """Response schema for GET /api/v1/sync delta endpoint.

    Contains all entities changed since the cursor timestamp, including
    tombstones (records with deleted_at set). The server_timestamp should
    be used as the cursor for the next sync request.
    """

    companies: list[CompanyResponse]
    users: list[UserResponse]
    user_roles: list[UserRoleResponse]
    server_timestamp: str  # ISO8601 — use as cursor for next sync
