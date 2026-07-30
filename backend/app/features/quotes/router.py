"""Quotes API router — REST endpoints for the quote lifecycle domain.

Endpoints (declared in order to prevent FastAPI path parameter shadowing):

Static/collection paths declared BEFORE /{quote_id} parameterized paths:
  POST   /quotes/templates          — save template (admin)
  GET    /quotes/templates          — list templates (admin)
  GET    /quotes/templates/{id}     — get template (admin)
  DELETE /quotes/templates/{id}     — delete template (admin, 204)
  GET    /quotes/for-job/{job_id}   — latest quote for a job
  POST   /quotes/                   — create draft quote (admin)
  GET    /quotes/{quote_id}         — get quote with line items; records view for client
  PATCH  /quotes/{quote_id}         — update draft quote (admin)
  POST   /quotes/{quote_id}/send    — send to client (admin)
  POST   /quotes/{quote_id}/approve — approve (client)
  POST   /quotes/{quote_id}/decline — decline with reason (client)
  POST   /quotes/{quote_id}/revise  — create revision (admin)
  POST   /quotes/{quote_id}/extend  — extend expiry date (admin)
  GET    /quotes/{quote_id}/pdf     — download PDF (admin or client)
  GET    /quotes/{quote_id}/variance — quoted-vs-actual for this quote (finance.view, FINAI-05)

  /projects/{project_id}/financials/quote-variance — the project drill-down's
  per-anchor quoted-vs-actual table (finance.view, FINAI-05), on its own router
  below (mirrors scope_quote_router's separate-router precedent).

Design notes:
- Plain APIRouter (not CRUDRouter) — custom domain operations per Phase 3 pattern.
- All logic delegated to QuoteService. Router: auth, schema validation, HTTP codes.
- Role enforcement: admin-only vs client-only checked via current_user.roles.
- GET /{quote_id}: if requester is client, calls record_view() for read receipt.
- PDF download: streams WeasyPrint bytes as application/pdf response.
"""

from __future__ import annotations

import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_service import entity_or_404
from app.core.database import get_db
from app.core.permissions import FINANCE_VIEW_PERMISSION
from app.core.security import (
    CurrentUser,
    effective_permissions,
    get_current_user,
    require_permission,
    require_roles,
)
from app.features.companies.models import Company
from app.features.jobs.models import Job
from app.features.pdf.service import pdf_service
from app.features.quotes.schemas import (
    DeclineQuoteRequest,
    ProjectQuoteVarianceResponse,
    QuoteCreate,
    QuoteResponse,
    QuoteTemplateCreate,
    QuoteTemplateResponse,
    QuoteUpdate,
    QuoteVarianceResponse,
    to_project_quote_variance_response,
    to_quote_variance_response,
)
from app.features.quotes.service import QuoteService
from app.features.quotes.variance_service import QuoteVarianceService
from app.features.users.models import User


class ExtendExpiryRequest(BaseModel):
    """Request body for extending a quote's expiry date."""

    new_expiry_date: date


# isort: split
# Side-effect import: ensure all referenced mappers are registered before
# configure_mappers() triggers on Quote relationship resolution.
import app.features.invoices.models  # noqa: E402
import app.features.scheduling.models  # noqa: E402
import app.features.users.models  # noqa: E402, F401

router = APIRouter(prefix="/quotes", tags=["quotes"])

# ---------------------------------------------------------------------------
# Trade-scope quote router — Phase 25
# Separate router so /api/trade-scopes/{scope_id}/quotes doesn't shadow /quotes
# ---------------------------------------------------------------------------
scope_quote_router = APIRouter(prefix="/trade-scopes/{scope_id}", tags=["trade-scope-quotes"])

# ---------------------------------------------------------------------------
# Project quote-variance router — Phase 37 (FINAI-05)
# Lives in the quotes feature (not finance/router.py): every definition it needs
# is quote-domain, and quotes -> finance is the established one-way import
# direction in this codebase (finance already imports quotes at
# finance/repository.py:39, budget_service.py:42, portfolio_repository.py:57),
# so declaring the route here adds no new edge and no cycle.
# ---------------------------------------------------------------------------
project_variance_router = APIRouter(
    prefix="/projects/{project_id}/financials", tags=["quote-variance"]
)


def _require_client(current_user: CurrentUser) -> None:
    """Raise 403 if the current user is not a client."""
    require_roles(current_user, "client", detail="Client role required")


async def finance_view_granted(
    current_user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> bool:
    """Whether this caller may see the AI lines' cost-derived fields."""
    return FINANCE_VIEW_PERMISSION in await effective_permissions(current_user, db)


# ---------------------------------------------------------------------------
# Template routes — MUST be declared before /{quote_id} to prevent shadowing
# ---------------------------------------------------------------------------


@router.post("/templates", response_model=QuoteTemplateResponse, status_code=201)
async def save_template(
    data: QuoteTemplateCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteTemplateResponse:
    """Create a new quote template from explicit data (admin only)."""
    await require_permission("quotes.create")(current_user, db)
    svc = QuoteService(db)
    template = await svc.create_template(data)
    return QuoteTemplateResponse.model_validate(template)


@router.get("/templates", response_model=list[QuoteTemplateResponse])
async def list_templates(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[QuoteTemplateResponse]:
    """List all quote templates for the current tenant (admin only)."""
    await require_permission("quotes.view")(current_user, db)
    svc = QuoteService(db)
    templates = await svc.list_templates()
    return [QuoteTemplateResponse.model_validate(t) for t in templates]


@router.get("/templates/{template_id}", response_model=QuoteTemplateResponse)
async def get_template(
    template_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteTemplateResponse:
    """Get a specific quote template (admin only)."""
    await require_permission("quotes.view")(current_user, db)
    svc = QuoteService(db)
    template = await svc.load_template(template_id)
    return QuoteTemplateResponse.model_validate(template)


@router.delete("/templates/{template_id}", response_model=None, status_code=204)
async def delete_template(
    template_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> None:
    """Delete a quote template (admin only)."""
    await require_permission("quotes.delete")(current_user, db)
    svc = QuoteService(db)
    deleted = await svc.delete_template(template_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Template not found")


@router.get("/", response_model=list[QuoteResponse])
async def list_quotes(
    status: str | None = None,
    offset: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> list[QuoteResponse]:
    """List all active (non-deleted, non-revised) quotes for the tenant (admin only).

    Optional `status` query param filters by quote status (e.g. draft, sent, approved).
    Paginated via offset/limit.
    """
    await require_permission("quotes.view")(current_user, db)
    svc = QuoteService(db)
    quotes = await svc.repository.get_active_quotes()
    if status is not None:
        quotes = [q for q in quotes if q.status == status]
    # Apply pagination
    quotes = quotes[offset : offset + min(limit, 200)]
    return [QuoteResponse.from_orm_with_totals(q, include_finance=include_finance) for q in quotes]


@router.get("/for-job/{job_id}", response_model=QuoteResponse)
async def get_quote_for_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Get the latest non-revised quote for a job."""
    svc = QuoteService(db)
    quote = entity_or_404(await svc.repository.get_for_job(job_id), "No quote found for job")
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


# ---------------------------------------------------------------------------
# Core quote routes
# ---------------------------------------------------------------------------


@router.post("/", response_model=QuoteResponse, status_code=201)
async def create_quote(
    data: QuoteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Create a new draft quote for a job (admin only)."""
    await require_permission("quotes.create")(current_user, db)
    svc = QuoteService(db)
    quote = await svc.create_quote(data, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.get("/{quote_id}", response_model=QuoteResponse)
async def get_quote(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Get a quote with line items.

    If the requester is a client, records their first view (read receipt).
    """
    svc = QuoteService(db)

    if "client" in current_user.roles:
        # record_view triggers status sent -> viewed and appends status_history
        quote = await svc.record_view(quote_id, current_user.user_id)
    else:
        quote = entity_or_404(await svc.repository.get_with_line_items(quote_id), "Quote not found")

    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.patch("/{quote_id}", response_model=QuoteResponse)
async def update_quote(
    quote_id: uuid.UUID,
    data: QuoteUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Update a draft quote (admin only). Line items are reconciled by id if provided."""
    await require_permission("quotes.edit")(current_user, db)
    svc = QuoteService(db)
    quote = await svc.update_quote(quote_id, data)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.post("/{quote_id}/send", response_model=QuoteResponse)
async def send_quote(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Send a draft quote to the client (admin only)."""
    await require_permission("quotes.edit")(current_user, db)
    svc = QuoteService(db)
    quote = await svc.send_quote(quote_id)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.post("/{quote_id}/approve", response_model=QuoteResponse)
async def approve_quote(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Approve a sent or viewed quote (client only)."""
    _require_client(current_user)
    svc = QuoteService(db)
    quote = await svc.approve_quote(quote_id, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.post("/{quote_id}/decline", response_model=QuoteResponse)
async def decline_quote(
    quote_id: uuid.UUID,
    data: DeclineQuoteRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Decline a sent or viewed quote with reason (client only)."""
    _require_client(current_user)
    svc = QuoteService(db)
    quote = await svc.decline_quote(quote_id, current_user.user_id, data)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.post("/{quote_id}/revise", response_model=QuoteResponse, status_code=201)
async def revise_quote(
    quote_id: uuid.UUID,
    data: QuoteUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Create a new revision of a sent/viewed/declined/expired quote (admin only)."""
    await require_permission("quotes.edit")(current_user, db)
    svc = QuoteService(db)
    new_quote = await svc.revise_quote(quote_id, data, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(new_quote, include_finance=include_finance)


@router.post("/{quote_id}/extend", response_model=QuoteResponse)
async def extend_expiry(
    quote_id: uuid.UUID,
    data: ExtendExpiryRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Extend the expiry date of a quote. Resets expired -> sent (admin only)."""
    await require_permission("quotes.edit")(current_user, db)
    svc = QuoteService(db)
    quote = await svc.extend_expiry(quote_id, data.new_expiry_date)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@router.get("/{quote_id}/pdf")
async def download_quote_pdf(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Download a quote as a PDF file (admin or client)."""
    svc = QuoteService(db)
    quote = entity_or_404(await svc.repository.get_with_line_items(quote_id), "Quote not found")

    # Load the company for branding
    company = entity_or_404(await db.get(Company, quote.company_id), "Company not found")

    # Resolve the client (quote -> job -> client User) for the "Prepared For" block.
    client = None
    if quote.job_id is not None:
        job = await db.get(Job, quote.job_id)
        if job is not None and job.client_id is not None:
            client = await db.get(User, job.client_id)

    pdf_bytes = await pdf_service.generate_quote_pdf(quote, company, client=client)
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="quote-{quote_id}.pdf"',
            "Content-Length": str(len(pdf_bytes)),
        },
    )


@router.get("/{quote_id}/variance", response_model=QuoteVarianceResponse)
async def get_quote_variance(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteVarianceResponse:
    """One quote's quoted-vs-actual (FINAI-05).

    finance.view-gated — this is the backend half of the Trap 8 double lock, and
    the half that actually holds: `/quotes/[id]` has no UI gate today, so a UI
    gate over an ungated endpoint would not be a lock.
    """
    await require_permission("finance.view")(current_user, db)
    result = await QuoteVarianceService(db).quote_variance(quote_id)
    return to_quote_variance_response(result)


# ---------------------------------------------------------------------------
# Trade-scope quote endpoints (Phase 25)
# ---------------------------------------------------------------------------


@scope_quote_router.post("/quotes", response_model=QuoteResponse, status_code=201)
async def create_scope_quote(
    scope_id: uuid.UUID,
    data: QuoteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> QuoteResponse:
    """Create a draft quote scoped to a trade scope (admin only).

    The quote is linked to the trade scope, not a job. scope_id in the URL
    overrides any trade_scope_id or job_id in the request body.
    """
    await require_permission("quotes.create")(current_user, db)
    # Provide a dummy trade_scope_id to satisfy the QuoteCreate model_validator;
    # create_for_scope overrides it with the URL scope_id anyway.
    data_with_scope = QuoteCreate(
        trade_scope_id=scope_id,
        tax_rate=data.tax_rate,
        discount_type=data.discount_type,
        discount_value=data.discount_value,
        expiry_date=data.expiry_date,
        admin_notes=data.admin_notes,
        line_items=data.line_items,
    )
    svc = QuoteService(db)
    quote = await svc.create_for_scope(scope_id, data_with_scope, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(quote, include_finance=include_finance)


@scope_quote_router.get("/quotes", response_model=list[QuoteResponse])
async def list_scope_quotes(
    scope_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
    include_finance: bool = Depends(finance_view_granted),
) -> list[QuoteResponse]:
    """List all quotes for a trade scope (admin only)."""
    await require_permission("quotes.view")(current_user, db)
    svc = QuoteService(db)
    quotes = await svc.list_by_scope(scope_id)
    return [QuoteResponse.from_orm_with_totals(q, include_finance=include_finance) for q in quotes]


# ---------------------------------------------------------------------------
# Project quote-variance endpoint (Phase 37, FINAI-05)
# ---------------------------------------------------------------------------


@project_variance_router.get("/quote-variance", response_model=ProjectQuoteVarianceResponse)
async def get_project_quote_variance(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ProjectQuoteVarianceResponse:
    """The financials drill-down's quoted-vs-actual table for one project (FINAI-05).

    One row per invoiced, approved-quote anchor in the project plus a summed
    total. finance.view-gated — the other half of the Trap 8 double lock.
    """
    await require_permission("finance.view")(current_user, db)
    result = await QuoteVarianceService(db).project_quote_variance(project_id)
    return to_project_quote_variance_response(result)
