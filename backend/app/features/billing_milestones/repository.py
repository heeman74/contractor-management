"""Repository for the billing milestones domain.

Inherits TenantScopedRepository for standard CRUD operations with RLS support.
Adds list_by_scope for filtering milestones by trade scope.
"""

import uuid

from sqlalchemy import select

from app.core.base_repository import TenantScopedRepository
from app.features.billing_milestones.models import BillingMilestone


class BillingMilestoneRepository(TenantScopedRepository[BillingMilestone]):
    """Repository for BillingMilestone entities with scope-level filtering."""

    model = BillingMilestone

    async def list_by_scope(self, trade_scope_id: uuid.UUID) -> list[BillingMilestone]:
        """List all active milestones for a trade scope, ordered by sort_order."""
        stmt = (
            select(BillingMilestone)
            .where(
                BillingMilestone.trade_scope_id == trade_scope_id,
                BillingMilestone.deleted_at.is_(None),
            )
            .order_by(BillingMilestone.sort_order)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
