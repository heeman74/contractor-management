import uuid
from typing import Literal

from pydantic import BaseModel, EmailStr, field_validator

from app.core.base_schemas import TenantResponseSchema


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


class UserResponse(TenantResponseSchema):
    """Schema for user API responses.

    Inherits id, version, created_at, updated_at, deleted_at, company_id
    from TenantResponseSchema.
    """

    email: str
    first_name: str | None
    last_name: str | None
    phone: str | None
    roles: list[str] = []

    @field_validator("roles", mode="before")
    @classmethod
    def extract_role_strings(cls, v):
        """Convert UserRole ORM objects to plain role strings."""
        if v and hasattr(v[0], "role"):
            return [r.role for r in v if getattr(r, "deleted_at", None) is None]
        return v


class RoleAssignment(BaseModel):
    """Schema for assigning a role to a user within the current tenant company.

    The company_id is derived from TenantMiddleware — not from request body.
    The user_id is provided in the path parameter, but also accepted here
    for validation cross-referencing.
    """

    user_id: uuid.UUID
    role: Literal["admin", "contractor", "client"]


class UserRoleResponse(TenantResponseSchema):
    """Schema for user role API responses.

    Inherits id, version, created_at, updated_at, deleted_at, company_id
    from TenantResponseSchema.
    """

    user_id: uuid.UUID
    role: str
