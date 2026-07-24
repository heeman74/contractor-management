"""REST API router for billing milestones.

Endpoints are nested under trade scopes:
  GET    /api/v1/trade-scopes/{scope_id}/milestones        — list milestones for scope
  POST   /api/v1/trade-scopes/{scope_id}/milestones        — create milestone
  PUT    /api/v1/trade-scopes/{scope_id}/milestones/{milestone_id} — update milestone
  DELETE /api/v1/trade-scopes/{scope_id}/milestones/{milestone_id} — soft delete
  POST   /api/v1/trade-scopes/{scope_id}/milestones/{milestone_id}/mark-invoiced — mark invoiced

All endpoints require authentication. Admin role enforced for write operations.

CLAUDE.md rules:
- Router functions are thin — delegate to service layer
- CurrentUser is the real CurrentUser object (user_id, company_id, roles attributes)
- No standalone functions — all logic in service layer
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user, require_permission
from app.features.billing_milestones.schemas import (
    BillingMilestoneCreate,
    BillingMilestoneResponse,
    BillingMilestoneUpdate,
)
from app.features.billing_milestones.service import BillingMilestoneService

router = APIRouter(
    prefix="/trade-scopes/{scope_id}/milestones",
    tags=["billing-milestones"],
)


@router.get("/", response_model=list[BillingMilestoneResponse])
async def list_milestones(
    scope_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> list[BillingMilestoneResponse]:
    """List all milestones for a trade scope, ordered by sort_order."""
    svc = BillingMilestoneService(db)
    milestones = await svc.list_by_scope(scope_id)
    return [BillingMilestoneResponse.from_model(m) for m in milestones]


@router.post("/", response_model=BillingMilestoneResponse, status_code=status.HTTP_201_CREATED)
async def create_milestone(
    scope_id: uuid.UUID,
    data: BillingMilestoneCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> BillingMilestoneResponse:
    """Create a new billing milestone for a trade scope. Requires invoices.manage."""
    await require_permission("invoices.create")(current_user, db)
    # Ensure the scope_id in URL matches the body (override for consistency)
    data_with_scope = BillingMilestoneCreate(
        trade_scope_id=scope_id,
        name=data.name,
        percentage=data.percentage,
        description=data.description,
        sort_order=data.sort_order,
    )
    svc = BillingMilestoneService(db)
    milestone = await svc.create_milestone(data_with_scope)
    return BillingMilestoneResponse.from_model(milestone)


@router.put(
    "/{milestone_id}",
    response_model=BillingMilestoneResponse,
)
async def update_milestone(
    scope_id: uuid.UUID,
    milestone_id: uuid.UUID,
    data: BillingMilestoneUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> BillingMilestoneResponse:
    """Update a billing milestone. Requires invoices.manage."""
    await require_permission("invoices.edit")(current_user, db)
    svc = BillingMilestoneService(db)
    milestone = await svc.update_milestone(milestone_id, data)
    return BillingMilestoneResponse.from_model(milestone)


@router.delete("/{milestone_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_milestone(
    scope_id: uuid.UUID,
    milestone_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Soft-delete a billing milestone. Requires invoices.manage."""
    await require_permission("invoices.delete")(current_user, db)
    svc = BillingMilestoneService(db)
    deleted = await svc.delete_milestone(milestone_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Billing milestone not found",
        )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/{milestone_id}/mark-invoiced",
    response_model=BillingMilestoneResponse,
)
async def mark_invoiced(
    scope_id: uuid.UUID,
    milestone_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> BillingMilestoneResponse:
    """Atomically mark a milestone as invoiced. Admin only.

    Returns 409 Conflict if milestone is already invoiced (double-billing prevention).
    """
    await require_permission("billing.trade.approve")(current_user, db)
    svc = BillingMilestoneService(db)
    milestone = await svc.mark_invoiced(milestone_id)
    return BillingMilestoneResponse.from_model(milestone)
