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

from app.core.base_service import TenantScopedService
from app.features.billing_milestones.models import BillingMilestone  # noqa: F401 — register mapper
from app.features.companies.models import Company
from app.features.invoices.models import Invoice, InvoiceLineItem
from app.features.invoices.repository import InvoiceRepository
from app.features.invoices.schemas import InvoiceCreate, InvoiceUpdate, MarkPaidRequest
from app.features.jobs.models import Job
from app.features.projects.models import Task, TradeScope
from app.features.quotes.models import Quote, QuoteLineItem


class InvoiceService(TenantScopedService[Invoice]):
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
        company = result.scalars().first()
        if company is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Company {company_id} not found",
            )

        company.invoice_sequence = company.invoice_sequence + 1
        prefix = company.invoice_prefix or "INV"
        await self.db.flush()  # persist increment before creating the invoice

        return f"{prefix}-{company.invoice_sequence:04d}"

    async def _append_status_history_event(
        self,
        job_id: uuid.UUID,
        event_type: str,
        user_id: uuid.UUID | None = None,
    ) -> None:
        """Append a status history event to the job's JSONB list."""
        job = await self.db.get(Job, job_id)
        if job is None:
            return
        event = {
            "type": event_type,
            "user_id": str(user_id) if user_id else None,
            "timestamp": datetime.now(UTC).isoformat(),
        }
        current_history = list(job.status_history or [])
        current_history.append(event)
        job.status_history = current_history
        await self.db.flush()

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
        for item in items_data:
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
        await self.db.flush()

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
        # Load job
        job = await self.db.get(Job, job_id)
        if job is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")

        if job.status != "complete":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Job must be in 'complete' status to generate an invoice (current: {job.status})",
            )

        # Find approved quote for this job
        from sqlalchemy.orm import selectinload

        result = await self.db.execute(
            select(Quote)
            .where(
                Quote.job_id == job_id,
                Quote.status == "approved",
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
            status="unpaid",
            tax_rate=approved_quote.tax_rate,
            discount_type=approved_quote.discount_type,
            discount_value=approved_quote.discount_value,
            issued_at=datetime.now(UTC),
        )
        self.db.add(invoice)
        await self.db.flush()  # get invoice.id

        # Copy line items from approved quote
        for item in approved_quote.line_items:
            self.db.add(
                InvoiceLineItem(
                    invoice_id=invoice.id,
                    company_id=company_id,
                    item_type=item.item_type,
                    description=item.description,
                    quantity=item.quantity,
                    unit=item.unit,
                    unit_price=item.unit_price,
                    sort_order=item.sort_order,
                )
            )

        # Transition job to invoiced
        job.status = "invoiced"
        job.version = (job.version or 0) + 1  # Maintain optimistic locking consistency
        await self.db.flush()
        await self._append_status_history_event(job_id, "invoice_generated", user_id)

        # FCM notification to client (fire-and-forget)
        try:
            from app.features.notifications.service import NotificationService

            if job.client_id is not None:
                notif_svc = NotificationService(self.db)
                await notif_svc.send_job_notification(
                    user_id=job.client_id,
                    job_description=job.description,
                    event="invoice_generated",
                    job_id=job.id,
                )
        except Exception:  # noqa: BLE001
            pass

        return await self.repository.get_with_line_items(invoice.id)  # type: ignore[return-value]

    async def generate_manual(
        self,
        data: InvoiceCreate,
        user_id: uuid.UUID,
    ) -> Invoice:
        """Generate a manual invoice for a job (no prior quote required).

        Useful for jobs that skip the quote step (e.g., emergency call-outs).
        Transitions job to 'invoiced'.
        """
        job = await self.db.get(Job, data.job_id)
        if job is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")

        # Manual invoicing allowed from 'complete' status
        if job.status != "complete":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Job must be in 'complete' status to invoice (current: {job.status})",
            )

        company_id = self._require_tenant_id()
        invoice_number = await self._generate_invoice_number(company_id)

        invoice = Invoice(
            company_id=company_id,
            job_id=data.job_id,
            quote_id=data.quote_id,
            invoice_number=invoice_number,
            status="unpaid",
            tax_rate=data.tax_rate,
            discount_type=data.discount_type,
            discount_value=data.discount_value,
            due_date=data.due_date,
            issued_at=data.issued_at or datetime.now(UTC),
        )
        self.db.add(invoice)
        await self.db.flush()  # get invoice.id

        for item in data.line_items:
            self.db.add(
                InvoiceLineItem(
                    invoice_id=invoice.id,
                    company_id=company_id,
                    item_type=item.item_type,
                    description=item.description,
                    quantity=item.quantity,
                    unit=item.unit,
                    unit_price=item.unit_price,
                    sort_order=item.sort_order,
                )
            )

        job.status = "invoiced"
        job.version = (job.version or 0) + 1  # Maintain optimistic locking consistency
        await self.db.flush()
        await self._append_status_history_event(data.job_id, "invoice_generated", user_id)

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
        invoice = await self.repository.get_with_line_items(invoice_id)
        if invoice is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

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
        invoice = await self.repository.get_with_line_items(invoice_id)
        if invoice is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

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
        invoice = await self.repository.get_with_line_items(invoice_id)
        if invoice is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

        # Prevent paid -> unpaid/partially_paid regression
        if invoice.status == "paid" and data.status != "paid":
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
        trade_scope = await self.db.get(TradeScope, trade_scope_id)
        if trade_scope is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"TradeScope {trade_scope_id} not found",
            )

        # Load completed tasks for this scope
        tasks_result = await self.db.execute(
            select(Task)
            .where(
                Task.trade_scope_id == trade_scope_id,
                Task.status == "complete",
                Task.deleted_at.is_(None),
            )
            .order_by(Task.sort_order)
        )
        completed_tasks = list(tasks_result.scalars().all())

        # Look for an approved quote to inherit tax_rate and discounts
        approved_quote_result = await self.db.execute(
            select(Quote)
            .where(
                Quote.trade_scope_id == trade_scope_id,
                Quote.status == "approved",
                Quote.deleted_at.is_(None),
            )
            .order_by(Quote.created_at.desc())
        )
        approved_quote = approved_quote_result.scalars().first()

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
            status="unpaid",
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
        milestone = await self.db.get(BillingMilestone, milestone_id)
        if milestone is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"BillingMilestone {milestone_id} not found",
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
        approved_quote_result = await self.db.execute(
            select(Quote)
            .where(
                Quote.trade_scope_id == trade_scope_id,
                Quote.status == "approved",
                Quote.deleted_at.is_(None),
            )
            .options(selectinload(Quote.line_items))
            .order_by(Quote.created_at.desc())
        )
        approved_quote = approved_quote_result.scalars().first()
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
            status="unpaid",
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
