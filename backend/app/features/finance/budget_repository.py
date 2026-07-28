"""BudgetRepository — async data access for budgets.

Tenant-scoped via PostgreSQL RLS (SET LOCAL app.current_company_id). Never
eager-loads Budget.breakdowns — the per-category breakdown is dormant in v4.0
(D-11) and stays lazy="raise" so an accidental touch fails loudly.
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.base_repository import TenantScopedRepository
from app.features.finance.models import Budget


class BudgetRepository(TenantScopedRepository[Budget]):
    """Data access for budgets. Every query filters deleted_at IS NULL —
    BaseRepository does not (Phase 31 pitfall)."""

    model = Budget

    async def active_for_project(self, project_id: uuid.UUID) -> Budget | None:
        """Return the active (non-soft-deleted) budget anchored to a project."""
        result = await self.db.execute(
            select(Budget).where(Budget.project_id == project_id, Budget.deleted_at.is_(None))
        )
        return result.scalars().first()

    async def active_for_trade_scope(self, trade_scope_id: uuid.UUID) -> Budget | None:
        """Return the active (non-soft-deleted) budget anchored to a trade scope."""
        result = await self.db.execute(
            select(Budget).where(
                Budget.trade_scope_id == trade_scope_id, Budget.deleted_at.is_(None)
            )
        )
        return result.scalars().first()

    async def active_by_id_or_404(self, budget_id: uuid.UUID) -> Budget:
        """Fetch a budget by id, or raise 404 for a missing or soft-deleted one."""
        result = await self.db.execute(
            select(Budget).where(Budget.id == budget_id, Budget.deleted_at.is_(None))
        )
        budget = result.scalars().first()
        if budget is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Budget not found")
        return budget

    async def list_active(self) -> list[Budget]:
        """All active budgets tenant-wide — drives the nightly threshold sweep."""
        result = await self.db.execute(select(Budget).where(Budget.deleted_at.is_(None)))
        return list(result.scalars().all())

    async def set_total(self, budget: Budget, total: Decimal) -> Budget:
        """The only write path for Budget.total.

        A raise (strictly greater than the current total) re-arms both
        thresholds (D-03) by nulling the fired timestamps. A decrease leaves
        fired state untouched: already-fired thresholds stay deduped and
        unfired ones fire on the next evaluation.
        """
        if total > budget.total:
            budget.warning_fired_at = None
            budget.overrun_fired_at = None
        budget.total = total
        await self.db.flush()
        await self.db.refresh(budget)
        return budget
