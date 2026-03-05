"""Sync service — multi-table delta query for offline sync.

Each function returns all records changed since a given cursor timestamp.
Records are included if updated_at > since OR deleted_at > since, ensuring
tombstones (soft-deleted records) are propagated to offline clients.

CRITICAL: RLS is automatically enforced via TenantMiddleware ContextVar,
so all queries are automatically scoped to the current tenant. No explicit
company_id WHERE clause is needed.
"""

from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.companies.models import Company
from app.features.users.models import User, UserRole


async def get_companies_since(
    db: AsyncSession, since: datetime
) -> list[Company]:
    """Return all companies changed since the given cursor timestamp.

    Includes both active records (updated_at > since) and tombstones
    (deleted_at > since) for correct offline tombstone propagation.

    Note: companies table has no RLS — all tenants see all companies.
    This is intentional: companies are the tenant root, not scoped by it.
    """
    result = await db.execute(
        select(Company).where(
            or_(Company.updated_at > since, Company.deleted_at > since)
        )
    )
    return list(result.scalars().all())


async def get_users_since(db: AsyncSession, since: datetime) -> list[User]:
    """Return all users changed since the given cursor timestamp.

    Includes both active records (updated_at > since) and tombstones
    (deleted_at > since). RLS automatically restricts to current tenant.
    """
    result = await db.execute(
        select(User).where(
            or_(User.updated_at > since, User.deleted_at > since)
        )
    )
    return list(result.scalars().all())


async def get_user_roles_since(
    db: AsyncSession, since: datetime
) -> list[UserRole]:
    """Return all user roles changed since the given cursor timestamp.

    Includes both active records (updated_at > since) and tombstones
    (deleted_at > since). RLS automatically restricts to current tenant.
    """
    result = await db.execute(
        select(UserRole).where(
            or_(UserRole.updated_at > since, UserRole.deleted_at > since)
        )
    )
    return list(result.scalars().all())
