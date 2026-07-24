"""Sync service — multi-table delta query for offline sync.

Each method returns all records changed since a given cursor timestamp.
Records are included if updated_at > since OR deleted_at > since, ensuring
tombstones (soft-deleted records) are propagated to offline clients.

CRITICAL: RLS is automatically enforced via TenantMiddleware ContextVar,
so all queries are automatically scoped to the current tenant. No explicit
company_id WHERE clause is needed (except get_companies_since — companies
table has no RLS).

Model imports are kept inside each method: the SQLAlchemy mapper registry must
have the relevant models registered (via side-effect imports in sync/router.py)
before these queries build their relationship options.
"""

import uuid
from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload, selectinload

from app.features.companies.models import Company
from app.features.users.models import User, UserRole

# Maximum records per sync batch to prevent memory exhaustion on first sync
_SYNC_MAX_LIMIT = 1000
_CLIENT_VISIBLE_QUOTE_STATUSES = ["sent", "viewed", "approved", "declined"]


class SyncService:
    """Delta sync service for offline-first clients."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # -------------------------------------------------------------------------
    # Shared delta-query helpers
    # -------------------------------------------------------------------------

    @staticmethod
    def _changed_since(model, since: datetime):
        """Predicate: record was updated or tombstoned after the cursor."""
        return or_(model.updated_at > since, model.deleted_at > since)

    async def _delta(
        self,
        model,
        since: datetime,
        *,
        options: tuple = (),
        extra_conditions: tuple = (),
        unique: bool = False,
        limit: int = _SYNC_MAX_LIMIT,
    ) -> list:
        """Run the standard delta query for a model changed since the cursor.

        options:          eager-load options (joinedload/selectinload).
        extra_conditions: additional WHERE clauses (e.g. client-scoped filters).
        unique:           dedupe rows (required when joinedload fans out one-to-many).
        """
        stmt = select(model).where(self._changed_since(model, since))
        if options:
            stmt = stmt.options(*options)
        if extra_conditions:
            stmt = stmt.where(*extra_conditions)
        stmt = stmt.order_by(model.updated_at).limit(limit)

        result = await self.db.execute(stmt)
        scalars = result.scalars().unique() if unique else result.scalars()
        return list(scalars.all())

    @staticmethod
    def _client_job_ids(client_user_id: str):
        """Scalar subquery of Job.id owned by the given client user."""
        from app.features.jobs.models import Job

        return select(Job.id).where(Job.client_id == uuid.UUID(client_user_id))

    # -------------------------------------------------------------------------
    # Tenant-root & identity entities
    # -------------------------------------------------------------------------

    async def get_companies_since(self, since: datetime) -> list[Company]:
        """Companies changed since the cursor (no RLS — companies are the tenant root)."""
        return await self._delta(Company, since)

    async def get_users_since(self, since: datetime) -> list[User]:
        """Users changed since the cursor, with roles eager-loaded."""
        return await self._delta(User, since, options=(selectinload(User.roles),))

    async def get_user_roles_since(self, since: datetime) -> list[UserRole]:
        """User roles changed since the cursor."""
        return await self._delta(UserRole, since)

    # -------------------------------------------------------------------------
    # Phase 4 — job lifecycle entities
    # -------------------------------------------------------------------------

    async def get_jobs_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
        limit: int = _SYNC_MAX_LIMIT,
    ) -> list:
        """Jobs changed since the cursor (client role sees only their own jobs)."""
        from app.features.jobs.models import Job

        extra = ()
        if client_user_id is not None:
            extra = (Job.client_id == uuid.UUID(client_user_id),)
        return await self._delta(
            Job,
            since,
            options=(joinedload(Job.client), joinedload(Job.contractor)),
            extra_conditions=extra,
            unique=True,
            limit=limit,
        )

    async def get_client_profiles_since(self, since: datetime) -> list:
        """Client profiles changed since the cursor."""
        from app.features.jobs.models import ClientProfile

        return await self._delta(ClientProfile, since)

    async def get_job_requests_since(self, since: datetime) -> list:
        """Job requests changed since the cursor."""
        from app.features.jobs.models import JobRequest

        return await self._delta(JobRequest, since)

    # -------------------------------------------------------------------------
    # Phase 5 — calendar & dispatch entities
    # -------------------------------------------------------------------------

    async def get_bookings_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
        limit: int = _SYNC_MAX_LIMIT,
    ) -> list:
        """Bookings changed since the cursor (client role scoped to their jobs)."""
        from app.features.scheduling.models import Booking

        extra = ()
        if client_user_id is not None:
            extra = (Booking.job_id.in_(self._client_job_ids(client_user_id)),)
        return await self._delta(Booking, since, extra_conditions=extra, limit=limit)

    async def get_job_sites_since(self, since: datetime) -> list:
        """Job sites changed since the cursor."""
        from app.features.scheduling.models import JobSite

        return await self._delta(JobSite, since)

    # -------------------------------------------------------------------------
    # Phase 6 — field workflow entities
    # -------------------------------------------------------------------------

    async def get_job_notes_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Job notes changed since the cursor, with attachments eager-loaded."""
        from app.features.jobs.models import JobNote

        extra = ()
        if client_user_id is not None:
            extra = (JobNote.job_id.in_(self._client_job_ids(client_user_id)),)
        return await self._delta(
            JobNote,
            since,
            options=(selectinload(JobNote.attachments),),
            extra_conditions=extra,
        )

    async def get_time_entries_since(self, since: datetime) -> list:
        """Time entries changed since the cursor."""
        from app.features.jobs.models import TimeEntry

        return await self._delta(TimeEntry, since)

    async def get_attachments_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Attachments changed since the cursor (client role scoped via their notes)."""
        from app.features.jobs.models import Attachment, JobNote

        extra = ()
        if client_user_id is not None:
            client_note_ids = select(JobNote.id).where(
                JobNote.job_id.in_(self._client_job_ids(client_user_id))
            )
            extra = (Attachment.note_id.in_(client_note_ids),)
        return await self._delta(Attachment, since, extra_conditions=extra)

    # -------------------------------------------------------------------------
    # Phase 8 — business operations entities
    # -------------------------------------------------------------------------

    async def get_quotes_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Quotes changed since the cursor, with line items eager-loaded.

        Client-role users only receive sent/viewed/approved/declined quotes for
        their own jobs; admin and contractor roles receive all.
        """
        from app.features.quotes.models import Quote

        extra = ()
        if client_user_id is not None:
            extra = (
                Quote.job_id.in_(self._client_job_ids(client_user_id)),
                Quote.status.in_(_CLIENT_VISIBLE_QUOTE_STATUSES),
            )
        return await self._delta(
            Quote,
            since,
            options=(selectinload(Quote.line_items),),
            extra_conditions=extra,
        )

    async def get_quote_line_items_since(self, since: datetime) -> list:
        """Quote line items changed since the cursor."""
        from app.features.quotes.models import QuoteLineItem

        return await self._delta(QuoteLineItem, since)

    async def get_invoices_since(
        self,
        since: datetime,
        *,
        client_user_id: str | None = None,
    ) -> list:
        """Invoices changed since the cursor, with line items eager-loaded."""
        from app.features.invoices.models import Invoice

        extra = ()
        if client_user_id is not None:
            extra = (Invoice.job_id.in_(self._client_job_ids(client_user_id)),)
        return await self._delta(
            Invoice,
            since,
            options=(selectinload(Invoice.line_items),),
            extra_conditions=extra,
        )

    async def get_invoice_line_items_since(self, since: datetime) -> list:
        """Invoice line items changed since the cursor."""
        from app.features.invoices.models import InvoiceLineItem

        return await self._delta(InvoiceLineItem, since)
