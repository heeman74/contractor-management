"""BudgetService — budget CRUD and budget-vs-actual assembly (D-10, BUDG-01/02).

Wraps BudgetRepository; the router stays thin and delegates every operation
here (CLAUDE.md: router functions keep thin — delegate to service layer).
No db.commit() — get_db handles the transaction lifecycle.
"""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import TYPE_CHECKING

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.features.finance.budget_math import percent_used
from app.features.finance.budget_repository import BudgetRepository
from app.features.finance.models import Budget
from app.features.finance.schemas import BudgetCreate, BudgetUpdate, BudgetVsActual

if TYPE_CHECKING:
    from app.features.finance.service import FinanceService

_PROJECT_DUPLICATE_DETAIL = "A budget already exists for this project"
_SCOPE_DUPLICATE_DETAIL = "A budget already exists for this trade scope"
_BREAKDOWNS_DORMANT_DETAIL = "Per-category budget allocation is not available yet"


def _to_budget_vs_actual(budget: Budget, spent: Decimal) -> BudgetVsActual:
    """Assemble the wire block; remaining goes negative when over budget (D-10)."""
    return BudgetVsActual(
        budget_id=budget.id,
        total=budget.total,
        spent=spent,
        remaining=budget.total - spent,
        percent_used=percent_used(spent, budget.total),
    )


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

    async def budget_vs_actual_for_project(
        self, project_id: uuid.UUID, *, spent: Decimal | None = None
    ) -> BudgetVsActual | None:
        """Budget block for a project, or None when no active budget exists (BUDG-02).

        The rollup path always passes its own grand_total as spent — no extra query,
        and budget.spent == grand_total by construction (Pitfall 6).
        """
        budget = await self.repository.active_for_project(project_id)
        if budget is None:
            return None
        if spent is None:
            spent = await self._finance_service().project_spend(project_id)
        return _to_budget_vs_actual(budget, spent)

    async def budget_vs_actual_for_trade_scope(
        self, trade_scope_id: uuid.UUID, *, spent: Decimal | None = None
    ) -> BudgetVsActual | None:
        """Budget block for a trade scope, or None when no active budget exists (BUDG-02)."""
        budget = await self.repository.active_for_trade_scope(trade_scope_id)
        if budget is None:
            return None
        if spent is None:
            spent = await self._finance_service().trade_scope_spend(trade_scope_id)
        return _to_budget_vs_actual(budget, spent)

    def _finance_service(self) -> FinanceService:
        """The single spend source. Lazy import: finance.service imports BudgetService
        at module level (cycle service -> budget_service -> service), matching the
        convention in app/core/security.py::effective_permissions."""
        from app.features.finance.service import FinanceService

        return FinanceService(self.db)
