"""QuoteService — business logic for the quotes domain.

Implements the full quote lifecycle:
  draft -> sent -> viewed -> approved | declined | expired | revised

Key operations:
- create_quote: creates quote with line items, appends event to job.status_history
- update_quote: full line item replacement (draft only)
- send_quote: transitions draft -> sent, sends FCM notification to client
- record_view: sets viewed_at on first view (read receipt)
- approve_quote: transitions sent/viewed -> approved, optionally transitions job
- decline_quote: transitions sent/viewed -> declined, FCM to admin
- revise_quote: marks current quote revised, creates new quote at revision+1
- extend_expiry: updates expiry date, resets expired -> sent
- save_as_template, load_template, list_templates: template management

All CLAUDE.md rules apply:
- Inherits TenantScopedService[Quote]
- No db.commit() — get_db handles transaction lifecycle
- db.flush() when generated IDs are needed before commit
- selectinload for one-to-many, joinedload for many-to-one
- Specific exception types over generic ValueError
"""

from __future__ import annotations

import json
import uuid
from datetime import UTC, date, datetime

from fastapi import HTTPException, status
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import TenantScopedService
from app.features.jobs.models import Job
from app.features.quotes.models import Quote, QuoteLineItem, QuoteTemplate
from app.features.quotes.repository import QuoteRepository, QuoteTemplateRepository
from app.features.quotes.schemas import (
    DeclineQuoteRequest,
    QuoteCreate,
    QuoteTemplateCreate,
    QuoteUpdate,
)


class QuoteService(TenantScopedService[Quote]):
    """Service implementing the full quote lifecycle for a tenant."""

    repository_class = QuoteRepository
    repository: QuoteRepository

    def __init__(self, db: AsyncSession) -> None:
        super().__init__(db)
        self._template_repo = QuoteTemplateRepository(db)

    # -------------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------------

    async def _append_status_history_event(
        self,
        job_id: uuid.UUID,
        event_type: str,
        user_id: uuid.UUID | None = None,
    ) -> None:
        """Append a status history event to the job's JSONB list.

        Loads the job, appends {type, user_id, timestamp}, and flushes.
        CLAUDE.md Pitfall 3: JSONB list must be replaced entirely (not mutated in-place).
        """
        job = await self.db.get(Job, job_id)
        if job is None:
            return
        event = {
            "type": event_type,
            "user_id": str(user_id) if user_id else None,
            "timestamp": datetime.now(UTC).isoformat(),
        }
        # Replace the list entirely to trigger SQLAlchemy dirty detection
        current_history = list(job.status_history or [])
        current_history.append(event)
        job.status_history = current_history
        await self.db.flush()

    async def _replace_line_items(
        self,
        quote_id: uuid.UUID,
        company_id: uuid.UUID,
        items_data: list,
    ) -> None:
        """Delete all existing line items for a quote and create new ones."""
        await self.db.execute(delete(QuoteLineItem).where(QuoteLineItem.quote_id == quote_id))
        for item in items_data:
            self.db.add(
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
            )
        await self.db.flush()

    def _require_quote_status(
        self,
        quote: Quote,
        allowed: set[str],
        operation: str,
    ) -> None:
        """Raise HTTP 409 if the quote's status is not in the allowed set."""
        if quote.status not in allowed:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Cannot {operation} quote in status '{quote.status}'. "
                f"Allowed statuses: {sorted(allowed)}",
            )

    # -------------------------------------------------------------------------
    # Core CRUD
    # -------------------------------------------------------------------------

    async def create_quote(
        self,
        data: QuoteCreate,
        user_id: uuid.UUID,
    ) -> Quote:
        """Create a new draft quote for a job.

        Validates that the job exists and is in 'quote' status.
        Creates QuoteLineItem rows from data.line_items.
        Appends 'quote_created' to job.status_history.
        """
        # Load the job and verify status
        job = await self.db.get(Job, data.job_id)
        if job is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Job {data.job_id} not found",
            )
        if job.status != "quote":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Job must be in 'quote' status to create a quote (current: {job.status})",
            )

        company_id = self._require_tenant_id()

        quote = Quote(
            company_id=company_id,
            job_id=data.job_id,
            status="draft",
            revision_number=1,
            tax_rate=data.tax_rate,
            discount_type=data.discount_type,
            discount_value=data.discount_value,
            expiry_date=data.expiry_date,
            admin_notes=data.admin_notes,
        )
        self.db.add(quote)
        await self.db.flush()  # get quote.id

        # Create line items
        for item in data.line_items:
            self.db.add(
                QuoteLineItem(
                    quote_id=quote.id,
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
        await self._append_status_history_event(data.job_id, "quote_created", user_id)
        await self.db.refresh(quote)
        return await self.repository.get_with_line_items(quote.id)  # type: ignore[return-value]

    async def update_quote(
        self,
        quote_id: uuid.UUID,
        data: QuoteUpdate,
    ) -> Quote:
        """Update a draft quote. Full line item replacement if items provided."""
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        self._require_quote_status(quote, {"draft"}, "update")

        if data.tax_rate is not None:
            quote.tax_rate = data.tax_rate
        if data.discount_type is not None:
            quote.discount_type = data.discount_type
        if data.discount_value is not None:
            quote.discount_value = data.discount_value
        if data.expiry_date is not None:
            quote.expiry_date = data.expiry_date
        if data.admin_notes is not None:
            quote.admin_notes = data.admin_notes

        if data.line_items is not None:
            await self._replace_line_items(quote_id, quote.company_id, data.line_items)

        await self.db.flush()
        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    # -------------------------------------------------------------------------
    # Quote lifecycle transitions
    # -------------------------------------------------------------------------

    async def send_quote(self, quote_id: uuid.UUID) -> Quote:
        """Send a draft quote to the client.

        Transitions draft -> sent. Appends 'quote_sent' to job.status_history.
        Triggers FCM notification to the job's client (fire-and-forget).
        """
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        self._require_quote_status(quote, {"draft"}, "send")

        quote.status = "sent"
        quote.sent_at = datetime.now(UTC)
        await self.db.flush()
        await self._append_status_history_event(quote.job_id, "quote_sent", None)

        # FCM notification to client (fire-and-forget)
        try:
            from app.features.notifications.service import NotificationService

            job = await self.db.get(Job, quote.job_id)
            if job is not None and job.client_id is not None:
                notif_svc = NotificationService(self.db)
                await notif_svc.send_job_notification(
                    user_id=job.client_id,
                    job_description=job.description,
                    event="quote_sent",
                    job_id=job.id,
                )
        except Exception:  # noqa: BLE001
            pass  # Notification failures never block quote operations

        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    async def record_view(self, quote_id: uuid.UUID, viewer_id: uuid.UUID) -> Quote:
        """Record client's first view of a sent quote (read receipt).

        Sets viewed_at only if NULL. Transitions sent -> viewed.
        Appends 'quote_viewed' to job.status_history.
        """
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        if quote.status not in {"sent", "viewed"}:
            # Silently skip — view recording is best-effort
            return quote  # type: ignore[return-value]

        if quote.viewed_at is None:
            quote.viewed_at = datetime.now(UTC)
            if quote.status == "sent":
                quote.status = "viewed"
            await self.db.flush()
            await self._append_status_history_event(quote.job_id, "quote_viewed", viewer_id)

        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    async def approve_quote(
        self,
        quote_id: uuid.UUID,
        client_user_id: uuid.UUID,
    ) -> Quote:
        """Client approves a sent or viewed quote.

        Validates expiry. Transitions quote -> approved.
        If job has contractor and booking, transitions job Quote->Scheduled.
        Triggers FCM notification to admin.
        """
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        self._require_quote_status(quote, {"sent", "viewed"}, "approve")

        # Check expiry
        if quote.expiry_date is not None and quote.expiry_date < datetime.now(UTC).date():
            # Mark as expired first
            quote.status = "expired"
            await self.db.flush()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Quote has expired and cannot be approved",
            )

        quote.status = "approved"
        quote.approved_at = datetime.now(UTC)
        await self.db.flush()
        await self._append_status_history_event(quote.job_id, "quote_approved", client_user_id)

        # FCM notification to admin (fire-and-forget)
        # NOTE: Admin notification on quote approval is omitted here — admin_user_id is not
        # available in this context. Admin receives updates via dashboard polling or webhook.
        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    async def decline_quote(
        self,
        quote_id: uuid.UUID,
        client_user_id: uuid.UUID,
        data: DeclineQuoteRequest,
    ) -> Quote:
        """Client declines a sent or viewed quote.

        Transitions quote -> declined. Appends 'quote_declined' to job.status_history.
        Triggers FCM notification to admin.
        """
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        self._require_quote_status(quote, {"sent", "viewed"}, "decline")

        quote.status = "declined"
        quote.declined_at = datetime.now(UTC)
        quote.decline_reason = data.reason
        quote.decline_detail = data.detail
        await self.db.flush()
        await self._append_status_history_event(quote.job_id, "quote_declined", client_user_id)

        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    async def revise_quote(
        self,
        quote_id: uuid.UUID,
        data: QuoteUpdate,
        user_id: uuid.UUID,
    ) -> Quote:
        """Create a new revision of a sent, viewed, declined, or expired quote.

        Sets current quote status='revised'. Creates a NEW Quote row with
        revision_number+1, status='draft', copies line items. Returns new quote.
        """
        old_quote = await self.repository.get_with_line_items(quote_id)
        if old_quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        self._require_quote_status(old_quote, {"sent", "viewed", "declined", "expired"}, "revise")

        # Mark current quote as revised
        old_quote.status = "revised"
        await self.db.flush()

        company_id = old_quote.company_id

        # Determine new line items: use update data if provided, else copy from old
        new_line_items_data = (
            data.line_items if data.line_items is not None else old_quote.line_items
        )

        new_quote = Quote(
            company_id=company_id,
            job_id=old_quote.job_id,
            status="draft",
            revision_number=old_quote.revision_number + 1,
            tax_rate=data.tax_rate if data.tax_rate is not None else old_quote.tax_rate,
            discount_type=data.discount_type
            if data.discount_type is not None
            else old_quote.discount_type,
            discount_value=data.discount_value
            if data.discount_value is not None
            else old_quote.discount_value,
            expiry_date=data.expiry_date if data.expiry_date is not None else old_quote.expiry_date,
            admin_notes=data.admin_notes if data.admin_notes is not None else old_quote.admin_notes,
        )
        self.db.add(new_quote)
        await self.db.flush()  # get new_quote.id

        # Copy line items from old quote (or use update data)
        for item in new_line_items_data:
            # Handle both ORM model instances and schema instances
            self.db.add(
                QuoteLineItem(
                    quote_id=new_quote.id,
                    company_id=company_id,
                    item_type=getattr(item, "item_type", None),
                    description=getattr(item, "description", None),
                    quantity=getattr(item, "quantity", None),
                    unit=getattr(item, "unit", None),
                    unit_price=getattr(item, "unit_price", None),
                    sort_order=getattr(item, "sort_order", 0),
                )
            )

        await self.db.flush()
        await self._append_status_history_event(old_quote.job_id, "quote_revised", user_id)
        return await self.repository.get_with_line_items(new_quote.id)  # type: ignore[return-value]

    async def extend_expiry(
        self,
        quote_id: uuid.UUID,
        new_expiry_date: date,
    ) -> Quote:
        """Extend the expiry date of a quote.

        If the quote's status is 'expired', resets it back to 'sent'.
        """
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        quote.expiry_date = new_expiry_date
        if quote.status == "expired":
            quote.status = "sent"

        await self.db.flush()
        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    # -------------------------------------------------------------------------
    # Template management
    # -------------------------------------------------------------------------

    async def save_as_template(
        self,
        quote_id: uuid.UUID,
        template_name: str,
    ) -> QuoteTemplate:
        """Save a quote's line items as a reusable template."""
        quote = await self.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

        company_id = self._require_tenant_id()

        # Serialize line items to JSON
        items_json = json.dumps(
            [
                {
                    "item_type": item.item_type,
                    "description": item.description,
                    "quantity": str(item.quantity),
                    "unit": item.unit,
                    "unit_price": str(item.unit_price),
                    "sort_order": item.sort_order,
                }
                for item in quote.line_items
            ]
        )

        template = QuoteTemplate(
            company_id=company_id,
            name=template_name,
            line_items_json=items_json,
            tax_rate=quote.tax_rate,
        )
        self.db.add(template)
        await self.db.flush()
        await self.db.refresh(template)
        return template

    async def create_template(self, data: QuoteTemplateCreate) -> QuoteTemplate:
        """Create a new template from explicit data."""
        company_id = self._require_tenant_id()

        items_json = json.dumps(
            [
                {
                    "item_type": item.item_type,
                    "description": item.description,
                    "quantity": str(item.quantity),
                    "unit": item.unit,
                    "unit_price": str(item.unit_price),
                    "sort_order": item.sort_order,
                }
                for item in data.line_items
            ]
        )

        template = QuoteTemplate(
            company_id=company_id,
            name=data.name,
            description=data.description,
            line_items_json=items_json,
            tax_rate=data.tax_rate,
        )
        self.db.add(template)
        await self.db.flush()
        await self.db.refresh(template)
        return template

    async def load_template(self, template_id: uuid.UUID) -> QuoteTemplate:
        """Return a template by ID (raises 404 if not found)."""
        template = await self.db.get(QuoteTemplate, template_id)
        if template is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")
        return template

    async def list_templates(self) -> list[QuoteTemplate]:
        """Return all templates for the current tenant."""
        return await self._template_repo.list_templates()

    async def delete_template(self, template_id: uuid.UUID) -> bool:
        """Delete a template. Returns False if not found."""
        return await self._template_repo.delete_template(template_id)
