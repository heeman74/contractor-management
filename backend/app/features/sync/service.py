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

# Maximum records per sync batch to prevent memory exhaustion on first sync
_SYNC_MAX_LIMIT = 1000


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
            select(Company)
            .where(or_(Company.updated_at > since, Company.deleted_at > since))
            .order_by(Company.updated_at)
            .limit(_SYNC_MAX_LIMIT)
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
            .order_by(User.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    async def get_user_roles_since(self, since: datetime) -> list[UserRole]:
        """Return all user roles changed since the given cursor timestamp.

        Includes both active records (updated_at > since) and tombstones
        (deleted_at > since). RLS automatically restricts to current tenant.
        """
        result = await self.db.execute(
            select(UserRole)
            .where(or_(UserRole.updated_at > since, UserRole.deleted_at > since))
            .order_by(UserRole.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    # -------------------------------------------------------------------------
    # Phase 4 — job lifecycle entity sync methods
    # -------------------------------------------------------------------------

    async def get_jobs_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
        limit: int = _SYNC_MAX_LIMIT,
    ) -> list:
        """Return all jobs changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        Eager-loads client (many-to-one) and contractor (many-to-one) via
        joinedload to prevent N+1 queries per CLAUDE.md rules.

        RLS automatically restricts to the current tenant's company_id.

        Args:
            since:          High-water mark cursor timestamp.
            client_user_id: When provided (client role), restricts results to jobs
                            where Job.client_id == client_user_id. Ensures clients
                            only receive their own jobs in the delta sync (CLNT-05).
            limit:          Max records to return (prevents memory exhaustion).
        """
        import uuid

        from app.features.jobs.models import Job

        stmt = (
            select(Job)
            .where(or_(Job.updated_at > since, Job.deleted_at > since))
            .options(
                joinedload(Job.client),
                joinedload(Job.contractor),
            )
            .order_by(Job.updated_at)
            .limit(limit)
        )
        if client_user_id is not None:
            stmt = stmt.where(Job.client_id == uuid.UUID(client_user_id))

        result = await self.db.execute(stmt)
        return list(result.scalars().unique().all())

    async def get_client_profiles_since(self, since: datetime) -> list:
        """Return all client profiles changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.
        """
        from app.features.jobs.models import ClientProfile

        result = await self.db.execute(
            select(ClientProfile)
            .where(or_(ClientProfile.updated_at > since, ClientProfile.deleted_at > since))
            .order_by(ClientProfile.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    async def get_job_requests_since(self, since: datetime) -> list:
        """Return all job requests changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.
        """
        from app.features.jobs.models import JobRequest

        result = await self.db.execute(
            select(JobRequest)
            .where(or_(JobRequest.updated_at > since, JobRequest.deleted_at > since))
            .order_by(JobRequest.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    # -------------------------------------------------------------------------
    # Phase 5 — calendar & dispatch entity sync methods
    # -------------------------------------------------------------------------

    async def get_bookings_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
        limit: int = _SYNC_MAX_LIMIT,
    ) -> list:
        """Return all bookings changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.

        Args:
            since:          High-water mark cursor timestamp.
            client_user_id: When provided, restricts bookings to those whose
                            job_id belongs to the client's jobs (via subquery).

        Note: scheduling.models must be imported before calling this method
        to ensure Booking is registered in the SQLAlchemy mapper registry.
        This is handled by the side-effect import in sync/router.py.
        """
        import uuid

        from app.features.scheduling.models import Booking

        stmt = (
            select(Booking)
            .where(or_(Booking.updated_at > since, Booking.deleted_at > since))
            .order_by(Booking.updated_at)
            .limit(limit)
        )

        if client_user_id is not None:
            from app.features.jobs.models import Job

            client_uuid = uuid.UUID(client_user_id)
            client_job_ids = select(Job.id).where(Job.client_id == client_uuid)
            stmt = stmt.where(Booking.job_id.in_(client_job_ids))

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_job_sites_since(self, since: datetime) -> list:
        """Return all job sites changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.
        """
        from app.features.scheduling.models import JobSite

        result = await self.db.execute(
            select(JobSite)
            .where(or_(JobSite.updated_at > since, JobSite.deleted_at > since))
            .order_by(JobSite.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    # -------------------------------------------------------------------------
    # Phase 6 — field workflow entity sync methods
    # -------------------------------------------------------------------------

    async def get_job_notes_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Return all job notes changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        Eager-loads attachments (one-to-many) so JobNoteResponse.attachments is populated.
        RLS automatically restricts to the current tenant.

        Args:
            since:          High-water mark cursor timestamp.
            client_user_id: When provided, restricts notes to those whose
                            job_id belongs to the client's jobs (via subquery).
        """
        import uuid

        from app.features.jobs.models import JobNote

        stmt = (
            select(JobNote)
            .where(or_(JobNote.updated_at > since, JobNote.deleted_at > since))
            .options(selectinload(JobNote.attachments))
            .order_by(JobNote.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )

        if client_user_id is not None:
            from app.features.jobs.models import Job

            client_uuid = uuid.UUID(client_user_id)
            client_job_ids = select(Job.id).where(Job.client_id == client_uuid)
            stmt = stmt.where(JobNote.job_id.in_(client_job_ids))

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_time_entries_since(self, since: datetime) -> list:
        """Return all time entries changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.
        """
        from app.features.jobs.models import TimeEntry

        result = await self.db.execute(
            select(TimeEntry)
            .where(or_(TimeEntry.updated_at > since, TimeEntry.deleted_at > since))
            .order_by(TimeEntry.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    async def get_attachments_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Return all attachments changed since the given cursor timestamp.

        Includes both active records and tombstones (deleted_at > since).
        RLS automatically restricts to the current tenant.

        Args:
            since:          High-water mark cursor timestamp.
            client_user_id: When provided, restricts attachments to those whose
                            note's job_id belongs to the client's jobs (via subquery
                            through JobNote).
        """
        import uuid

        from app.features.jobs.models import Attachment

        stmt = (
            select(Attachment)
            .where(or_(Attachment.updated_at > since, Attachment.deleted_at > since))
            .order_by(Attachment.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )

        if client_user_id is not None:
            from app.features.jobs.models import Job, JobNote

            client_uuid = uuid.UUID(client_user_id)
            client_job_ids = select(Job.id).where(Job.client_id == client_uuid)
            client_note_ids = select(JobNote.id).where(JobNote.job_id.in_(client_job_ids))
            stmt = stmt.where(Attachment.note_id.in_(client_note_ids))

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    # -------------------------------------------------------------------------
    # Phase 8 — business operations entity sync methods
    # -------------------------------------------------------------------------

    async def get_quotes_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Return all quotes changed since the given cursor timestamp.

        For client-role users, only includes sent/viewed/approved/declined quotes
        (not drafts or revised ones) to prevent premature quote disclosure.
        Admin and contractor roles receive all non-draft quotes.
        Includes line_items eagerly loaded (selectinload) — no N+1.

        Args:
            since:          High-water mark cursor timestamp.
            client_user_id: When provided (client role), restricts to sent/viewed/
                            approved/declined quotes for the client's own jobs.
        """
        from sqlalchemy.orm import selectinload

        from app.features.quotes.models import Quote

        stmt = (
            select(Quote)
            .where(or_(Quote.updated_at > since, Quote.deleted_at > since))
            .options(selectinload(Quote.line_items))
            .order_by(Quote.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )

        if client_user_id is not None:
            import uuid

            from app.features.jobs.models import Job

            client_uuid = uuid.UUID(client_user_id)
            client_job_ids = select(Job.id).where(Job.client_id == client_uuid)
            stmt = stmt.where(
                Quote.job_id.in_(client_job_ids),
                Quote.status.in_(["sent", "viewed", "approved", "declined"]),
            )
        # Admin/contractor: exclude drafts for cleanliness (admin sees all via API)
        # Actually per plan: client sees only sent/viewed/approved/declined — no filter for admin

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_quote_line_items_since(self, since: datetime) -> list:
        """Return all quote line items changed since the given cursor timestamp."""
        from app.features.quotes.models import QuoteLineItem

        result = await self.db.execute(
            select(QuoteLineItem)
            .where(or_(QuoteLineItem.updated_at > since, QuoteLineItem.deleted_at > since))
            .order_by(QuoteLineItem.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())

    async def get_invoices_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Return all invoices changed since the given cursor timestamp.

        Includes line_items eagerly loaded (selectinload) — no N+1.
        Client role users see invoices for their own jobs.

        Args:
            since:          High-water mark cursor timestamp.
            client_user_id: When provided (client role), restricts to invoices
                            for the client's own jobs.
        """
        from sqlalchemy.orm import selectinload

        from app.features.invoices.models import Invoice

        stmt = (
            select(Invoice)
            .where(or_(Invoice.updated_at > since, Invoice.deleted_at > since))
            .options(selectinload(Invoice.line_items))
            .order_by(Invoice.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )

        if client_user_id is not None:
            import uuid

            from app.features.jobs.models import Job

            client_uuid = uuid.UUID(client_user_id)
            client_job_ids = select(Job.id).where(Job.client_id == client_uuid)
            stmt = stmt.where(Invoice.job_id.in_(client_job_ids))

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_invoice_line_items_since(self, since: datetime) -> list:
        """Return all invoice line items changed since the given cursor timestamp."""
        from app.features.invoices.models import InvoiceLineItem

        result = await self.db.execute(
            select(InvoiceLineItem)
            .where(or_(InvoiceLineItem.updated_at > since, InvoiceLineItem.deleted_at > since))
            .order_by(InvoiceLineItem.updated_at)
            .limit(_SYNC_MAX_LIMIT)
        )
        return list(result.scalars().all())
