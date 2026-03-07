"""Sync service — multi-table delta query for offline sync.

Each method returns all records changed since a given cursor timestamp.
Records are included if updated_at > since OR deleted_at > since, ensuring
tombstones (soft-deleted records) are propagated to offline clients.

CRITICAL: RLS is automatically enforced via TenantMiddleware ContextVar,
so all queries are automatically scoped to the current tenant. No explicit
company_id WHERE clause is needed.
"""

from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.features.companies.models import Company
from app.features.users.models import User, UserRole


class SyncService:
    """Delta sync service for offline-first clients."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def get_companies_since(self, since: datetime) -> list[Company]:
        """Return all companies changed since the given cursor timestamp.

        Includes both active records (updated_at > since) and tombstones
        (deleted_at > since) for correct offline tombstone propagation.

        Note: companies table has no RLS — all tenants see all companies.
        This is intentional: companies are the tenant root, not scoped by it.
        """
        result = await self.db.execute(
            select(Company).where(or_(Company.updated_at > since, Company.deleted_at > since))
        )
        return list(result.scalars().all())

    async def get_users_since(self, since: datetime) -> list[User]:
        """Return all users changed since the given cursor timestamp.

        Includes both active records (updated_at > since) and tombstones
        (deleted_at > since). RLS automatically restricts to current tenant.
        """
        result = await self.db.execute(
            select(User)
            .where(or_(User.updated_at > since, User.deleted_at > since))
            .options(selectinload(User.roles))
        )
        return list(result.scalars().all())

    async def get_user_roles_since(self, since: datetime) -> list[UserRole]:
        """Return all user roles changed since the given cursor timestamp.

        Includes both active records (updated_at > since) and tombstones
        (deleted_at > since). RLS automatically restricts to current tenant.
        """
        result = await self.db.execute(
            select(UserRole).where(or_(UserRole.updated_at > since, UserRole.deleted_at > since))
        )
        return list(result.scalars().all())
