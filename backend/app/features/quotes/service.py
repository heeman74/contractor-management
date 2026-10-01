"""QuoteService — business logic for the quotes domain.

Implements the full quote lifecycle:
  draft -> sent -> viewed -> approved | declined | expired | revised

Key operations:
- create_quote: creates quote with line items, appends event to job.status_history
- update_quote: id-keyed line item reconcile (draft only)
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
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from smtplib import SMTPAuthenticationError

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.base_service import TenantScopedService, entity_or_404
from app.core.config import settings
from app.core.email import EmailService
from app.core.logging_config import get_logger
from app.features.companies.models import Company
from app.features.contracts.models import Contract
from app.features.invoices.models import Invoice
from app.features.jobs.mixins import JobEventsMixin
from app.features.jobs.models import Job
from app.features.jobs.schemas import JobCreate, JobStatus
from app.features.jobs.service import JobService
from app.features.projects.models import Project, TradeScope
from app.features.projects.schemas import ProjectCreate
from app.features.projects.service import ProjectService
from app.features.quotes.models import (
    CO_TARGET_NEW_JOB,
    QUOTE_KIND_CHANGE_ORDER,
    REVIEW_STATE_ACCEPTED,
    REVIEW_STATE_EDITED,
    REVIEW_STATE_UNREVIEWED,
    Quote,
    QuoteLineItem,
    QuoteTemplate,
)
from app.features.quotes.repository import QuoteRepository, QuoteTemplateRepository
from app.features.quotes.schemas import (
    DeclineQuoteRequest,
    QuoteCreate,
    QuoteLineItemCreate,
    QuoteResponse,
    QuoteTemplateCreate,
    QuoteUpdate,
)
from app.features.users.models import User

logger = get_logger(__name__)

# Fallbacks when an approved project-level quote is converted into a project.
_DEFAULT_PROJECT_NAME = "New Project"
_DEFAULT_JOB_FIELD = "General"

# Priced/descriptive fields compared to decide whether a stored AI line was
# touched by a PATCH (D-07/D-08). Deliberately excludes `id`, `sort_order`,
# `review_state` — reordering or an explicit review-state change is not itself
# an edit of the line's content.
PRICED_FIELDS = ("description", "quantity", "unit", "unit_price", "field")

# User-visible and byte-locked by 37-UI-SPEC (state 35) — do not reword.
UNREVIEWED_AI_LINES_DETAIL = (
    "This quote has AI-suggested line items that have not been reviewed. "
    "Accept or edit every suggested line before sending."
)


def review_state_after(row: QuoteLineItem, incoming: QuoteLineItemCreate) -> str:
    """The review state a stored line carries after one PATCH (D-07, D-08).

    Only an AI-originated line has review state at all. A changed priced field
    is an edit no matter what the client claimed, so an edit can never be
    laundered as an untouched acceptance; and an edit never reverts to
    accepted.
    """
    if not row.ai_origin:
        return REVIEW_STATE_UNREVIEWED
    if any(getattr(row, name) != getattr(incoming, name) for name in PRICED_FIELDS):
        return REVIEW_STATE_EDITED
    if row.review_state == REVIEW_STATE_EDITED:
        return REVIEW_STATE_EDITED
    if incoming.review_state == REVIEW_STATE_ACCEPTED:
        return REVIEW_STATE_ACCEPTED
    return row.review_state


class QuoteService(JobEventsMixin, TenantScopedService[Quote]):
    """Service implementing the full quote lifecycle for a tenant."""

    repository_class = QuoteRepository
    repository: QuoteRepository

    def __init__(self, db: AsyncSession) -> None:
        super().__init__(db)
        self._template_repo = QuoteTemplateRepository(db)

    # -------------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------------

    async def _reconcile_line_items(self, quote: Quote, items_data: list) -> None:
        """Match incoming lines to stored rows by id: update in place, insert the
        unmatched, delete the absent. Identity is what every review-state
        guarantee in this phase stands on — a delete-and-recreate destroys it."""
        stored = {item.id: item for item in quote.line_items}
        kept: set[uuid.UUID] = set()
        for position, incoming in enumerate(items_data):
            row = stored.get(incoming.id) if incoming.id is not None else None
            if row is None:
                self.db.add(self._new_line_item(quote, incoming, position))
            else:
                self._apply_line_item(row, incoming, position)
                kept.add(row.id)
        for row_id, row in stored.items():
            if row_id not in kept:
                await self.db.delete(row)
        await self.db.flush()
        # Added/removed rows never went through the collection itself (they were
        # added/deleted directly on the session), so the in-memory `line_items`
        # collection is now stale. Expire it so the next load — including the
        # selectinload the router's response is built from — re-reads it from
        # the DB instead of serving the pre-reconcile Python list.
        self.db.expire(quote, ["line_items"])

    def _new_line_item(
        self, quote: Quote, incoming: QuoteLineItemCreate, position: int
    ) -> QuoteLineItem:
        """Build a fresh hand-built line item — never AI-originated."""
        return QuoteLineItem(
            quote_id=quote.id,
            company_id=quote.company_id,
            item_type=incoming.item_type,
            description=incoming.description,
            quantity=incoming.quantity,
            unit=incoming.unit,
            unit_price=incoming.unit_price,
            sort_order=position,
            field=incoming.field,
            ai_origin=False,
            review_state=REVIEW_STATE_UNREVIEWED,
        )

    @staticmethod
    def _apply_line_item(row: QuoteLineItem, incoming: QuoteLineItemCreate, position: int) -> None:
        """Overwrite a stored line item with the incoming data.

        Computes the new review state BEFORE overwriting the priced fields —
        review_state_after compares the stored values against the incoming ones.
        """
        row.review_state = review_state_after(row, incoming)
        row.item_type = incoming.item_type
        row.description = incoming.description
        row.quantity = incoming.quantity
        row.unit = incoming.unit
        row.unit_price = incoming.unit_price
        row.field = incoming.field
        row.sort_order = position

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

    async def _get_quote_or_404(self, quote_id: uuid.UUID) -> Quote:
        """Fetch a quote with line items eager-loaded, or raise 404."""
        return entity_or_404(await self.repository.get_with_line_items(quote_id), "Quote not found")

    async def _resolve_client_id(self, quote: Quote) -> uuid.UUID | None:
        """Who this quote is addressed to, or None when nothing names them.

        The quote's own client wins. job.client_id is the fallback for quotes
        raised before the column existed, and originating_job_id covers a change
        order, which amends an existing job and so is addressed to that job's
        client by definition.
        """
        client_id = quote.client_id
        for job_id in (quote.job_id, quote.originating_job_id):
            if client_id is not None:
                break
            if job_id is None:
                continue
            job = await self.db.get(Job, job_id)
            client_id = job.client_id if job is not None else None
        return client_id

    async def _require_is_the_client(self, quote: Quote, user_id: uuid.UUID) -> None:
        """403 unless this user is the client the quote is addressed to.

        Row level security scopes a client to their company, not to their own
        quotes, so without this any client of the company could open, view,
        approve or decline a quote priced for somebody else — approval being the
        one that creates the jobs and commits the work.

        A quote naming no client at all is refused rather than allowed. Sending
        already requires one, so anything a client can reach resolves; failing
        closed keeps an unaddressed quote from being approvable by anyone.
        """
        client_id = await self._resolve_client_id(quote)
        if client_id is None or client_id != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This quote is addressed to a different client.",
            )

    async def _require_client(self, quote: Quote) -> uuid.UUID:
        """The client this quote is addressed to, or 400 if there is none.

        Server-side for the same reason as the AI-line gate: a hidden button is
        not a guarantee. Without this a quote moved to `sent` addressed to
        nobody — status flipped, an expiry was stamped, no client was ever
        notified, and it read as sent.

        The quote's own client wins. job.client_id is the fallback for quotes
        raised before the column existed, and originating_job_id covers a change
        order, which amends an existing job and so is addressed to that job's
        client by definition — asking the user to name them again would be
        asking a question the data already answers.
        """
        client_id = quote.client_id
        for job_id in (quote.job_id, quote.originating_job_id):
            if client_id is not None:
                break
            if job_id is None:
                continue
            job = await self.db.get(Job, job_id)
            client_id = job.client_id if job is not None else None
        if client_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "This quote has no client. Add a client before sending it, "
                    "so it reaches someone."
                ),
            )
        return client_id

    def _require_no_unreviewed_ai_lines(self, quote: Quote) -> None:
        """409 while any AI-originated line is still unreviewed (D-07, SC2).

        line_items is already eager-loaded by _get_quote_or_404, so this costs
        no round trip. Server-side by design: a hidden button is not a
        guarantee.
        """
        if any(
            item.ai_origin and item.review_state == REVIEW_STATE_UNREVIEWED
            for item in quote.line_items
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail=UNREVIEWED_AI_LINES_DETAIL
            )

    @staticmethod
    def _serialize_line_items_to_json(items: list) -> str:
        """Serialize quote/schema line items to the template's JSON string."""
        return json.dumps(
            [
                {
                    "item_type": item.item_type,
                    "description": item.description,
                    "quantity": str(item.quantity),
                    "unit": item.unit,
                    "unit_price": str(item.unit_price),
                    "sort_order": item.sort_order,
                }
                for item in items
            ]
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
        # Job quotes validate the linked job; project-level quotes (no job_id and
        # no trade_scope_id) have no job to check.
        if data.job_id is not None:
            job = entity_or_404(await self.db.get(Job, data.job_id), f"Job {data.job_id} not found")
            if job.status != "quote":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        f"Job must be in 'quote' status to create a quote (current: {job.status})"
                    ),
                )

        co_number = (
            await self._prepare_change_order(data)
            if data.quote_kind == QUOTE_KIND_CHANGE_ORDER
            else None
        )

        company_id = self._require_tenant_id()

        quote = Quote(
            company_id=company_id,
            job_id=data.job_id,
            trade_scope_id=data.trade_scope_id,
            client_id=data.client_id,
            title=data.title,
            status="draft",
            quote_number=await self._next_quote_number(company_id),
            revision_number=1,
            tax_rate=data.tax_rate,
            discount_type=data.discount_type,
            discount_value=data.discount_value,
            expiry_date=data.expiry_date,
            admin_notes=data.admin_notes,
            quote_kind=data.quote_kind,
            project_id=data.project_id,
            co_number=co_number,
            change_reason=data.change_reason,
            schedule_impact_days=data.schedule_impact_days,
            originating_job_id=data.originating_job_id,
            co_target=data.co_target,
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
                    field=item.field,
                )
            )

        await self.db.flush()
        if data.job_id is not None:
            await self._append_job_status_event(data.job_id, "quote_created", user_id)
        await self.db.refresh(quote)
        return await self.repository.get_with_line_items(quote.id)  # type: ignore[return-value]

    async def _prepare_change_order(self, data: QuoteCreate) -> int:
        """Validate a change order's project + originating job; return its CO number."""
        project = entity_or_404(
            await self.db.get(Project, data.project_id),
            f"Project {data.project_id} not found",
        )
        originating_job = entity_or_404(
            await self.db.get(Job, data.originating_job_id),
            f"Job {data.originating_job_id} not found",
        )
        if originating_job.project_id != project.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Originating job must belong to the change order's project",
            )
        return await self._next_co_number(project.id)

    async def _next_co_number(self, project_id: uuid.UUID) -> int:
        """The next sequential change-order number for a project (CO-1, CO-2, …)."""
        result = await self.db.execute(
            select(func.max(Quote.co_number)).where(
                Quote.project_id == project_id,
                Quote.quote_kind == QUOTE_KIND_CHANGE_ORDER,
            )
        )
        return (result.scalar_one_or_none() or 0) + 1

    async def _next_quote_number(self, company_id: uuid.UUID) -> int:
        """The next human-facing quote number for a company (#1, #2, …).

        Revisions reuse their root's number, so the max never counts a chain
        twice and the next original quote gets the following integer.
        """
        result = await self.db.execute(
            select(func.max(Quote.quote_number)).where(Quote.company_id == company_id)
        )
        return (result.scalar_one_or_none() or 0) + 1

    async def update_quote(
        self,
        quote_id: uuid.UUID,
        data: QuoteUpdate,
    ) -> Quote:
        """Update a draft quote. Line items are reconciled by id if provided."""
        quote = await self._get_quote_or_404(quote_id)
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
        if data.client_id is not None:
            quote.client_id = data.client_id

        if data.line_items is not None:
            await self._reconcile_line_items(quote, data.line_items)

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
        quote = await self._get_quote_or_404(quote_id)
        self._require_quote_status(quote, {"draft"}, "send")
        self._require_no_unreviewed_ai_lines(quote)
        client_id = await self._require_client(quote)

        quote.status = "sent"
        quote.sent_at = datetime.now(UTC)
        # "Valid today only": default expiry to the send date unless already set.
        if quote.expiry_date is None:
            quote.expiry_date = datetime.now(UTC).date()
        await self.db.flush()
        await self._append_job_status_event(quote.job_id, "quote_sent", None)

        sent = await self.repository.get_with_line_items(quote_id)
        await self._email_quote_to_client(sent, client_id)  # type: ignore[arg-type]
        await self._notify_job_client(quote.job_id, "quote_sent")

        return sent  # type: ignore[return-value]

    async def revert_to_draft(self, quote_id: uuid.UUID) -> Quote:
        """Put a sent quote back to draft so it can be corrected and sent again.

        Allowed from sent and viewed only. An approved quote has already created
        work and a declined one carries the client's answer, so neither is a
        draft that merely went out too early.

        Clears the send receipts, since a draft has not been sent or seen. The
        expiry is cleared only when it matches the day the quote went out: that
        is the "valid today only" default the send stamps on, so keeping it would
        leave the next send carrying a date nobody chose — and once that date is
        in the past, the client cannot approve. An expiry the user picked
        deliberately is left alone.
        """
        quote = await self._get_quote_or_404(quote_id)
        self._require_quote_status(quote, {"sent", "viewed"}, "revert to draft")

        was_auto_expiry = (
            quote.expiry_date is not None
            and quote.sent_at is not None
            and quote.expiry_date == quote.sent_at.date()
        )

        quote.status = "draft"
        quote.sent_at = None
        quote.viewed_at = None
        if was_auto_expiry:
            quote.expiry_date = None

        await self.db.flush()
        await self._append_job_status_event(quote.job_id, "quote_reverted_to_draft", None)

        return await self.repository.get_with_line_items(quote_id)  # type: ignore[return-value]

    async def _email_quote_to_client(self, quote: Quote, client_id: uuid.UUID) -> None:
        """Email the quote to the client it is addressed to.

        Sending is part of the operation rather than fire-and-forget. A push
        notification was the only thing a send ever produced, so a quote could be
        marked sent, answer 200, and reach the client's inbox never — which is
        indistinguishable from success to whoever pressed the button. If the mail
        cannot go out the request fails, the transaction rolls back, and the
        quote stays a draft that can be sent again.
        """
        client = await self.db.get(User, client_id)
        if client is None or not client.email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This quote's client has no email address to send to.",
            )

        company = await self.db.get(Company, quote.company_id)
        quote_url = f"{settings.public_web_url.rstrip('/')}/quotes/{quote.id}"
        # The same total the API returns, not a second implementation of it.
        # model_validate alone leaves the totals on their zero defaults — they
        # are computed, and from_orm_with_totals is what computes them.
        total = QuoteResponse.from_orm_with_totals(quote).total

        try:
            await EmailService().send_quote_to_client(
                to=client.email,
                quote_number=f"#{quote.quote_number}",
                company_name=company.name if company is not None else "Your contractor",
                total=f"${total:,.2f}",
                quote_url=quote_url,
                expiry_date=quote.expiry_date.isoformat() if quote.expiry_date else None,
            )
        except SMTPAuthenticationError as exc:
            # The mail provider rejected our credentials: nobody can fix this by
            # pressing the button again, so do not invite them to. Gmail answers
            # 535 5.7.8 here when given an account password instead of an app
            # password.
            logger.error(
                "quote_email_credentials_rejected",
                quote_id=str(quote.id),
                recipient=client.email,
                smtp_code=exc.smtp_code,
                smtp_error=str(exc.smtp_error),
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=(
                    "The email service rejected our sign-in, so the quote was not "
                    "sent and is still a draft. An administrator needs to fix the "
                    "mail settings — retrying will not help."
                ),
            ) from exc
        except Exception as exc:
            logger.error(
                "quote_email_failed",
                quote_id=str(quote.id),
                recipient=client.email,
                error=repr(exc),
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Could not email the quote to the client. The quote is still a draft.",
            ) from exc

    async def record_view(self, quote_id: uuid.UUID, viewer_id: uuid.UUID) -> Quote:
        """Record client's first view of a sent quote (read receipt).

        Sets viewed_at only if NULL. Transitions sent -> viewed.
        Appends 'quote_viewed' to job.status_history.
        """
        quote = await self._get_quote_or_404(quote_id)
        await self._require_is_the_client(quote, viewer_id)

        if quote.status not in {"sent", "viewed"}:
            # Silently skip — view recording is best-effort
            return quote  # type: ignore[return-value]

        if quote.viewed_at is None:
            quote.viewed_at = datetime.now(UTC)
            if quote.status == "sent":
                quote.status = "viewed"
            await self.db.flush()
            await self._append_job_status_event(quote.job_id, "quote_viewed", viewer_id)

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
        quote = await self._get_quote_or_404(quote_id)
        await self._require_is_the_client(quote, client_user_id)
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

        if quote.quote_kind == QUOTE_KIND_CHANGE_ORDER:
            # Change order → add work to the existing project (new job or extend).
            await self._execute_change_order(quote, client_user_id)
        elif quote.job_id is not None:
            await self._append_job_status_event(quote.job_id, "quote_approved", client_user_id)
        elif quote.trade_scope_id is None and quote.project_id is None:
            # Project-level quote → create the project and its per-field jobs.
            await self._convert_project_quote(quote, client_user_id)

        # FCM notification to admin (fire-and-forget)
        # NOTE: Admin notification on quote approval is omitted here — admin_user_id is not
        # available in this context. Admin receives updates via dashboard polling or webhook.
        return await self._apply_budget_delta(quote_id)

    async def _apply_budget_delta(self, quote_id: uuid.UUID) -> Quote:
        """Budget delta (BUDG-04): same transaction as the approval, so the status
        change, the budget adjustment and any threshold alert commit together.
        Reuses the one get_with_line_items load approve_quote returns anyway."""
        from app.features.finance.budget_service import BudgetService  # local: quotes -> finance

        approved = await self.repository.get_with_line_items(quote_id)
        await BudgetService(self.db).apply_quote_delta(approved)
        return approved  # type: ignore[return-value]

    async def _execute_change_order(self, quote: Quote, client_user_id: uuid.UUID) -> None:
        """Apply an approved change order: add or extend a job, shift schedule, roll budget.

        co_target='new_job' creates a job in the project (traced by created_job_id);
        'existing_job' appends the change scope to the originating job's notes. Then
        the schedule impact extends the project's completion and the full change-order
        amount is added to the project budget.

        Re-approving a REVISION of an already-approved change order takes the
        amend path instead: the job it created and the scope it added already
        exist, so only what actually changed is applied — the schedule-day
        difference, and the money as a chain delta through the shipped
        `apply_quote_delta`. Running the full path twice would add a second job
        for the same work and count its amount into the budget twice.
        """
        previous = await self.repository.previous_approved_in_chain(quote)
        if previous is not None:
            await self._amend_change_order(quote, previous)
            return

        company_id = self._require_tenant_id()
        originating_job = entity_or_404(
            await self.db.get(Job, quote.originating_job_id),
            "Originating job not found",
        )

        if quote.co_target == CO_TARGET_NEW_JOB:
            job = await JobService(self.db).create_job(
                self._build_change_order_job(quote, originating_job),
                user_id=client_user_id,
                company_id=company_id,
            )
            quote.created_job_id = job.id
        else:
            self._append_change_order_to_job(quote, originating_job)

        await self._apply_schedule_impact(quote)
        await self.db.flush()

        from app.features.finance.budget_service import BudgetService  # quotes -> finance

        await BudgetService(self.db).apply_change_order(quote)

    async def _amend_change_order(self, quote: Quote, previous: Quote) -> None:
        """Apply only what a revised change order changed against its predecessor.

        The budget is deliberately left to `apply_quote_delta`, which every
        approval already runs: it applies this chain's revision delta, so adding
        the full amount here as well would count the same scope twice.
        """
        await self._shift_schedule(quote, self._schedule_day_delta(quote, previous))
        await self.db.flush()

    @staticmethod
    def _schedule_day_delta(quote: Quote, previous: Quote) -> int:
        """Extra days this revision adds beyond what its predecessor already shifted."""
        return (quote.schedule_impact_days or 0) - (previous.schedule_impact_days or 0)

    def _build_change_order_job(self, quote: Quote, originating_job: Job) -> JobCreate:
        """Assemble the new job an approved change order creates in the project."""
        labor = [item for item in quote.line_items if item.item_type == "labor"]
        description = (
            (quote.change_reason or "").strip()
            or "; ".join(item.description for item in labor).strip()
            or f"Change order CO-{quote.co_number}"
        )
        return JobCreate(
            description=description,
            trade_type=originating_job.trade_type,
            status=JobStatus.quote,
            project_id=quote.project_id,
            notes=self._change_order_note(quote),
        )

    def _append_change_order_to_job(self, quote: Quote, originating_job: Job) -> None:
        """Fold an approved change order's scope + cost into the originating job's notes."""
        summary = "; ".join(
            item.description for item in quote.line_items if item.item_type == "labor"
        )
        total = self._line_items_total(quote)
        addendum = (
            f"[CO-{quote.co_number}] {quote.change_reason or 'Added scope'}"
            f"{f': {summary}' if summary else ''}. Added ${total:.2f}."
        )
        originating_job.notes = (
            f"{originating_job.notes}\n{addendum}" if originating_job.notes else addendum
        )

    def _change_order_note(self, quote: Quote) -> str:
        """Notes for a change-order job: materials list + quoted total."""
        materials = [item for item in quote.line_items if item.item_type == "material"]
        lines = [f"Change order CO-{quote.co_number}."]
        if materials:
            lines.append(
                "Materials: "
                + ", ".join(f"{m.description} ({m.quantity} {m.unit})" for m in materials)
            )
        lines.append(f"Quoted total: ${self._line_items_total(quote):.2f}")
        return "\n".join(lines)

    @staticmethod
    def _line_items_total(quote: Quote) -> Decimal:
        """Sum of quantity × unit price across the quote's line items."""
        return sum((item.quantity * item.unit_price for item in quote.line_items), Decimal("0"))

    async def _apply_schedule_impact(self, quote: Quote) -> None:
        """Extend the project's target completion by the change order's schedule days."""
        await self._shift_schedule(quote, quote.schedule_impact_days or 0)

    async def _shift_schedule(self, quote: Quote, days: int) -> None:
        """Move the project's target completion by `days` (negative moves it in).

        A project with no target end date has nothing to shift — a change order
        never invents a completion date the plan never had.
        """
        if not days or quote.project_id is None:
            return
        project = await self.db.get(Project, quote.project_id)
        if project is not None and project.target_end_date is not None:
            project.target_end_date = project.target_end_date + timedelta(days=days)

    async def _convert_project_quote(self, quote: Quote, client_user_id: uuid.UUID) -> None:
        """Create a project from an approved project-level quote — one job per field.

        Line items are grouped by their `field`; within a group, labor items
        describe the work and material items become the job's notes. Each group
        becomes a job whose trade_type is the field. The quote is linked to the
        created project via quote.project_id.
        """
        company_id = self._require_tenant_id()

        result = await self.db.execute(
            select(QuoteLineItem)
            .where(QuoteLineItem.quote_id == quote.id)
            .order_by(QuoteLineItem.sort_order)
        )
        line_items = list(result.scalars().all())

        project = await ProjectService(self.db).create(
            ProjectCreate(name=quote.title or _DEFAULT_PROJECT_NAME),
            user_id=client_user_id,
        )
        await self.db.flush()

        job_svc = JobService(self.db)
        for field_name, items in self._group_items_by_field(line_items).items():
            await job_svc.create_job(
                self._build_job_from_field(project.id, field_name, items),
                user_id=client_user_id,
                company_id=company_id,
            )

        quote.project_id = project.id
        await self.db.flush()

    @staticmethod
    def _group_items_by_field(
        line_items: list[QuoteLineItem],
    ) -> dict[str, list[QuoteLineItem]]:
        """Group line items by field, preserving first-seen (sort) order."""
        groups: dict[str, list[QuoteLineItem]] = {}
        for item in line_items:
            key = (item.field or _DEFAULT_JOB_FIELD).strip() or _DEFAULT_JOB_FIELD
            groups.setdefault(key, []).append(item)
        return groups

    @staticmethod
    def _build_job_from_field(
        project_id: uuid.UUID, field_name: str, items: list[QuoteLineItem]
    ) -> JobCreate:
        """Assemble a JobCreate for one field group of an approved project quote."""
        labor = [i for i in items if i.item_type == "labor"]
        materials = [i for i in items if i.item_type == "material"]

        description = "; ".join(i.description for i in labor).strip()
        if not description:
            description = f"{field_name} work"

        note_lines: list[str] = []
        if materials:
            note_lines.append(
                "Materials: "
                + ", ".join(f"{i.description} ({i.quantity} {i.unit})" for i in materials)
            )
        total = sum((i.quantity * i.unit_price for i in items), Decimal("0"))
        note_lines.append(f"Quoted total: ${total:.2f}")

        return JobCreate(
            description=description,
            trade_type=field_name,
            status=JobStatus.quote,
            project_id=project_id,
            notes="\n".join(note_lines),
        )

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
        quote = await self._get_quote_or_404(quote_id)
        await self._require_is_the_client(quote, client_user_id)
        self._require_quote_status(quote, {"sent", "viewed"}, "decline")

        quote.status = "declined"
        quote.declined_at = datetime.now(UTC)
        quote.decline_reason = data.reason
        quote.decline_detail = data.detail
        await self.db.flush()
        await self._append_job_status_event(quote.job_id, "quote_declined", client_user_id)

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
        old_quote = await self._get_quote_or_404(quote_id)
        # "approved" is revisable: without it no chain could contain a second
        # approval and BUDG-04's budget delta would be unreachable. Margin stays
        # correct automatically — the old row flips to 'revised' and drops out of
        # the approved-quote revenue leg while the new approval takes over.
        self._require_quote_status(
            old_quote, {"sent", "viewed", "declined", "expired", "approved"}, "revise"
        )

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
            client_id=old_quote.client_id,
            # Anchors must survive revision: dropping them orphaned revised scope
            # quotes (both anchors null), breaking D-06 budget linkage AND the
            # Phase 33 approved-quote revenue leg. Pre-existing bug, fixed here.
            trade_scope_id=old_quote.trade_scope_id,
            project_id=old_quote.project_id,
            # Explicit chain link — revision_number + shared anchor is ambiguous
            # when multiple independent chains exist at one anchor.
            revised_from_quote_id=old_quote.id,
            status="draft",
            # A revision is the same quote re-issued — keep its number stable.
            quote_number=old_quote.quote_number,
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
            # Change-order identity survives revision for the same reason the
            # anchors above do: a revised CO is still CO-N against the same
            # project and originating job. Dropping these silently demoted the
            # revision to a standard quote, so re-approving it added no job and
            # shifted no schedule. created_job_id carries forward too — the work
            # it points at was already created by the first approval.
            quote_kind=old_quote.quote_kind,
            co_number=old_quote.co_number,
            change_reason=old_quote.change_reason,
            schedule_impact_days=old_quote.schedule_impact_days,
            originating_job_id=old_quote.originating_job_id,
            co_target=old_quote.co_target,
            created_job_id=old_quote.created_job_id,
        )
        self.db.add(new_quote)
        await self.db.flush()  # get new_quote.id

        # Copy line items from old quote (or use update data). AI provenance
        # (ai_origin/confidence_band/basis/suggested_at) carries forward for the
        # variance loop (D-08), but review_state always resets to unreviewed — a
        # revision is a new document that must be reviewed again.
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
                    field=getattr(item, "field", None),
                    ai_origin=getattr(item, "ai_origin", False),
                    review_state=REVIEW_STATE_UNREVIEWED,
                    confidence_band=getattr(item, "confidence_band", None),
                    basis=getattr(item, "basis", None),
                    suggested_at=getattr(item, "suggested_at", None),
                )
            )

        await self.db.flush()
        await self._append_job_status_event(old_quote.job_id, "quote_revised", user_id)
        return await self.repository.get_with_line_items(new_quote.id)  # type: ignore[return-value]

    async def extend_expiry(
        self,
        quote_id: uuid.UUID,
        new_expiry_date: date,
    ) -> Quote:
        """Extend the expiry date of a quote.

        If the quote's status is 'expired', resets it back to 'sent'.
        """
        quote = await self._get_quote_or_404(quote_id)

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
        quote = await self._get_quote_or_404(quote_id)
        company_id = self._require_tenant_id()
        items_json = self._serialize_line_items_to_json(quote.line_items)

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
        items_json = self._serialize_line_items_to_json(data.line_items)

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
        return entity_or_404(await self.db.get(QuoteTemplate, template_id), "Template not found")

    async def list_change_orders(self, project_id: uuid.UUID) -> list[Quote]:
        """A project's change orders, ordered by CO number."""
        return await self.repository.list_change_orders_for_project(project_id)

    async def list_templates(self) -> list[QuoteTemplate]:
        """Return all templates for the current tenant."""
        return await self._template_repo.list_templates()

    async def delete_quote(self, quote_id: uuid.UUID) -> None:
        """Soft-delete a quote, refusing when something downstream depends on it.

        Soft because the house pattern is `deleted_at` and every list query
        already filters on it, so hiding the row needs no read-path changes and
        the record survives for audit.

        An approved quote is refused outright: approval is what creates the jobs
        or project, so deleting it would hide the origin of work that exists.
        Invoices, contracts and later revisions are refused for the same reason —
        each is a row that points here, and the quote is the explanation for it.
        A draft, or a quote that went nowhere, has no such dependents and is the
        case this exists for.
        """
        quote = await self._get_quote_or_404(quote_id)

        if quote.status == "approved":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "This quote was approved, so the work it created would lose its "
                    "origin. Delete is only for quotes that produced nothing."
                ),
            )

        blocker = await self._first_dependent(quote_id)
        if blocker is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"This quote has {blocker} attached, so it cannot be deleted.",
            )

        quote.deleted_at = datetime.now(UTC)
        await self.db.flush()

    async def _first_dependent(self, quote_id: uuid.UUID) -> str | None:
        """The name of the first thing still pointing at this quote, if any."""
        invoice = (
            await self.db.execute(
                select(Invoice.id)
                .where(Invoice.quote_id == quote_id)
                .where(Invoice.deleted_at.is_(None))
                .limit(1)
            )
        ).first()
        if invoice is not None:
            return "an invoice"

        revision = (
            await self.db.execute(
                select(Quote.id)
                .where(Quote.revised_from_quote_id == quote_id)
                .where(Quote.deleted_at.is_(None))
                .limit(1)
            )
        ).first()
        if revision is not None:
            return "a later revision"

        contract = (
            await self.db.execute(
                select(Contract.id)
                .where(Contract.quote_id == quote_id)
                .where(Contract.deleted_at.is_(None))
                .limit(1)
            )
        ).first()
        if contract is not None:
            return "a contract"

        return None

    async def delete_template(self, template_id: uuid.UUID) -> bool:
        """Delete a template. Returns False if not found."""
        return await self._template_repo.delete_template(template_id)

    # -------------------------------------------------------------------------
    # Trade-scope quoting (Phase 25)
    # -------------------------------------------------------------------------

    async def create_for_scope(
        self,
        trade_scope_id: uuid.UUID,
        data: QuoteCreate,
        user_id: uuid.UUID,
    ) -> Quote:
        """Create a draft quote scoped to a specific trade scope.

        Validates that the trade scope exists. Overrides data.trade_scope_id
        and sets job_id=None regardless of what was in the request body.
        """
        entity_or_404(
            await self.db.get(TradeScope, trade_scope_id),
            f"TradeScope {trade_scope_id} not found",
        )

        company_id = self._require_tenant_id()

        quote = Quote(
            company_id=company_id,
            job_id=None,
            trade_scope_id=trade_scope_id,
            # A scope quote has no job to inherit a client from, so it must carry
            # its own — and sending requires one.
            client_id=data.client_id,
            status="draft",
            quote_number=await self._next_quote_number(company_id),
            revision_number=1,
            tax_rate=data.tax_rate,
            discount_type=data.discount_type,
            discount_value=data.discount_value,
            expiry_date=data.expiry_date,
            admin_notes=data.admin_notes,
        )
        self.db.add(quote)
        await self.db.flush()  # get quote.id

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
        await self.db.refresh(quote)
        result = await self.db.execute(
            select(Quote).where(Quote.id == quote.id).options(selectinload(Quote.line_items))
        )
        return result.scalars().first()  # type: ignore[return-value]

    async def list_by_scope(self, trade_scope_id: uuid.UUID) -> list[Quote]:
        """List all non-deleted quotes for a trade scope, newest first."""
        result = await self.db.execute(
            select(Quote)
            .where(
                Quote.trade_scope_id == trade_scope_id,
                Quote.deleted_at.is_(None),
            )
            .options(selectinload(Quote.line_items))
            .order_by(Quote.created_at.desc())
        )
        return list(result.scalars().all())

    async def aggregate_by_project(self, project_id: uuid.UUID) -> dict:
        """Return per-scope quote totals and grand total for a project.

        Returns:
            dict with keys:
            - scopes: list of {scope_id, trade_name, quote_count, subtotal}
            - grand_total: sum of all scope subtotals
        """
        result = await self.db.execute(
            select(
                TradeScope.id.label("scope_id"),
                TradeScope.trade_name,
                func.count(Quote.id).label("quote_count"),
                func.coalesce(
                    func.sum(QuoteLineItem.quantity * QuoteLineItem.unit_price),
                    Decimal("0"),
                ).label("subtotal"),
            )
            .select_from(TradeScope)
            .outerjoin(
                Quote,
                (Quote.trade_scope_id == TradeScope.id) & Quote.deleted_at.is_(None),
            )
            .outerjoin(
                QuoteLineItem,
                (QuoteLineItem.quote_id == Quote.id) & QuoteLineItem.deleted_at.is_(None),
            )
            .where(
                TradeScope.project_id == project_id,
                TradeScope.deleted_at.is_(None),
            )
            .group_by(TradeScope.id, TradeScope.trade_name)
            .order_by(TradeScope.trade_name)
        )
        rows = result.all()

        scopes = [
            {
                "scope_id": str(row.scope_id),
                "trade_name": row.trade_name,
                "quote_count": row.quote_count,
                "subtotal": float(row.subtotal or 0),
            }
            for row in rows
        ]
        grand_total = sum(s["subtotal"] for s in scopes)

        return {
            "project_id": str(project_id),
            "scopes": scopes,
            "grand_total": grand_total,
        }
