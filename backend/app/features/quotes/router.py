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

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.companies.models import Company
from app.features.pdf.service import pdf_service
from app.features.quotes.schemas import (
    DeclineQuoteRequest,
    QuoteCreate,
    QuoteResponse,
    QuoteTemplateCreate,
    QuoteTemplateResponse,
    QuoteUpdate,
)
from app.features.quotes.service import QuoteService


class ExtendExpiryRequest(BaseModel):
    """Request body for extending a quote's expiry date."""

    new_expiry_date: date


# isort: split
# Side-effect import: ensure all referenced mappers are registered before
# configure_mappers() triggers on Quote relationship resolution.
import app.features.invoices.models  # noqa: E402, F401
import app.features.scheduling.models  # noqa: E402, F401
import app.features.users.models  # noqa: E402, F401

router = APIRouter(prefix="/quotes", tags=["quotes"])


def _require_admin(current_user: CurrentUser) -> None:
    """Raise 403 if the current user is not an admin."""
    if "admin" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )


def _require_client(current_user: CurrentUser) -> None:
    """Raise 403 if the current user is not a client."""
    if "client" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Client role required",
        )


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
    _require_admin(current_user)
    svc = QuoteService(db)
    template = await svc.create_template(data)
    return QuoteTemplateResponse.model_validate(template)


@router.get("/templates", response_model=list[QuoteTemplateResponse])
async def list_templates(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[QuoteTemplateResponse]:
    """List all quote templates for the current tenant (admin only)."""
    _require_admin(current_user)
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
    _require_admin(current_user)
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
    _require_admin(current_user)
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
) -> list[QuoteResponse]:
    """List all active (non-deleted, non-revised) quotes for the tenant (admin only).

    Optional `status` query param filters by quote status (e.g. draft, sent, approved).
    Paginated via offset/limit.
    """
    _require_admin(current_user)
    svc = QuoteService(db)
    quotes = await svc.repository.get_active_quotes()
    if status is not None:
        quotes = [q for q in quotes if q.status == status]
    # Apply pagination
    quotes = quotes[offset : offset + min(limit, 200)]
    return [QuoteResponse.from_orm_with_totals(q) for q in quotes]


@router.get("/for-job/{job_id}", response_model=QuoteResponse)
async def get_quote_for_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Get the latest non-revised quote for a job."""
    svc = QuoteService(db)
    quote = await svc.repository.get_for_job(job_id)
    if quote is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No quote found for job")
    return QuoteResponse.from_orm_with_totals(quote)


# ---------------------------------------------------------------------------
# Core quote routes
# ---------------------------------------------------------------------------


@router.post("/", response_model=QuoteResponse, status_code=201)
async def create_quote(
    data: QuoteCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Create a new draft quote for a job (admin only)."""
    _require_admin(current_user)
    svc = QuoteService(db)
    quote = await svc.create_quote(data, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(quote)


@router.get("/{quote_id}", response_model=QuoteResponse)
async def get_quote(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Get a quote with line items.

    If the requester is a client, records their first view (read receipt).
    """
    svc = QuoteService(db)

    if "client" in current_user.roles:
        # record_view triggers status sent -> viewed and appends status_history
        quote = await svc.record_view(quote_id, current_user.user_id)
    else:
        quote = await svc.repository.get_with_line_items(quote_id)
        if quote is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

    return QuoteResponse.from_orm_with_totals(quote)


@router.patch("/{quote_id}", response_model=QuoteResponse)
async def update_quote(
    quote_id: uuid.UUID,
    data: QuoteUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Update a draft quote (admin only). Full line item replacement if provided."""
    _require_admin(current_user)
    svc = QuoteService(db)
    quote = await svc.update_quote(quote_id, data)
    return QuoteResponse.from_orm_with_totals(quote)


@router.post("/{quote_id}/send", response_model=QuoteResponse)
async def send_quote(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Send a draft quote to the client (admin only)."""
    _require_admin(current_user)
    svc = QuoteService(db)
    quote = await svc.send_quote(quote_id)
    return QuoteResponse.from_orm_with_totals(quote)


@router.post("/{quote_id}/approve", response_model=QuoteResponse)
async def approve_quote(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Approve a sent or viewed quote (client only)."""
    _require_client(current_user)
    svc = QuoteService(db)
    quote = await svc.approve_quote(quote_id, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(quote)


@router.post("/{quote_id}/decline", response_model=QuoteResponse)
async def decline_quote(
    quote_id: uuid.UUID,
    data: DeclineQuoteRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Decline a sent or viewed quote with reason (client only)."""
    _require_client(current_user)
    svc = QuoteService(db)
    quote = await svc.decline_quote(quote_id, current_user.user_id, data)
    return QuoteResponse.from_orm_with_totals(quote)


@router.post("/{quote_id}/revise", response_model=QuoteResponse, status_code=201)
async def revise_quote(
    quote_id: uuid.UUID,
    data: QuoteUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Create a new revision of a sent/viewed/declined/expired quote (admin only)."""
    _require_admin(current_user)
    svc = QuoteService(db)
    new_quote = await svc.revise_quote(quote_id, data, current_user.user_id)
    return QuoteResponse.from_orm_with_totals(new_quote)


@router.post("/{quote_id}/extend", response_model=QuoteResponse)
async def extend_expiry(
    quote_id: uuid.UUID,
    data: ExtendExpiryRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> QuoteResponse:
    """Extend the expiry date of a quote. Resets expired -> sent (admin only)."""
    _require_admin(current_user)
    svc = QuoteService(db)
    quote = await svc.extend_expiry(quote_id, data.new_expiry_date)
    return QuoteResponse.from_orm_with_totals(quote)


@router.get("/{quote_id}/pdf")
async def download_quote_pdf(
    quote_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Download a quote as a PDF file (admin or client)."""
    svc = QuoteService(db)
    quote = await svc.repository.get_with_line_items(quote_id)
    if quote is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Quote not found")

    # Load the company for branding
    company = await db.get(Company, quote.company_id)
    if company is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found")

    pdf_bytes = await pdf_service.generate_quote_pdf(quote, company)
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="quote-{quote_id}.pdf"',
            "Content-Length": str(len(pdf_bytes)),
        },
    )
