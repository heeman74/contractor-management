"""InvoiceService — business logic for the invoices domain.

Key operations:
- generate_from_quote: validates completed job with approved quote, generates
  sequential invoice number via SELECT FOR UPDATE on company row (Research Pattern 2),
  copies quote's line items, transitions job to Invoiced.
- generate_manual: for jobs without quotes. Same numbering, same transition.
- update_invoice: line item replacement before finalize.
- finalize_invoice: sets finalized_at, prevents further edits.
- update_payment_status: valid transitions between unpaid/partially_paid/paid.

Sequential numbering design:
  SELECT ... FOR UPDATE on the company row prevents duplicate invoice numbers
  under concurrent requests. The sequence counter is incremented and flushed
  before the invoice is created, ensuring uniqueness within a single transaction.
  Format: f"{prefix}-{sequence:04d}" (e.g. "INV-0001").

All CLAUDE.md rules apply:
- Inherits TenantScopedService[Invoice]
- No db.commit() — get_db handles transaction lifecycle
- db.flush() when generated IDs are needed before commit
- selectinload for one-to-many, joinedload for many-to-one
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import delete, func, select, text
from sqlalchemy.orm import selectinload

from app.core.base_service import TenantScopedService, entity_or_404
from app.features.billing_milestones.models import BillingMilestone
from app.features.companies.models import Company
from app.features.invoices.models import Invoice, InvoiceLineItem
from app.features.invoices.repository import InvoiceRepository
from app.features.invoices.schemas import InvoiceCreate, InvoiceUpdate, MarkPaidRequest
from app.features.jobs.mixins import JobEventsMixin
from app.features.jobs.models import Job
from app.features.projects.models import Task, TradeScope
from app.features.quotes.models import Quote, QuoteLineItem

# Domain status literals (mirror DB CheckConstraints)
_JOB_STATUS_COMPLETE = "complete"
_JOB_STATUS_INVOICED = "invoiced"
_TASK_STATUS_COMPLETE = "complete"
_QUOTE_STATUS_APPROVED = "approved"
_INVOICE_STATUS_UNPAID = "unpaid"
_INVOICE_STATUS_PAID = "paid"
_INVOICE_GENERATED_EVENT = "invoice_generated"


class InvoiceService(JobEventsMixin, TenantScopedService[Invoice]):
    """Service implementing invoice generation and lifecycle for a tenant."""

    repository_class = InvoiceRepository
    repository: InvoiceRepository

    # -------------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------------

    async def _generate_invoice_number(self, company_id: uuid.UUID) -> str:
        """Generate the next sequential invoice number using SELECT FOR UPDATE.

        Atomically increments company.invoice_sequence under a row-level lock,
        preventing duplicate numbers under concurrent requests.
        Returns formatted number like 'INV-0001'.
        """
        # SELECT FOR UPDATE — acquires row-level lock for this transaction
        result = await self.db.execute(
            select(Company).where(Company.id == company_id).with_for_update()
        )
        company = entity_or_404(result.scalars().first(), f"Company {company_id} not found")

        company.invoice_sequence = company.invoice_sequence + 1
        prefix = company.invoice_prefix or "INV"
        await self.db.flush()  # persist increment before creating the invoice

        return f"{prefix}-{company.invoice_sequence:04d}"

    def _add_source_line_items(
        self,
        invoice_id: uuid.UUID,
        company_id: uuid.UUID,
        sources: list,
    ) -> None:
        """Add InvoiceLineItem rows copied from quote/schema line-item objects."""
        for item in sources:
            self.db.add(
                InvoiceLineItem(
                    invoice_id=invoice_id,
                    company_id=company_id,
                    item_type=item.item_type,
                    description=item.description,
                    quantity=item.quantity,
                    unit=item.unit,
                    unit_price=item.unit_price,
                    sort_order=item.sort_order,
                )
            )

    async def _replace_line_items(
        self,
        invoice_id: uuid.UUID,
        company_id: uuid.UUID,
        items_data: list,
    ) -> None:
        """Delete all existing line items for an invoice and create new ones."""
        await self.db.execute(
            delete(InvoiceLineItem).where(InvoiceLineItem.invoice_id == invoice_id)
        )
        self._add_source_line_items(invoice_id, company_id, items_data)
        await self.db.flush()

    async def _get_invoice_or_404(self, invoice_id: uuid.UUID) -> Invoice:
        """Fetch an invoice with line items eager-loaded, or raise 404."""
        return entity_or_404(
            await self.repository.get_with_line_items(invoice_id), "Invoice not found"
        )

    async def _load_complete_job(self, job_id: uuid.UUID) -> Job:
        """Fetch a job that must be in 'complete' status before invoicing."""
        job = entity_or_404(await self.db.get(Job, job_id), "Job not found")
        if job.status != _JOB_STATUS_COMPLETE:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"Job must be in '{_JOB_STATUS_COMPLETE}' status to generate "
                    f"an invoice (current: {job.status})"
                ),
            )
        return job

    async def _mark_job_invoiced(self, job: Job, user_id: uuid.UUID) -> None:
        """Transition a job to 'invoiced', bump its version, and record the event."""
        job.status = _JOB_STATUS_INVOICED
        job.version = (job.version or 0) + 1  # Maintain optimistic locking consistency
        await self.db.flush()
        await self._append_job_status_event(job.id, _INVOICE_GENERATED_EVENT, user_id)

    async def _latest_approved_quote_for_scope(
        self,
        trade_scope_id: uuid.UUID,
        *,
        load_line_items: bool = False,
    ) -> Quote | None:
        """Return the most recent approved, non-deleted quote for a trade scope."""
        stmt = (
            select(Quote)
            .where(
                Quote.trade_scope_id == trade_scope_id,
                Quote.status == _QUOTE_STATUS_APPROVED,
                Quote.deleted_at.is_(None),
            )
            .order_by(Quote.created_at.desc())
        )
        if load_line_items:
            stmt = stmt.options(selectinload(Quote.line_items))
        result = await self.db.execute(stmt)
        return result.scalars().first()

    # -------------------------------------------------------------------------
    # Invoice generation
    # -------------------------------------------------------------------------

    async def generate_from_quote(
        self,
        job_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Invoice:
        """Generate an invoice from a completed job's approved quote.

        Validates:
        - Job must exist and be in 'complete' status
        - Job must have an approved quote

        Then:
        1. Generates sequential invoice number (SELECT FOR UPDATE on company)
        2. Creates Invoice copying quote's line items, tax_rate, discount
        3. Sets issued_at = now()
        4. Transitions job to 'invoiced'
        5. Appends 'invoice_generated' to job.status_history
        6. Sends FCM notification to client (fire-and-forget)
        """
        job = await self._load_complete_job(job_id)

        result = await self.db.execute(
            select(Quote)
            .where(
                Quote.job_id == job_id,
                Quote.status == _QUOTE_STATUS_APPROVED,
                Quote.deleted_at.is_(None),
            )
            .options(selectinload(Quote.line_items))
            .order_by(Quote.created_at.desc())
        )
        approved_quote = result.scalars().first()
        if approved_quote is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="No approved quote found for this job",
            )

        company_id = self._require_tenant_id()
        invoice_number = await self._generate_invoice_number(company_id)

        invoice = Invoice(
            company_id=company_id,
            job_id=job_id,
            quote_id=approved_quote.id,
            invoice_number=invoice_number,
            status=_INVOICE_STATUS_UNPAID,
            tax_rate=approved_quote.tax_rate,
            discount_type=approved_quote.discount_type,
            discount_value=approved_quote.discount_value,
            issued_at=datetime.now(UTC),
        )
        self.db.add(invoice)
        await self.db.flush()  # get invoice.id

        self._add_source_line_items(invoice.id, company_id, approved_quote.line_items)
        await self._mark_job_invoiced(job, user_id)
        await self._notify_client(job, _INVOICE_GENERATED_EVENT)

        return await self.repository.get_with_line_items(invoice.id)  # type: ignore[return-value]

    async def generate_manual(
        self,
        data: InvoiceCreate,
        user_id: uuid.UUID,
    ) -> Invoice:
        """Generate a manual invoice for a job or a trade scope (no prior quote required).

        Useful for jobs that skip the quote step (e.g., emergency call-outs).
        Job-anchored invoices require a 'complete' job and transition it to
        'invoiced'; trade-scope-anchored invoices (Phase 25 anchor) only require
        the scope to exist — scopes have no invoiced status machine.
        """
        job = None
        if data.job_id is not None:
            job = await self._load_complete_job(data.job_id)
        else:
            entity_or_404(
                await self.db.get(TradeScope, data.trade_scope_id),
                f"TradeScope {data.trade_scope_id} not found",
            )

        company_id = self._require_tenant_id()
        invoice_number = await self._generate_invoice_number(company_id)

        invoice = Invoice(
            company_id=company_id,
            job_id=data.job_id,
            trade_scope_id=data.trade_scope_id,
            quote_id=data.quote_id,
            invoice_number=invoice_number,
            status=_INVOICE_STATUS_UNPAID,
            tax_rate=data.tax_rate,
            discount_type=data.discount_type,
            discount_value=data.discount_value,
            due_date=data.due_date,
            issued_at=data.issued_at or datetime.now(UTC),
        )
        self.db.add(invoice)
        await self.db.flush()  # get invoice.id

        self._add_source_line_items(invoice.id, company_id, data.line_items)
        if job is not None:
            await self._mark_job_invoiced(job, user_id)

        return await self.repository.get_with_line_items(invoice.id)  # type: ignore[return-value]

    # -------------------------------------------------------------------------
    # Invoice lifecycle
    # -------------------------------------------------------------------------

    async def update_invoice(
        self,
        invoice_id: uuid.UUID,
        data: InvoiceUpdate,
    ) -> Invoice:
        """Update an invoice before finalization. Full line item replacement if items provided."""
        invoice = await self._get_invoice_or_404(invoice_id)

        if invoice.finalized_at is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot update a finalized invoice",
            )

        if data.tax_rate is not None:
            invoice.tax_rate = data.tax_rate
        if data.discount_type is not None:
            invoice.discount_type = data.discount_type
        if data.discount_value is not None:
            invoice.discount_value = data.discount_value
        if data.due_date is not None:
            invoice.due_date = data.due_date

        if data.line_items is not None:
            await self._replace_line_items(invoice_id, invoice.company_id, data.line_items)

        await self.db.flush()
        return await self.repository.get_with_line_items(invoice_id)  # type: ignore[return-value]

    async def finalize_invoice(self, invoice_id: uuid.UUID) -> Invoice:
        """Finalize an invoice — set finalized_at, prevent further edits."""
        invoice = await self._get_invoice_or_404(invoice_id)

        if invoice.finalized_at is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Invoice is already finalized",
            )

        invoice.finalized_at = datetime.now(UTC)
        await self.db.flush()
        return await self.repository.get_with_line_items(invoice_id)  # type: ignore[return-value]

    async def update_payment_status(
        self,
        invoice_id: uuid.UUID,
        data: MarkPaidRequest,
    ) -> Invoice:
        """Update invoice payment status.

        Valid transitions:
        - unpaid -> partially_paid
        - unpaid -> paid
        - partially_paid -> paid
        - partially_paid -> unpaid (e.g. chargeback)
        - paid -> unpaid is NOT allowed (prevents fraud)
        """
        invoice = await self._get_invoice_or_404(invoice_id)

        # Prevent paid -> unpaid/partially_paid regression
        if invoice.status == _INVOICE_STATUS_PAID and data.status != _INVOICE_STATUS_PAID:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Cannot revert a paid invoice to an unpaid status",
            )

        invoice.status = data.status
        if data.amount_paid is not None:
            invoice.amount_paid = data.amount_paid
        await self.db.flush()
        return await self.repository.get_with_line_items(invoice_id)  # type: ignore[return-value]

    # -------------------------------------------------------------------------
    # Trade-scope invoice generation (Phase 25)
    # -------------------------------------------------------------------------

    async def generate_from_scope(
        self,
        trade_scope_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Invoice:
        """Generate an invoice from completed tasks in a trade scope.

        Each completed task becomes a line item. Inherits tax_rate from the
        approved quote on this scope if one exists. unit_price=0.00 — GC fills in.
        """
        entity_or_404(
            await self.db.get(TradeScope, trade_scope_id),
            f"TradeScope {trade_scope_id} not found",
        )

        # Load completed tasks for this scope
        tasks_result = await self.db.execute(
            select(Task)
            .where(
                Task.trade_scope_id == trade_scope_id,
                Task.status == _TASK_STATUS_COMPLETE,
                Task.deleted_at.is_(None),
            )
            .order_by(Task.sort_order)
        )
        completed_tasks = list(tasks_result.scalars().all())

        # Look for an approved quote to inherit tax_rate and discounts
        approved_quote = await self._latest_approved_quote_for_scope(trade_scope_id)

        tax_rate = approved_quote.tax_rate if approved_quote else Decimal("0")
        discount_type = approved_quote.discount_type if approved_quote else None
        discount_value = approved_quote.discount_value if approved_quote else Decimal("0")

        company_id = self._require_tenant_id()
        invoice_number = await self._generate_invoice_number(company_id)

        invoice = Invoice(
            company_id=company_id,
            job_id=None,
            trade_scope_id=trade_scope_id,
            quote_id=approved_quote.id if approved_quote else None,
            invoice_number=invoice_number,
            status=_INVOICE_STATUS_UNPAID,
            tax_rate=tax_rate,
            discount_type=discount_type,
            discount_value=discount_value,
            issued_at=datetime.now(UTC),
        )
        self.db.add(invoice)
        await self.db.flush()  # get invoice.id

        # One line item per completed task
        for i, task in enumerate(completed_tasks):
            self.db.add(
                InvoiceLineItem(
                    invoice_id=invoice.id,
                    company_id=company_id,
                    item_type="labor",
                    description=task.title,
                    quantity=task.estimated_hours if task.estimated_hours else Decimal("1"),
                    unit="hr",
                    unit_price=Decimal("0.00"),
                    sort_order=i,
                )
            )

        await self.db.flush()
        return await self.repository.get_with_line_items(invoice.id)  # type: ignore[return-value]

    async def generate_progress_invoice(
        self,
        trade_scope_id: uuid.UUID,
        milestone_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> Invoice:
        """Generate a progress invoice from a billing milestone.

        Uses atomic UPDATE ... WHERE is_invoiced=FALSE to prevent double-billing.
        Requires an approved quote on the trade scope to compute the invoice amount.
        """
        milestone = entity_or_404(
            await self.db.get(BillingMilestone, milestone_id),
            f"BillingMilestone {milestone_id} not found",
        )

        # Atomic double-billing prevention: UPDATE ... WHERE is_invoiced=FALSE RETURNING id
        stmt = text(
            "UPDATE billing_milestones "
            "SET is_invoiced = TRUE "
            "WHERE id = :id AND is_invoiced = FALSE "
            "RETURNING id"
        )
        result = await self.db.execute(stmt, {"id": milestone_id})
        row = result.fetchone()
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Milestone already invoiced",
            )

        # Require approved quote for this scope to compute amount
        approved_quote = await self._latest_approved_quote_for_scope(
            trade_scope_id, load_line_items=True
        )
        if approved_quote is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No approved quote for this trade scope — cannot calculate progress invoice amount",
            )

        # Compute quote total (subtotal before tax/discount — kept simple per plan spec)
        quote_subtotal_result = await self.db.execute(
            select(
                func.coalesce(
                    func.sum(QuoteLineItem.quantity * QuoteLineItem.unit_price),
                    Decimal("0"),
                ).label("total")
            ).where(
                QuoteLineItem.quote_id == approved_quote.id,
                QuoteLineItem.deleted_at.is_(None),
            )
        )
        quote_total_row = quote_subtotal_result.fetchone()
        quote_subtotal = Decimal(str(quote_total_row.total or 0))

        # milestone.percentage is the share of the scope total
        # Re-read milestone after update to get current state
        milestone = await self.db.get(BillingMilestone, milestone_id)
        if milestone is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Billing milestone not found after update",
            )

        computed_amount = (quote_subtotal * milestone.percentage / Decimal("100")).quantize(
            Decimal("0.01")
        )

        company_id = self._require_tenant_id()
        invoice_number = await self._generate_invoice_number(company_id)

        invoice = Invoice(
            company_id=company_id,
            job_id=None,
            trade_scope_id=trade_scope_id,
            milestone_id=milestone_id,
            quote_id=approved_quote.id,
            invoice_number=invoice_number,
            status=_INVOICE_STATUS_UNPAID,
            tax_rate=approved_quote.tax_rate,
            discount_type=None,
            discount_value=Decimal("0"),
            issued_at=datetime.now(UTC),
        )
        self.db.add(invoice)
        await self.db.flush()  # get invoice.id

        self.db.add(
            InvoiceLineItem(
                invoice_id=invoice.id,
                company_id=company_id,
                item_type="labor",
                description=f"Progress billing: {milestone.name} ({milestone.percentage}%)",
                quantity=Decimal("1"),
                unit="ea",
                unit_price=computed_amount,
                sort_order=0,
            )
        )

        await self.db.flush()
        return await self.repository.get_with_line_items(invoice.id)  # type: ignore[return-value]

    async def aggregate_by_project(self, project_id: uuid.UUID) -> dict:
        """Return per-scope invoice totals and grand totals for a project.

        Returns:
            dict with keys:
            - scopes: list of {scope_id, trade_name, invoice_count, total_billed, total_paid, total_outstanding}
            - total_billed: sum across all scopes
            - total_paid: sum across all scopes
            - total_outstanding: total_billed - total_paid
        """
        result = await self.db.execute(
            select(
                TradeScope.id.label("scope_id"),
                TradeScope.trade_name,
                func.count(Invoice.id).label("invoice_count"),
                func.coalesce(
                    func.sum(
                        select(
                            func.coalesce(
                                func.sum(InvoiceLineItem.quantity * InvoiceLineItem.unit_price),
                                Decimal("0"),
                            )
                        )
                        .where(
                            InvoiceLineItem.invoice_id == Invoice.id,
                            InvoiceLineItem.deleted_at.is_(None),
                        )
                        .correlate(Invoice)
                        .scalar_subquery()
                    ),
                    Decimal("0"),
                ).label("total_billed"),
                func.coalesce(func.sum(Invoice.amount_paid), Decimal("0")).label("total_paid"),
            )
            .select_from(TradeScope)
            .outerjoin(
                Invoice,
                (Invoice.trade_scope_id == TradeScope.id) & Invoice.deleted_at.is_(None),
            )
            .where(
                TradeScope.project_id == project_id,
                TradeScope.deleted_at.is_(None),
            )
            .group_by(TradeScope.id, TradeScope.trade_name)
            .order_by(TradeScope.trade_name)
        )
        rows = result.all()

        scopes = []
        for row in rows:
            total_billed = float(row.total_billed or 0)
            total_paid = float(row.total_paid or 0)
            scopes.append(
                {
                    "scope_id": str(row.scope_id),
                    "trade_name": row.trade_name,
                    "invoice_count": row.invoice_count,
                    "total_billed": total_billed,
                    "total_paid": total_paid,
                    "total_outstanding": round(total_billed - total_paid, 2),
                }
            )

        grand_total_billed = sum(s["total_billed"] for s in scopes)
        grand_total_paid = sum(s["total_paid"] for s in scopes)

        return {
            "project_id": str(project_id),
            "scopes": scopes,
            "total_billed": grand_total_billed,
            "total_paid": grand_total_paid,
            "total_outstanding": round(grand_total_billed - grand_total_paid, 2),
        }
