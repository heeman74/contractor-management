"""BudgetService — budget CRUD and budget-vs-actual assembly (D-10, BUDG-01/02).

Wraps BudgetRepository; the router stays thin and delegates every operation
here (CLAUDE.md: router functions keep thin — delegate to service layer).
No db.commit() — get_db handles the transaction lifecycle.
"""

from __future__ import annotations

import uuid

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.features.finance.budget_repository import BudgetRepository
from app.features.finance.models import Budget
from app.features.finance.schemas import BudgetCreate, BudgetUpdate

_PROJECT_DUPLICATE_DETAIL = "A budget already exists for this project"
_SCOPE_DUPLICATE_DETAIL = "A budget already exists for this trade scope"
_BREAKDOWNS_DORMANT_DETAIL = "Per-category budget allocation is not available yet"


class BudgetService(TenantScopedService[Budget]):
    """Budget CRUD and budget-vs-actual assembly (D-10, BUDG-01/02)."""

    repository_class = BudgetRepository
    repository: BudgetRepository

    async def create_budget(self, data: BudgetCreate, company_id: uuid.UUID) -> Budget:
        """Create a budget at a project XOR trade-scope anchor (XOR enforced by schema).

        A non-empty category_breakdowns list is rejected loudly rather than
        silently dropped — the per-category breakdown is dormant in v4.0 (D-11).
        """
        if data.category_breakdowns:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=_BREAKDOWNS_DORMANT_DETAIL,
            )
        await self._reject_duplicate_anchor(data)
        budget = Budget(
            company_id=company_id,
            project_id=data.project_id,
            trade_scope_id=data.trade_scope_id,
            total=data.total,
        )
        return await self.repository.create(budget)

    async def _reject_duplicate_anchor(self, data: BudgetCreate) -> None:
        """409 when an active budget already exists at the requested anchor.

        The partial unique indexes from migration 0035 are the hard guarantee;
        this check is the friendly error.
        """
        if data.project_id is not None:
            existing = await self.repository.active_for_project(data.project_id)
            detail = _PROJECT_DUPLICATE_DETAIL
        else:
            assert data.trade_scope_id is not None  # XOR guaranteed by BudgetCreate
            existing = await self.repository.active_for_trade_scope(data.trade_scope_id)
            detail = _SCOPE_DUPLICATE_DETAIL
        if existing is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)

    async def update_budget(self, budget_id: uuid.UUID, data: BudgetUpdate) -> Budget:
        """Edit a budget's total — set_total applies the D-03 re-arm on a raise."""
        budget = await self.repository.active_by_id_or_404(budget_id)
        return await self.repository.set_total(budget, data.total)

    async def delete_budget(self, budget_id: uuid.UUID) -> None:
        """Soft-delete a budget — it drops out of every active-budget lookup."""
        budget = await self.repository.active_by_id_or_404(budget_id)
        await self.repository.soft_delete(budget.id)
