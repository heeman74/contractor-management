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

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.finance.models import CostEntry
from app.features.finance.schemas import (
    CostCategoryResponse,
    CostEntryCreate,
    CostEntryResponse,
    CostEntryUpdate,
    ProjectCostRollupResponse,
)
from app.features.finance.service import FinanceService

router = APIRouter(tags=["finance"])


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
