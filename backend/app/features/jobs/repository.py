"""Repository for the job lifecycle domain.

Provides JobRepository(TenantScopedRepository[Job]) with:
- CRUD operations with eager-loaded relationships
- Filtered list with optional filters
- Full-text search via PostgreSQL tsvector/plainto_tsquery
- Bulk booking soft-delete on job cancellation (no N+1 loops)

All CLAUDE.md rules apply:
- No db.commit() — get_db handles transaction lifecycle
- No query inside a loop — use bulk UPDATE for booking cancellation
- Eager-load relationships on all queries (lazy="raise" on models)
- Inherit TenantScopedRepository per OOP architecture rules
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import func, select, update
from sqlalchemy.orm import selectinload

from app.core.base_repository import TenantScopedRepository
from app.features.jobs.models import Job


class JobRepository(TenantScopedRepository[Job]):
    """Repository for Job entities with full lifecycle support."""

    model = Job

    async def get_by_id(self, job_id: uuid.UUID) -> Job | None:
        """Retrieve a single job by ID with all relationships eager-loaded.

        Loads client, contractor, and bookings to prevent lazy-load errors
        (all relationships have lazy="raise").
        """
        result = await self.db.execute(
            select(Job)
            .where(Job.id == job_id)
            .where(Job.deleted_at.is_(None))
            .options(
                selectinload(Job.client),
                selectinload(Job.contractor),
                selectinload(Job.bookings),
            )
        )
        return result.scalars().first()

    async def list_jobs(
        self,
        *,
        status: str | None = None,
        contractor_id: uuid.UUID | None = None,
        client_id: uuid.UUID | None = None,
        trade_type: str | None = None,
        priority: str | None = None,
        offset: int = 0,
        limit: int = 50,
    ) -> list[Job]:
        """Filtered list of non-deleted jobs with client/contractor eager-loaded.

        All filters are optional. Results ordered by created_at DESC (newest first).
        """
        stmt = (
            select(Job)
            .where(Job.deleted_at.is_(None))
            .options(
                selectinload(Job.client),
                selectinload(Job.contractor),
            )
            .order_by(Job.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
        if status is not None:
            stmt = stmt.where(Job.status == status)
        if contractor_id is not None:
            stmt = stmt.where(Job.contractor_id == contractor_id)
        if client_id is not None:
            stmt = stmt.where(Job.client_id == client_id)
        if trade_type is not None:
            stmt = stmt.where(Job.trade_type == trade_type)
        if priority is not None:
            stmt = stmt.where(Job.priority == priority)

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def search_jobs(
        self,
        query: str,
        *,
        status: str | None = None,
        contractor_id: uuid.UUID | None = None,
        client_id: uuid.UUID | None = None,
        trade_type: str | None = None,
        priority: str | None = None,
    ) -> list[Job]:
        """Full-text search using PostgreSQL tsvector.

        Primary path: uses search_vector column with plainto_tsquery, ordered by
        ts_rank descending (most relevant first).

        Fallback: ILIKE on description for jobs created before the trigger ran
        (search_vector IS NULL). Both result sets are returned unioned via
        two separate queries merged in Python to avoid complex SQL.

        Eager-loads client and contractor (lazy="raise" requires this).
        """
        options = [
            selectinload(Job.client),
            selectinload(Job.contractor),
        ]
        base_filters: list[Any] = [Job.deleted_at.is_(None)]
        if status is not None:
            base_filters.append(Job.status == status)
        if contractor_id is not None:
            base_filters.append(Job.contractor_id == contractor_id)
        if client_id is not None:
            base_filters.append(Job.client_id == client_id)
        if trade_type is not None:
            base_filters.append(Job.trade_type == trade_type)
        if priority is not None:
            base_filters.append(Job.priority == priority)

        tsquery = func.plainto_tsquery("english", query)

        # Primary: full-text search on search_vector
        fts_column = func.to_tsvector("english", Job.description)
        fts_stmt = (
            select(Job)
            .where(*base_filters)
            .where(fts_column.op("@@")(tsquery))
            .options(*options)
            .order_by(func.ts_rank(fts_column, tsquery).desc())
        )
        fts_result = await self.db.execute(fts_stmt)
        fts_jobs = list(fts_result.scalars().all())

        # Fallback: ILIKE on description for jobs with NULL search_vector
        # (covers jobs inserted before the DB trigger was created)
        ilike_stmt = (
            select(Job)
            .where(*base_filters)
            .where(Job.description.ilike(f"%{query}%"))
            .options(*options)
        )
        ilike_result = await self.db.execute(ilike_stmt)
        ilike_jobs = list(ilike_result.scalars().all())

        # Merge: FTS results first, then ILIKE-only results (deduplicate by id)
        seen_ids: set[uuid.UUID] = {j.id for j in fts_jobs}
        fallback = [j for j in ilike_jobs if j.id not in seen_ids]
        return fts_jobs + fallback

    async def cancel_job_bookings(self, job_id: uuid.UUID) -> None:
        """Bulk soft-delete all active bookings for a job.

        Uses a single UPDATE statement — NOT a loop — per CLAUDE.md N+1 rules
        and RESEARCH.md Pitfall 4. This frees scheduling slots atomically.
        """
        stmt = (
            update(self._booking_model())
            .where(self._booking_model().job_id == job_id)
            .where(self._booking_model().deleted_at.is_(None))
            .values(deleted_at=datetime.now(UTC))
        )
        await self.db.execute(stmt)

    def _booking_model(self):  # type: ignore[return]
        """Lazy import of Booking model to avoid circular imports at module load."""
        from app.features.scheduling.models import Booking

        return Booking

    async def get_jobs_for_client(self, client_id: uuid.UUID) -> list[Job]:
        """All non-deleted jobs for a specific client with contractor eager-loaded.

        Used for CRM job history view.
        """
        result = await self.db.execute(
            select(Job)
            .where(Job.client_id == client_id)
            .where(Job.deleted_at.is_(None))
            .options(selectinload(Job.contractor))
            .order_by(Job.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_jobs_for_contractor(self, contractor_id: uuid.UUID) -> list[Job]:
        """All non-deleted jobs assigned to a contractor with client eager-loaded.

        Used for contractor job list view.
        """
        result = await self.db.execute(
            select(Job)
            .where(Job.contractor_id == contractor_id)
            .where(Job.deleted_at.is_(None))
            .options(selectinload(Job.client))
            .order_by(Job.created_at.desc())
        )
        return list(result.scalars().all())
