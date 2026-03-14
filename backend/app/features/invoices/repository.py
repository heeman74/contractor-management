"""InvoiceRepository — async data access for the invoices domain.

Inherits TenantScopedRepository[Invoice].  All queries are automatically
tenant-scoped via PostgreSQL RLS (SET LOCAL app.current_company_id).

Eager-loading strategy (per CLAUDE.md):
- selectinload for one-to-many (line_items)
- joinedload for many-to-one (job, quote)
"""

from __future__ import annotations

import uuid

from sqlalchemy import and_, select
from sqlalchemy.orm import joinedload, selectinload

from app.core.base_repository import TenantScopedRepository

# isort: split
# Side-effect imports: ensure all referenced mappers are registered before
# configure_mappers() triggers on Invoice relationship resolution.
import app.features.quotes.models  # noqa: F401 — Quote mapper (Invoice.quote FK)
import app.features.scheduling.models  # noqa: F401 — Booking mapper (Job.bookings)
import app.features.users.models  # noqa: F401 — User mapper (Job.client_id)

# isort: split
from app.features.invoices.models import Invoice


class InvoiceRepository(TenantScopedRepository[Invoice]):
    """Repository for Invoice entities — eager-loads line_items by default."""

    model = Invoice
    # Default eager loading for get_by_id and list_all
    eager_load_options = [
        selectinload(Invoice.line_items),
        joinedload(Invoice.job),
        joinedload(Invoice.quote),
    ]

    async def get_with_line_items(self, invoice_id: uuid.UUID) -> Invoice | None:
        """Return an invoice with line_items, job, and quote eagerly loaded."""
        result = await self.db.execute(
            select(Invoice)
            .where(Invoice.id == invoice_id)
            .options(
                selectinload(Invoice.line_items),
                joinedload(Invoice.job),
                joinedload(Invoice.quote),
            )
        )
        return result.scalars().first()

    async def get_for_job(self, job_id: uuid.UUID) -> Invoice | None:
        """Return the invoice for a job (most recent non-deleted)."""
        result = await self.db.execute(
            select(Invoice)
            .where(
                and_(
                    Invoice.job_id == job_id,
                    Invoice.deleted_at.is_(None),
                )
            )
            .options(
                selectinload(Invoice.line_items),
                joinedload(Invoice.job),
                joinedload(Invoice.quote),
            )
            .order_by(Invoice.created_at.desc())
        )
        return result.scalars().first()
