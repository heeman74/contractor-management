"""Service for the billing milestones domain.

Inherits TenantScopedService for standard CRUD operations.
Adds domain-specific methods: create_milestone, update_milestone, delete_milestone,
list_by_scope, and atomic mark_invoiced with double-billing prevention.
"""

import uuid

from fastapi import HTTPException, status
from sqlalchemy import text

from app.core.base_service import TenantScopedService
from app.features.billing_milestones.models import BillingMilestone
from app.features.billing_milestones.repository import BillingMilestoneRepository
from app.features.billing_milestones.schemas import BillingMilestoneCreate, BillingMilestoneUpdate


class BillingMilestoneService(TenantScopedService[BillingMilestone]):
    """Service for BillingMilestone CRUD and invoicing operations."""

    repository_class = BillingMilestoneRepository

    @property
    def _milestone_repo(self) -> BillingMilestoneRepository:
        """Typed access to the milestone repository."""
        return self.repository  # type: ignore[return-value]

    async def create_milestone(self, data: BillingMilestoneCreate) -> BillingMilestone:
        """Create a new billing milestone for a trade scope."""
        company_id = self._require_tenant_id()
        milestone = BillingMilestone(
            company_id=company_id,
            trade_scope_id=data.trade_scope_id,
            name=data.name,
            percentage=data.percentage,
            description=data.description,
            sort_order=data.sort_order,
        )
        return await self._milestone_repo.create(milestone)

    async def update_milestone(
        self, milestone_id: uuid.UUID, data: BillingMilestoneUpdate
    ) -> BillingMilestone:
        """Update milestone fields. Raises 404 if milestone not found."""
        milestone = await self._milestone_repo.get_by_id(milestone_id)
        if milestone is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Billing milestone not found",
            )
        update_data = {k: v for k, v in data.model_dump().items() if v is not None}
        updated = await self._milestone_repo.update(milestone_id, update_data)
        if updated is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Billing milestone not found",
            )
        return updated

    async def delete_milestone(self, milestone_id: uuid.UUID) -> bool:
        """Soft-delete a billing milestone. Returns False if not found."""
        return await self._milestone_repo.soft_delete(milestone_id)

    async def list_by_scope(self, trade_scope_id: uuid.UUID) -> list[BillingMilestone]:
        """List all milestones for a trade scope, ordered by sort_order."""
        return await self._milestone_repo.list_by_scope(trade_scope_id)

    async def mark_invoiced(self, milestone_id: uuid.UUID) -> BillingMilestone:
        """Atomically mark a milestone as invoiced.

        Uses a conditional UPDATE (WHERE is_invoiced=FALSE) to prevent double-billing.
        If the milestone is already invoiced, raises HTTP 409 Conflict.
        """
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
        await self.db.flush()
        milestone = await self._milestone_repo.get_by_id(milestone_id)
        if milestone is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Billing milestone not found after update",
            )
        return milestone
