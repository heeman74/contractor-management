"""QuoteRepository — async data access for the quotes domain.

Inherits TenantScopedRepository[Quote].  All queries are automatically
tenant-scoped via PostgreSQL RLS (SET LOCAL app.current_company_id).

Eager-loading strategy (per CLAUDE.md):
- selectinload for one-to-many (line_items)
- joinedload for many-to-one (job)
"""

from __future__ import annotations

import uuid

from sqlalchemy import and_, select
from sqlalchemy.orm import joinedload, selectinload

from app.core.base_repository import TenantScopedRepository

# isort: split
# Side-effect imports: ensure related mappers are registered before configure_mappers()
# triggers on Quote model access (same pattern as jobs/router.py Phase 4 fix).
import app.features.billing_milestones.models
import app.features.invoices.models
import app.features.scheduling.models
import app.features.users.models  # noqa: F401 — User mapper (Job.client_id)

# isort: split
from app.features.quotes.models import Quote, QuoteLineItem, QuoteTemplate

# Depth guard for the revision-chain walk: terminates cyclic or corrupt chains
# instead of looping forever. Real chains are single-digit deep.
MAX_REVISION_CHAIN_DEPTH = 50


class QuoteRepository(TenantScopedRepository[Quote]):
    """Repository for Quote entities — eager-loads line_items by default."""

    model = Quote
    # Default eager loading for get_by_id and list_all
    eager_load_options = [
        selectinload(Quote.line_items),
        joinedload(Quote.job),
    ]

    async def get_with_line_items(self, quote_id: uuid.UUID) -> Quote | None:
        """Return a quote with line_items and job eagerly loaded."""
        result = await self.db.execute(
            select(Quote)
            .where(Quote.id == quote_id)
            .options(
                selectinload(Quote.line_items),
                joinedload(Quote.job),
            )
        )
        return result.scalars().first()

    async def previous_approved_in_chain(self, quote: Quote) -> Quote | None:
        """Nearest ancestor with approved_at set, walking revised_from_quote_id.

        Returns None for the first quote of a chain (no approved ancestor) or
        when the depth guard trips. Ancestors that were never approved
        (declined/expired revisions) are skipped. Each ancestor loads with its
        line items because callers compute the pre-tax delta from them.

        This loop does not violate the CLAUDE.md no-query-in-a-loop rule: it is
        bounded by revision-chain length (single-digit in practice, hard-capped
        at MAX_REVISION_CHAIN_DEPTH), not by row count, and each step is one
        primary-key lookup.
        """
        ancestor_id = quote.revised_from_quote_id
        for _ in range(MAX_REVISION_CHAIN_DEPTH):
            if ancestor_id is None:
                return None
            ancestor = await self.get_with_line_items(ancestor_id)
            if ancestor is None:
                return None
            if ancestor.approved_at is not None:
                return ancestor
            ancestor_id = ancestor.revised_from_quote_id
        return None

    async def get_for_job(self, job_id: uuid.UUID) -> Quote | None:
        """Return the latest non-deleted, non-revised quote for a job.

        Prefers sent/viewed/approved/declined over draft if multiple exist.
        Falls back to the most recently created draft.
        """
        result = await self.db.execute(
            select(Quote)
            .where(
                and_(
                    Quote.job_id == job_id,
                    Quote.deleted_at.is_(None),
                    Quote.status != "revised",
                )
            )
            .options(
                selectinload(Quote.line_items),
                joinedload(Quote.job),
            )
            .order_by(Quote.created_at.desc())
        )
        return result.scalars().first()

    async def get_active_quotes(self) -> list[Quote]:
        """Return all non-deleted, non-revised quotes for the current tenant."""
        result = await self.db.execute(
            select(Quote)
            .where(
                and_(
                    Quote.deleted_at.is_(None),
                    Quote.status != "revised",
                )
            )
            .options(
                selectinload(Quote.line_items),
                joinedload(Quote.job),
            )
            .order_by(Quote.created_at.desc())
        )
        return list(result.scalars().all())


class QuoteTemplateRepository(TenantScopedRepository[QuoteTemplate]):
    """Repository for QuoteTemplate entities."""

    model = QuoteTemplate

    async def list_templates(self) -> list[QuoteTemplate]:
        """Return all templates for the current tenant."""
        result = await self.db.execute(
            select(QuoteTemplate)
            .where(QuoteTemplate.deleted_at.is_(None))
            .order_by(QuoteTemplate.created_at.desc())
        )
        return list(result.scalars().all())

    async def delete_template(self, template_id: uuid.UUID) -> bool:
        """Hard-delete a quote template. Returns False if not found."""
        template = await self.db.get(QuoteTemplate, template_id)
        if template is None:
            return False
        await self.db.delete(template)
        await self.db.flush()
        return True


def _make_line_items(
    quote_id: uuid.UUID, company_id: uuid.UUID, items_data: list
) -> list[QuoteLineItem]:
    """Build QuoteLineItem instances from line item data objects."""
    return [
        QuoteLineItem(
            quote_id=quote_id,
            company_id=company_id,
            item_type=item.item_type,
            description=item.description,
            quantity=item.quantity,
            unit=item.unit,
            unit_price=item.unit_price,
            sort_order=item.sort_order,
        )
        for item in items_data
    ]
