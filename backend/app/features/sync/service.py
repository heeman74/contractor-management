"""Sync service — multi-table delta query for offline sync.

Each method returns all records changed since a given cursor timestamp.
Records are included if updated_at > since OR deleted_at > since, ensuring
tombstones (soft-deleted records) are propagated to offline clients.

CRITICAL: RLS is automatically enforced via TenantMiddleware ContextVar,
so all queries are automatically scoped to the current tenant. No explicit
company_id WHERE clause is needed (except get_companies_since — companies
table has no RLS).

Phase 4 additions:
  - get_jobs_since: delta sync for Job records (eager-loads client, contractor)
  - get_client_profiles_since: delta sync for ClientProfile records
  - get_job_requests_since: delta sync for JobRequest records
"""

from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload

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

    # -------------------------------------------------------------------------
    # Phase 4 — job lifecycle entity sync methods
    # -------------------------------------------------------------------------

    async def get_jobs_since(self, since: datetime) -> list:
        """Return all jobs changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        Eager-loads client (many-to-one) and contractor (many-to-one) via
        joinedload to prevent N+1 queries per CLAUDE.md rules.

        RLS automatically restricts to the current tenant's company_id.
        """
        from app.features.jobs.models import Job

        result = await self.db.execute(
            select(Job)
            .where(or_(Job.updated_at > since, Job.deleted_at > since))
            .options(
                joinedload(Job.client),
                joinedload(Job.contractor),
            )
        )
        return list(result.scalars().unique().all())

    async def get_client_profiles_since(self, since: datetime) -> list:
        """Return all client profiles changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.
        """
        from app.features.jobs.models import ClientProfile

        result = await self.db.execute(
            select(ClientProfile).where(
                or_(ClientProfile.updated_at > since, ClientProfile.deleted_at > since)
            )
        )
        return list(result.scalars().all())

    async def get_job_requests_since(self, since: datetime) -> list:
        """Return all job requests changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.
        """
        from app.features.jobs.models import JobRequest

        result = await self.db.execute(
            select(JobRequest).where(
                or_(JobRequest.updated_at > since, JobRequest.deleted_at > since)
            )
        )
        return list(result.scalars().all())
