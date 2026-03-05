import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr


class UserCreate(BaseModel):
    """Schema for creating a new user.

    CRITICAL: company_id is intentionally excluded from this schema.
    It is derived from the TenantMiddleware ContextVar (set via X-Company-Id
    header) — never from the request body. Accepting company_id from clients
    would be a tenant isolation bypass vulnerability.
    """

    email: EmailStr
    first_name: str | None = None
    last_name: str | None = None
    phone: str | None = None


class UserResponse(BaseModel):
    """Schema for user API responses.

    Includes company_id (tenant scope), all profile fields, and assigned roles.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    company_id: uuid.UUID
    email: str
    first_name: str | None
    last_name: str | None
    phone: str | None
    version: int
    created_at: datetime
    updated_at: datetime
    roles: list[str] = []


class RoleAssignment(BaseModel):
    """Schema for assigning a role to a user within the current tenant company.

    The company_id is derived from TenantMiddleware — not from request body.
    The user_id is provided in the path parameter, but also accepted here
    for validation cross-referencing.
    """

    user_id: uuid.UUID
    role: Literal["admin", "contractor", "client"]


class UserRoleResponse(BaseModel):
    """Schema for user role API responses."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    company_id: uuid.UUID
    role: str
    created_at: datetime
