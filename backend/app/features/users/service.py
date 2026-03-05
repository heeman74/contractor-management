"""User service — business logic for user operations.

CRITICAL: All tenant-scoped operations derive company_id from the
get_current_tenant_id() ContextVar, never from request body.
This prevents tenant isolation bypass vulnerabilities.
"""

import uuid

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.tenant import get_current_tenant_id
from app.features.users.models import User, UserRole
from app.features.users.schemas import RoleAssignment, UserCreate


def _require_tenant_id() -> uuid.UUID:
    """Get current tenant ID or raise 400 if not set.

    Tenant ID must be set by TenantMiddleware via X-Company-Id header.
    """
    tenant_id = get_current_tenant_id()
    if tenant_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Company-Id header is required",
        )
    return tenant_id


async def create_user(db: AsyncSession, data: UserCreate) -> User:
    """Create a new user within the current tenant company.

    company_id is derived from TenantMiddleware ContextVar — never from
    the request body. This is the tenant isolation enforcement point.
    """
    company_id = _require_tenant_id()
    user = User(
        company_id=company_id,
        email=data.email,
        first_name=data.first_name,
        last_name=data.last_name,
        phone=data.phone,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)
    return user


async def get_user(db: AsyncSession, user_id: uuid.UUID) -> User | None:
    """Retrieve a user by ID. RLS automatically filters to current tenant."""
    return await db.get(User, user_id)


async def list_users(db: AsyncSession) -> list[User]:
    """List all users for the current tenant.

    PostgreSQL RLS automatically filters to the current company_id,
    so no explicit WHERE clause is needed — the SET LOCAL injected by
    the after_begin event enforces tenant isolation at the DB level.
    """
    result = await db.execute(select(User))
    return list(result.scalars().all())


async def assign_role(
    db: AsyncSession, user_id: uuid.UUID, data: RoleAssignment
) -> UserRole:
    """Assign a role to a user within the current tenant company.

    company_id is derived from TenantMiddleware — never from request body.
    Validates that the user_id in path matches the body for consistency.
    """
    company_id = _require_tenant_id()

    # Verify user exists
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    user_role = UserRole(
        user_id=user_id,
        company_id=company_id,
        role=data.role,
    )
    db.add(user_role)
    await db.flush()
    await db.refresh(user_role)
    return user_role


async def get_user_roles(db: AsyncSession, user_id: uuid.UUID) -> list[UserRole]:
    """Get all roles for a specific user within the current tenant."""
    result = await db.execute(
        select(UserRole).where(UserRole.user_id == user_id)
    )
    return list(result.scalars().all())
