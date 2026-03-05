"""Users API router.

Endpoints:
  POST   /api/v1/users/                  — create user (company_id from middleware)
  GET    /api/v1/users/                  — list users (RLS-filtered to tenant)
  POST   /api/v1/users/{user_id}/roles   — assign role to user
  GET    /api/v1/users/{user_id}/roles   — get user's roles

CRITICAL: X-Company-Id header required for all endpoints.
The TenantMiddleware reads this header and sets the ContextVar that
drives both RLS (via after_begin event) and explicit company_id
assignments in service functions.
"""

import uuid

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.features.users import service
from app.features.users.schemas import (
    RoleAssignment,
    UserCreate,
    UserResponse,
    UserRoleResponse,
)

router = APIRouter(prefix="/users", tags=["users"])


@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    data: UserCreate,
    db: AsyncSession = Depends(get_db),
) -> UserResponse:
    """Create a new user scoped to the current tenant.

    Requires X-Company-Id header. company_id is set by TenantMiddleware —
    never by request body.
    """
    user = await service.create_user(db, data)
    return UserResponse.model_validate(user)


@router.get("/", response_model=list[UserResponse])
async def list_users(
    db: AsyncSession = Depends(get_db),
) -> list[UserResponse]:
    """List all users for the current tenant (RLS-filtered).

    Requires X-Company-Id header. PostgreSQL RLS automatically restricts
    results to the current company — no explicit WHERE clause needed.
    """
    users = await service.list_users(db)
    return [UserResponse.model_validate(u) for u in users]


@router.post(
    "/{user_id}/roles",
    response_model=UserRoleResponse,
    status_code=status.HTTP_201_CREATED,
)
async def assign_role(
    user_id: uuid.UUID,
    data: RoleAssignment,
    db: AsyncSession = Depends(get_db),
) -> UserRoleResponse:
    """Assign a role to a user within the current tenant company.

    Supports all three role types: admin, contractor, client.
    Requires X-Company-Id header.
    """
    user_role = await service.assign_role(db, user_id, data)
    return UserRoleResponse.model_validate(user_role)


@router.get("/{user_id}/roles", response_model=list[UserRoleResponse])
async def get_user_roles(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> list[UserRoleResponse]:
    """Get all roles for a specific user within the current tenant."""
    roles = await service.get_user_roles(db, user_id)
    return [UserRoleResponse.model_validate(r) for r in roles]
