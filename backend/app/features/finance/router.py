"""REST API router for the finance domain: cost entries, categories, project rollup.

Plain APIRouter (NOT CRUDRouter — it has no permission-gating hook, per
31-RESEARCH.md Pitfall 4). Every handler stays thin (delegates to
FinanceService) and calls the gate INLINE in the body, mirroring
billing_milestones/router.py exactly:

  POST   /cost-entries/                          — finance.manage
  GET    /cost-entries/?job_id=&trade_scope_id=   — finance.view
  GET    /cost-entries/{entry_id}                 — finance.view
  PATCH  /cost-entries/{entry_id}                 — finance.manage
  DELETE /cost-entries/{entry_id}                 — finance.manage (soft delete)
  GET    /projects/{project_id}/cost-entries      — finance.view (rollup)
  GET    /cost-categories/                        — finance.view

Receipt upload/serve endpoints land in Plan 31-02.
"""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Annotated

import aiofiles
from fastapi import APIRouter, Depends, Form, HTTPException, Query, Response, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.finance.models import CostEntry
from app.features.finance.schemas import (
    CostCategoryResponse,
    CostEntryCreate,
    CostEntryResponse,
    CostEntryUpdate,
    CostReceiptResponse,
    ProjectCostRollupResponse,
)
from app.features.finance.service import FinanceService

router = APIRouter(tags=["finance"])

_MAX_COST_RECEIPT_BYTES = 25 * 1024 * 1024


def _to_response(entry: CostEntry) -> CostEntryResponse:
    """Build a CostEntryResponse from an ORM CostEntry with category eager-loaded."""
    response = CostEntryResponse.model_validate(entry)
    response.category_name = entry.category.name
    return response


@router.post(
    "/cost-entries/", response_model=CostEntryResponse, status_code=status.HTTP_201_CREATED
)
async def create_cost_entry(
    data: CostEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CostEntryResponse:
    """Create a materials/subcontractor/other cost entry anchored to a job XOR a trade scope."""
    await require_permission("finance.manage")(current_user, db)
    svc = FinanceService(db)
    entry = await svc.create_cost_entry(data, company_id=current_user.company_id)
    return _to_response(entry)


@router.get("/cost-entries/", response_model=list[CostEntryResponse])
async def list_cost_entries(
    job_id: uuid.UUID | None = Query(default=None),
    trade_scope_id: uuid.UUID | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[CostEntryResponse]:
    """List non-soft-deleted cost entries for a job or a trade scope."""
    await require_permission("finance.view")(current_user, db)
    svc = FinanceService(db)
    if job_id is not None:
        entries = await svc.list_for_job(job_id)
    elif trade_scope_id is not None:
        entries = await svc.list_for_trade_scope(trade_scope_id)
    else:
        entries = []
    return [_to_response(entry) for entry in entries]


@router.get("/cost-entries/{entry_id}", response_model=CostEntryResponse)
async def get_cost_entry(
    entry_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CostEntryResponse:
    """Fetch a single cost entry by id."""
    await require_permission("finance.view")(current_user, db)
    svc = FinanceService(db)
    entry = await svc.get_entry_or_404(entry_id)
    return _to_response(entry)


@router.patch("/cost-entries/{entry_id}", response_model=CostEntryResponse)
async def update_cost_entry(
    entry_id: uuid.UUID,
    data: CostEntryUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CostEntryResponse:
    """Update a cost entry's amount/category/date/vendor/note (anchor is immutable)."""
    await require_permission("finance.manage")(current_user, db)
    svc = FinanceService(db)
    entry = await svc.update_cost_entry(entry_id, data)
    return _to_response(entry)


@router.delete(
    "/cost-entries/{entry_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None
)
async def delete_cost_entry(
    entry_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Soft-delete a cost entry — drops out of lists and the project rollup (D-05)."""
    await require_permission("finance.manage")(current_user, db)
    svc = FinanceService(db)
    await svc.delete_cost_entry(entry_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/projects/{project_id}/cost-entries", response_model=ProjectCostRollupResponse)
async def get_project_cost_rollup(
    project_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> ProjectCostRollupResponse:
    """Return the project cost rollup: trade-scope costs + job costs (D-02/D-05)."""
    await require_permission("finance.view")(current_user, db)
    svc = FinanceService(db)
    entries, total = await svc.rollup_for_project(project_id)
    return ProjectCostRollupResponse(
        project_id=project_id,
        total=total,
        entries=[_to_response(entry) for entry in entries],
    )


@router.get("/cost-categories/", response_model=list[CostCategoryResponse])
async def list_cost_categories(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[CostCategoryResponse]:
    """List the current tenant's cost categories."""
    await require_permission("finance.view")(current_user, db)
    svc = FinanceService(db)
    categories = await svc.list_categories()
    return [CostCategoryResponse.model_validate(category) for category in categories]


# ---------------------------------------------------------------------------
# Cost receipt endpoints (COST-03)
# ---------------------------------------------------------------------------


async def _save_cost_receipt_file(cost_entry_id: uuid.UUID, file: UploadFile) -> str:
    """Persist an uploaded receipt under uploads/cost-receipts/{cost_entry_id}/ and return its URL.

    Enforces the size limit and returns the /files/-served remote URL.
    """
    suffix = Path(file.filename or "").suffix.lower() or ".bin"
    unique_filename = f"{uuid.uuid4()}{suffix}"
    upload_dir = Path("uploads") / "cost-receipts" / str(cost_entry_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    content = await file.read()
    if len(content) > _MAX_COST_RECEIPT_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="File too large. Maximum size is 25 MB.",
        )
    async with aiofiles.open(upload_dir / unique_filename, "wb") as destination:
        await destination.write(content)

    return f"/files/cost-receipts/{cost_entry_id}/{unique_filename}"


@router.post(
    "/cost-entries/{cost_entry_id}/receipts",
    response_model=CostReceiptResponse,
    status_code=status.HTTP_201_CREATED,
)
async def upload_cost_receipt(
    cost_entry_id: uuid.UUID,
    file: UploadFile,
    caption: Annotated[str | None, Form()] = None,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CostReceiptResponse:
    """Upload a receipt file and attach it to a cost entry (D-04, COST-03)."""
    await require_permission("finance.manage")(current_user, db)
    svc = FinanceService(db)
    await svc.get_entry_or_404(cost_entry_id)  # 404s a forged/foreign id under RLS
    remote_url = await _save_cost_receipt_file(cost_entry_id, file)
    receipt = await svc.add_receipt(cost_entry_id, current_user.company_id, remote_url, caption)
    return CostReceiptResponse.model_validate(receipt)


@router.get("/cost-entries/{cost_entry_id}/receipts", response_model=list[CostReceiptResponse])
async def list_cost_receipts(
    cost_entry_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[CostReceiptResponse]:
    """List non-soft-deleted receipts for a cost entry."""
    await require_permission("finance.view")(current_user, db)
    svc = FinanceService(db)
    receipts = await svc.list_receipts(cost_entry_id)
    return [CostReceiptResponse.model_validate(receipt) for receipt in receipts]


@router.delete(
    "/cost-entries/{cost_entry_id}/receipts/{receipt_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def delete_cost_receipt(
    cost_entry_id: uuid.UUID,
    receipt_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Soft-delete a receipt from a cost entry."""
    await require_permission("finance.manage")(current_user, db)
    svc = FinanceService(db)
    await svc.delete_receipt(cost_entry_id, receipt_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
