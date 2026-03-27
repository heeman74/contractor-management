"""Invoices API router — REST endpoints for the invoice lifecycle domain.

Endpoints (declared in order to prevent FastAPI path parameter shadowing):

Static paths declared BEFORE /{invoice_id} parameterized paths:
  POST   /invoices/generate/{job_id}  — generate from approved quote (admin)
  GET    /invoices/for-job/{job_id}   — get invoice for a job (admin or client)
  POST   /invoices/                   — create manual invoice (admin)
  GET    /invoices/{invoice_id}       — get with line items
  PATCH  /invoices/{invoice_id}       — update before finalize (admin)
  POST   /invoices/{invoice_id}/finalize    — finalize invoice (admin)
  PATCH  /invoices/{invoice_id}/payment     — update payment status (admin)
  GET    /invoices/{invoice_id}/pdf         — download PDF

Design notes:
- Plain APIRouter (not CRUDRouter) — lifecycle operations.
- All logic delegated to InvoiceService.
- PDF download streams WeasyPrint bytes as application/pdf.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user
from app.features.companies.models import Company
from app.features.invoices.schemas import (
    InvoiceCreate,
    InvoiceResponse,
    InvoiceUpdate,
    MarkPaidRequest,
)
from app.features.invoices.service import InvoiceService
from app.features.pdf.service import pdf_service

# isort: split
# Side-effect import: ensure related mappers registered before configure_mappers() triggers.
import app.features.quotes.models
import app.features.scheduling.models
import app.features.users.models  # noqa: F401


class ProgressInvoiceRequest(BaseModel):
    """Request body for generating a progress invoice from a milestone."""

    milestone_id: uuid.UUID


router = APIRouter(prefix="/invoices", tags=["invoices"])

# ---------------------------------------------------------------------------
# Trade-scope invoice router — Phase 25
# Separate router so /api/trade-scopes/{scope_id}/invoices/* doesn't shadow /invoices
# ---------------------------------------------------------------------------
scope_invoice_router = APIRouter(prefix="/trade-scopes/{scope_id}", tags=["trade-scope-invoices"])


def _require_admin(current_user: CurrentUser) -> None:
    """Raise 403 if the current user is not an admin."""
    if "admin" not in current_user.roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )


# ---------------------------------------------------------------------------
# Static routes — MUST be declared before /{invoice_id} to prevent shadowing
# ---------------------------------------------------------------------------


@router.post("/generate/{job_id}", response_model=InvoiceResponse, status_code=201)
async def generate_invoice_from_quote(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Generate an invoice from a completed job's approved quote (admin only).

    Uses SELECT FOR UPDATE on the company row to generate a sequential invoice number.
    Transitions the job to 'invoiced' status.
    """
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.generate_from_quote(job_id, current_user.user_id)
    return InvoiceResponse.from_orm_with_totals(invoice)


@router.get("/", response_model=list[InvoiceResponse])
async def list_invoices(
    status: str | None = None,
    offset: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[InvoiceResponse]:
    """List all invoices for the tenant (admin only).

    Optional `status` query param filters by payment status (unpaid, partially_paid, paid).
    Soft-deleted invoices are excluded. Paginated via offset/limit.
    """
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoices = await svc.repository.list_all()
    invoices = [i for i in invoices if i.deleted_at is None]
    if status is not None:
        invoices = [i for i in invoices if i.status == status]
    # Apply pagination
    invoices = invoices[offset : offset + min(limit, 200)]
    return [InvoiceResponse.from_orm_with_totals(i) for i in invoices]


@router.get("/for-job/{job_id}", response_model=InvoiceResponse)
async def get_invoice_for_job(
    job_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Get the invoice for a job."""
    svc = InvoiceService(db)
    invoice = await svc.repository.get_for_job(job_id)
    if invoice is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No invoice found for job"
        )
    return InvoiceResponse.from_orm_with_totals(invoice)


# ---------------------------------------------------------------------------
# Core invoice routes
# ---------------------------------------------------------------------------


@router.post("/", response_model=InvoiceResponse, status_code=201)
async def create_manual_invoice(
    data: InvoiceCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Create a manual invoice for a job (admin only).

    For jobs that skip the quote step (e.g., emergency call-outs).
    """
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.generate_manual(data, current_user.user_id)
    return InvoiceResponse.from_orm_with_totals(invoice)


@router.get("/{invoice_id}", response_model=InvoiceResponse)
async def get_invoice(
    invoice_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Get an invoice with all line items."""
    svc = InvoiceService(db)
    invoice = await svc.repository.get_with_line_items(invoice_id)
    if invoice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")
    return InvoiceResponse.from_orm_with_totals(invoice)


@router.patch("/{invoice_id}", response_model=InvoiceResponse)
async def update_invoice(
    invoice_id: uuid.UUID,
    data: InvoiceUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Update an invoice before finalization (admin only)."""
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.update_invoice(invoice_id, data)
    return InvoiceResponse.from_orm_with_totals(invoice)


@router.post("/{invoice_id}/finalize", response_model=InvoiceResponse)
async def finalize_invoice(
    invoice_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Finalize an invoice — prevents further edits (admin only)."""
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.finalize_invoice(invoice_id)
    return InvoiceResponse.from_orm_with_totals(invoice)


@router.patch("/{invoice_id}/payment", response_model=InvoiceResponse)
async def update_payment_status(
    invoice_id: uuid.UUID,
    data: MarkPaidRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Update invoice payment status (admin only).

    Valid: unpaid -> partially_paid -> paid. No paid -> unpaid regression.
    """
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.update_payment_status(invoice_id, data)
    return InvoiceResponse.from_orm_with_totals(invoice)


@router.get("/{invoice_id}/pdf")
async def download_invoice_pdf(
    invoice_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Download an invoice as a PDF file."""
    svc = InvoiceService(db)
    invoice = await svc.repository.get_with_line_items(invoice_id)
    if invoice is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

    company = await db.get(Company, invoice.company_id)
    if company is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found")

    pdf_bytes = await pdf_service.generate_invoice_pdf(invoice, company)
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="invoice-{invoice.invoice_number}.pdf"',
            "Content-Length": str(len(pdf_bytes)),
        },
    )


# ---------------------------------------------------------------------------
# Trade-scope invoice endpoints (Phase 25)
# ---------------------------------------------------------------------------


@scope_invoice_router.post("/invoices/generate", response_model=InvoiceResponse, status_code=201)
async def generate_scope_invoice(
    scope_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Generate an invoice from completed tasks in a trade scope (admin only).

    Each completed task becomes a line item with unit_price=0.00 for GC to fill in.
    Inherits tax_rate from the approved quote if one exists.
    """
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.generate_from_scope(scope_id, current_user.user_id)
    return InvoiceResponse.from_orm_with_totals(invoice)


@scope_invoice_router.post("/invoices/progress", response_model=InvoiceResponse, status_code=201)
async def generate_progress_invoice(
    scope_id: uuid.UUID,
    data: ProgressInvoiceRequest,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> InvoiceResponse:
    """Generate a milestone-based progress invoice for a trade scope (admin only).

    Returns 409 if the milestone was already invoiced (double-billing prevention).
    Returns 400 if no approved quote exists for the scope.
    """
    _require_admin(current_user)
    svc = InvoiceService(db)
    invoice = await svc.generate_progress_invoice(scope_id, data.milestone_id, current_user.user_id)
    return InvoiceResponse.from_orm_with_totals(invoice)


@scope_invoice_router.get("/invoices", response_model=list[InvoiceResponse])
async def list_scope_invoices(
    scope_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[InvoiceResponse]:
    """List all non-deleted invoices for a trade scope (admin only)."""
    from sqlalchemy import select
    from sqlalchemy.orm import selectinload

    from app.features.invoices.models import Invoice

    _require_admin(current_user)
    result = await db.execute(
        select(Invoice)
        .where(
            Invoice.trade_scope_id == scope_id,
            Invoice.deleted_at.is_(None),
        )
        .options(selectinload(Invoice.line_items))
        .order_by(Invoice.created_at.desc())
    )
    invoices = list(result.scalars().all())
    return [InvoiceResponse.from_orm_with_totals(i) for i in invoices]
