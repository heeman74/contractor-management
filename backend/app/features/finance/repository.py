"""FinanceRepository — async data access for the cost-entry domain.

Inherits TenantScopedRepository[CostEntry]. All queries are automatically
tenant-scoped via PostgreSQL RLS (SET LOCAL app.current_company_id).

CLAUDE.md N+1 rule: joinedload(CostEntry.category) on every list/get/rollup
query — category is many-to-one, category is lazy="raise" on the model, so an
un-eager-loaded access would fail loudly rather than silently N+1.

Pitfall 3 (31-RESEARCH.md): BaseRepository.list_all() does NOT filter
deleted_at — every custom query method here adds `.where(CostEntry.deleted_at.is_(None))`
explicitly (D-05: soft-deleted entries drop out of lists and rollups).

The public module-level query builders (costable_sessions_query,
invoice_amounts_query, approved_quote_amounts_query) and their row mappers
(to_work_sessions, to_anchored_amounts) are the single definition of the finance
traversal predicates. They are public because portfolio_repository composes the
same predicates company-wide; a second definition there would drift from this one.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import ColumnElement, Row, Select, func, select
from sqlalchemy.orm import joinedload

from app.core.base_repository import TenantScopedRepository
from app.features.finance.labor_derivation import LABOR_CATEGORY_NAME, ZERO_MONEY, WorkSession
from app.features.finance.margin_math import DocumentAmounts, RevenueAnchor
from app.features.finance.models import CostCategory, CostEntry, CostReceipt, LaborRate
from app.features.invoices.models import Invoice, InvoiceLineItem
from app.features.jobs.models import Job, TimeEntry
from app.features.projects.models import TradeScope
from app.features.quotes.models import Quote, QuoteLineItem
from app.features.users.models import User

# D-03: only clocked-out sessions with a final duration contribute labor cost;
# active sessions never do.
_COSTABLE_SESSION_STATUSES = ("completed", "adjusted")

# D-03 (Phase 33): only approved quotes qualify as revenue fallback.
QUOTE_STATUS_APPROVED = "approved"


def costable_sessions_query() -> Select[tuple[uuid.UUID, datetime, int, uuid.UUID | None]]:
    """Column-only select of costable tracked time (Pitfall 3 predicates, stated once)."""
    return select(
        TimeEntry.contractor_id,
        TimeEntry.clocked_in_at,
        TimeEntry.duration_seconds,
        TimeEntry.job_id,
    ).where(
        TimeEntry.session_status.in_(_COSTABLE_SESSION_STATUSES),
        TimeEntry.duration_seconds.is_not(None),
        TimeEntry.deleted_at.is_(None),
    )


def to_work_sessions(
    rows: Sequence[tuple[uuid.UUID, datetime, int, uuid.UUID | None]],
) -> list[WorkSession]:
    """Map column tuples to plain WorkSessions so the service never sees Row objects."""
    return [
        WorkSession(
            contractor_id=contractor_id,
            clocked_in_at=clocked_in_at,
            duration_seconds=seconds,
            job_id=job_id,
        )
        for contractor_id, clocked_in_at, seconds, job_id in rows
    ]


class FinanceRepository(TenantScopedRepository[CostEntry]):
    """Repository for CostEntry entities — eager-loads category by default."""

    model = CostEntry

    async def completed_work_sessions_for_job(self, job_id: uuid.UUID) -> list[WorkSession]:
        """Costable tracked time for a job, as plain WorkSessions.

        Selects columns only (never whole ORM rows) — TimeEntry.job and
        TimeEntry.contractor are lazy="raise" and the derivation needs neither.
        """
        result = await self.db.execute(costable_sessions_query().where(TimeEntry.job_id == job_id))
        return to_work_sessions(result.tuples().all())

    async def completed_work_sessions_for_project(self, project_id: uuid.UUID) -> list[WorkSession]:
        """Costable tracked time for every job linked to a project (jobs.project_id, D-07)."""
        result = await self.db.execute(
            costable_sessions_query()
            .join(Job, TimeEntry.job_id == Job.id)
            .where(Job.project_id == project_id)
        )
        return to_work_sessions(result.tuples().all())

    async def category_totals_for_job(
        self, job_id: uuid.UUID
    ) -> list[tuple[uuid.UUID, str, Decimal]]:
        """Per-category cost-entry sums for a job, in one GROUP BY round trip."""
        return await self._category_totals_where(CostEntry.job_id == job_id)

    async def category_totals_for_trade_scope(
        self, trade_scope_id: uuid.UUID
    ) -> list[tuple[uuid.UUID, str, Decimal]]:
        """Per-category cost-entry sums for a trade scope, in one GROUP BY round trip."""
        return await self._category_totals_where(CostEntry.trade_scope_id == trade_scope_id)

    async def _category_totals_where(
        self, anchor_filter: ColumnElement[bool]
    ) -> list[tuple[uuid.UUID, str, Decimal]]:
        """Shared GROUP BY over non-soft-deleted cost entries for one anchor filter."""
        result = await self.db.execute(
            select(CostCategory.id, CostCategory.name, func.sum(CostEntry.amount))
            .select_from(CostEntry)
            .join(CostCategory, CostEntry.category_id == CostCategory.id)
            .where(anchor_filter, CostEntry.deleted_at.is_(None))
            .group_by(CostCategory.id, CostCategory.name)
            .order_by(CostCategory.name)
        )
        return list(result.tuples().all())

    async def list_for_job(self, job_id: uuid.UUID) -> list[CostEntry]:
        """Return non-soft-deleted cost entries for a job, newest incurred_date first."""
        result = await self.db.execute(
            select(CostEntry)
            .where(CostEntry.job_id == job_id, CostEntry.deleted_at.is_(None))
            .options(joinedload(CostEntry.category))
            .order_by(CostEntry.incurred_date.desc())
        )
        return list(result.scalars().unique().all())

    async def list_for_trade_scope(self, trade_scope_id: uuid.UUID) -> list[CostEntry]:
        """Return non-soft-deleted cost entries for a trade scope, newest first."""
        result = await self.db.execute(
            select(CostEntry)
            .where(CostEntry.trade_scope_id == trade_scope_id, CostEntry.deleted_at.is_(None))
            .options(joinedload(CostEntry.category))
            .order_by(CostEntry.incurred_date.desc())
        )
        return list(result.scalars().unique().all())

    async def rollup_for_project(self, project_id: uuid.UUID) -> list[CostEntry]:
        """Return every non-soft-deleted cost entry rolling up to a project.

        Per D-02/D-05: trade-scope-anchored costs (trade_scopes.project_id) +
        costs on jobs whose project_id matches, in ONE query (no per-anchor
        loop — CLAUDE.md N+1 rule). The service computes the Decimal total
        from this single itemized list.
        """
        result = await self.db.execute(
            select(CostEntry)
            .outerjoin(TradeScope, CostEntry.trade_scope_id == TradeScope.id)
            .outerjoin(Job, CostEntry.job_id == Job.id)
            .where(
                CostEntry.deleted_at.is_(None),
                (TradeScope.project_id == project_id) | (Job.project_id == project_id),
            )
            .options(joinedload(CostEntry.category))
            .order_by(CostEntry.incurred_date.desc())
        )
        return list(result.scalars().unique().all())

    async def get_entry_or_404(self, entry_id: uuid.UUID) -> CostEntry:
        """Fetch a cost entry by id with category eager-loaded, or raise 404."""
        result = await self.db.execute(
            select(CostEntry)
            .where(CostEntry.id == entry_id, CostEntry.deleted_at.is_(None))
            .options(joinedload(CostEntry.category))
        )
        entry = result.scalars().unique().first()
        if entry is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Cost entry not found"
            )
        return entry

    async def soft_delete(self, entry_id: uuid.UUID) -> None:
        """Set deleted_at on a cost entry so it drops out of lists/rollups."""
        entry = await self.get_entry_or_404(entry_id)
        entry.deleted_at = datetime.now(UTC)
        await self.db.flush()

    async def is_reserved_labor_category(self, category_id: uuid.UUID) -> bool:
        """True when the id is this tenant's protected system `labor` category."""
        result = await self.db.execute(
            select(CostCategory.id)
            .where(
                CostCategory.id == category_id,
                CostCategory.name == LABOR_CATEGORY_NAME,
                CostCategory.is_system.is_(True),
            )
            .limit(1)
        )
        return result.scalar_one_or_none() is not None

    async def list_categories(self) -> list[CostCategory]:
        """Return the current tenant's cost categories, alphabetically."""
        result = await self.db.execute(select(CostCategory).order_by(CostCategory.name))
        return list(result.scalars().all())

    async def list_receipts_for_entry(self, cost_entry_id: uuid.UUID) -> list[CostReceipt]:
        """Return non-soft-deleted receipts for a cost entry, newest first."""
        result = await self.db.execute(
            select(CostReceipt)
            .where(CostReceipt.cost_entry_id == cost_entry_id, CostReceipt.deleted_at.is_(None))
            .order_by(CostReceipt.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_receipt_or_404(self, receipt_id: uuid.UUID) -> CostReceipt:
        """Fetch a non-soft-deleted receipt by id, or raise 404."""
        result = await self.db.execute(
            select(CostReceipt).where(
                CostReceipt.id == receipt_id, CostReceipt.deleted_at.is_(None)
            )
        )
        receipt = result.scalars().first()
        if receipt is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
        return receipt

    async def soft_delete_receipt(self, receipt_id: uuid.UUID) -> None:
        """Set deleted_at on a receipt so it drops out of the receipt list."""
        receipt = await self.get_receipt_or_404(receipt_id)
        receipt.deleted_at = datetime.now(UTC)
        await self.db.flush()


class LaborRateRepository(TenantScopedRepository[LaborRate]):
    """Append-only reads/writes over labor_rates (COST-04).

    RLS injects the company_id filter, so ix_labor_rates_company_user_effective
    (company_id, user_id, effective_from) serves every query here — no new index.
    """

    model = LaborRate

    async def list_history_for_user(self, user_id: uuid.UUID) -> list[LaborRate]:
        """Full rate history for one worker, newest effective_from first (display order)."""
        result = await self.db.execute(
            select(LaborRate)
            .where(LaborRate.user_id == user_id, LaborRate.deleted_at.is_(None))
            .order_by(LaborRate.effective_from.desc(), LaborRate.created_at.desc())
        )
        return list(result.scalars().all())

    async def list_all_rates(self) -> list[LaborRate]:
        """Every active rate row for the tenant, ascending — the sort order the
        effective-dated resolver requires."""
        result = await self.db.execute(
            select(LaborRate)
            .where(LaborRate.deleted_at.is_(None))
            .order_by(LaborRate.user_id, LaborRate.effective_from, LaborRate.created_at)
        )
        return list(result.scalars().all())

    async def list_rates_for_users(self, user_ids: Sequence[uuid.UUID]) -> list[LaborRate]:
        """Active rate rows for the given workers, ascending (resolver sort order).

        Returns [] for an empty user_ids to avoid an `IN ()` round trip.
        """
        if not user_ids:
            return []
        result = await self.db.execute(
            select(LaborRate)
            .where(LaborRate.user_id.in_(user_ids), LaborRate.deleted_at.is_(None))
            .order_by(LaborRate.user_id, LaborRate.effective_from, LaborRate.created_at)
        )
        return list(result.scalars().all())

    async def user_exists(self, user_id: uuid.UUID) -> bool:
        """True when the id belongs to an active user in the current tenant (RLS-scoped).

        labor_rates.user_id is a soft FK — without this check a typo'd UUID creates
        an orphan rate that silently never matches any tracked time.
        """
        result = await self.db.execute(
            select(User.id).where(User.id == user_id, User.deleted_at.is_(None)).limit(1)
        )
        return result.scalar_one_or_none() is not None


def invoice_amounts_query() -> Select:
    """Per-invoice money fields at their anchor, in one GROUP BY round trip.

    D-02: invoices have NO draft state (status constraint is exactly
    unpaid|partially_paid|paid), so "all issued invoices" needs no status
    filter — only the soft-delete predicate.

    `issued_at` trails the six money columns because the Phase 35 margin trend
    buckets an invoice by the UTC day it was issued. It is grouped explicitly
    even though Invoice.id already determines it: stating the intent beats
    relying on PostgreSQL's functional-dependency shortcut.
    """
    subtotal = func.coalesce(
        func.sum(InvoiceLineItem.quantity * InvoiceLineItem.unit_price), ZERO_MONEY
    )
    return (
        select(
            Invoice.job_id,
            Invoice.trade_scope_id,
            Invoice.discount_type,
            Invoice.discount_value,
            Invoice.tax_rate,
            subtotal,
            Invoice.issued_at,
        )
        .select_from(Invoice)
        .outerjoin(
            InvoiceLineItem,
            (InvoiceLineItem.invoice_id == Invoice.id) & InvoiceLineItem.deleted_at.is_(None),
        )
        .where(Invoice.deleted_at.is_(None))
        .group_by(
            Invoice.id,
            Invoice.job_id,
            Invoice.trade_scope_id,
            Invoice.discount_type,
            Invoice.discount_value,
            Invoice.tax_rate,
            Invoice.issued_at,
        )
    )


def approved_quote_amounts_query() -> Select:
    """Per-approved-quote money fields at their anchor, newest first.

    The created_at DESC ordering lets callers take the first row per anchor as
    "latest approved" (D-03 — mirrors InvoiceService._latest_approved_quote_for_scope).

    `approved_on` trails created_at because the Phase 35 margin trend buckets a
    quote by the UTC day it became effective. The COALESCE fallback exists
    because `approved_at` is nullable even for status `approved` (legacy and
    imported rows): dropping such a quote would break the final trend bucket's
    reconciliation with the all-time rollup, which is the trend's only self-check.
    """
    subtotal = func.coalesce(
        func.sum(QuoteLineItem.quantity * QuoteLineItem.unit_price), ZERO_MONEY
    )
    approved_on = func.coalesce(Quote.approved_at, Quote.created_at).label("approved_on")
    return (
        select(
            Quote.job_id,
            Quote.trade_scope_id,
            Quote.discount_type,
            Quote.discount_value,
            Quote.tax_rate,
            subtotal,
            Quote.created_at,
            approved_on,
        )
        .select_from(Quote)
        .outerjoin(
            QuoteLineItem,
            (QuoteLineItem.quote_id == Quote.id) & QuoteLineItem.deleted_at.is_(None),
        )
        .where(Quote.status == QUOTE_STATUS_APPROVED, Quote.deleted_at.is_(None))
        .group_by(
            Quote.id,
            Quote.job_id,
            Quote.trade_scope_id,
            Quote.discount_type,
            Quote.discount_value,
            Quote.tax_rate,
            Quote.created_at,
            approved_on,
        )
        .order_by(Quote.created_at.desc())
    )


def to_anchored_amounts(row: Row) -> tuple[RevenueAnchor, DocumentAmounts]:
    """Map one aggregate row to margin_math value objects (never ORM instances).

    Both document queries lead with the same six columns, so one mapper serves
    invoices and quotes alike; their trailing date columns are read by label at
    the call sites that need them, never through this mapper.
    """
    job_id, trade_scope_id, discount_type, discount_value, tax_rate, subtotal = row[:6]
    return (
        RevenueAnchor(job_id=job_id, trade_scope_id=trade_scope_id),
        DocumentAmounts(
            subtotal=subtotal,
            discount_type=discount_type,
            discount_value=discount_value,
            tax_rate=tax_rate,
        ),
    )


def _anchor_filter(
    anchor: RevenueAnchor, document: type[Invoice] | type[Quote]
) -> ColumnElement[bool]:
    """job_id == X for a job anchor, trade_scope_id == X for a scope anchor."""
    if anchor.job_id is not None:
        return document.job_id == anchor.job_id
    return document.trade_scope_id == anchor.trade_scope_id


class RevenueRepository(TenantScopedRepository[Invoice]):
    """Bounded, read-only revenue aggregates for margin assembly (MARG-01/02).

    Every method returns margin_math value objects, never ORM rows — all
    Invoice/Quote relationships are lazy="raise" (Pitfall 6), and the column-only
    GROUP BY aggregates are O(1) round trips regardless of document count.
    RLS scopes every query to the current tenant automatically.
    """

    model = Invoice

    async def invoice_amounts_for_anchor(self, anchor: RevenueAnchor) -> list[DocumentAmounts]:
        """Money fields of every invoice at one job or trade-scope anchor."""
        result = await self.db.execute(
            invoice_amounts_query().where(_anchor_filter(anchor, Invoice))
        )
        return [to_anchored_amounts(row)[1] for row in result.all()]

    async def latest_approved_quote_amounts_for_anchor(
        self, anchor: RevenueAnchor
    ) -> DocumentAmounts | None:
        """Money fields of the latest approved quote at one anchor, or None."""
        result = await self.db.execute(
            approved_quote_amounts_query().where(_anchor_filter(anchor, Quote)).limit(1)
        )
        row = result.first()
        return None if row is None else to_anchored_amounts(row)[1]

    async def invoice_amounts_by_anchor_for_project(
        self, project_id: uuid.UUID
    ) -> list[tuple[RevenueAnchor, DocumentAmounts]]:
        """Every invoice rolling up to a project, tagged with its anchor.

        D-12: revenue traverses the exact dual-outerjoin shape of
        rollup_for_project so mixed job/scope records net out with the cost side.
        """
        result = await self.db.execute(
            invoice_amounts_query()
            .outerjoin(TradeScope, Invoice.trade_scope_id == TradeScope.id)
            .outerjoin(Job, Invoice.job_id == Job.id)
            .where((TradeScope.project_id == project_id) | (Job.project_id == project_id))
        )
        return [to_anchored_amounts(row) for row in result.all()]

    async def approved_quote_amounts_by_anchor_for_project(
        self, project_id: uuid.UUID
    ) -> list[tuple[RevenueAnchor, DocumentAmounts]]:
        """Every approved quote rolling up to a project, newest first, per anchor.

        Same D-12 traversal as the invoice leg; callers take the first row per
        anchor as that anchor's latest approved quote.
        """
        result = await self.db.execute(
            approved_quote_amounts_query()
            .outerjoin(TradeScope, Quote.trade_scope_id == TradeScope.id)
            .outerjoin(Job, Quote.job_id == Job.id)
            .where((TradeScope.project_id == project_id) | (Job.project_id == project_id))
        )
        return [to_anchored_amounts(row) for row in result.all()]

    async def latest_project_level_approved_quote_amounts(
        self, project_id: uuid.UUID
    ) -> DocumentAmounts | None:
        """Money fields of the latest project-level approved quote, or None.

        D-14: a project-anchored quote (job_id AND trade_scope_id both NULL)
        counts only when NO anchor in the project resolved any revenue — the
        service enforces that rule; this method only fetches the candidate.
        """
        result = await self.db.execute(
            approved_quote_amounts_query()
            .where(
                Quote.project_id == project_id,
                Quote.job_id.is_(None),
                Quote.trade_scope_id.is_(None),
            )
            .limit(1)
        )
        row = result.first()
        return None if row is None else to_anchored_amounts(row)[1]
