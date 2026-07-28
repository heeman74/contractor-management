"""BudgetRepository — async data access for budgets.

Tenant-scoped via PostgreSQL RLS (SET LOCAL app.current_company_id). Never
eager-loads Budget.breakdowns — the per-category breakdown is dormant in v4.0
(D-11) and stays lazy="raise" so an accidental touch fails loudly.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select, text
from sqlalchemy.sql.elements import TextClause

from app.core.base_repository import TenantScopedRepository
from app.features.finance.budget_math import BudgetThreshold
from app.features.finance.labor_derivation import CENTS, ZERO_MONEY
from app.features.finance.models import Budget, CostEntry
from app.features.projects.models import Project, TradeScope


@dataclass(frozen=True)
class BudgetAlertContext:
    """Everything the alert copy and the DashboardAlert row need about a budget's anchor."""

    project_id: uuid.UUID
    project_name: str
    trade_name: str | None  # None = project budget


_CLAIM_SQL: dict[BudgetThreshold, TextClause] = {
    BudgetThreshold.warning: text(
        "UPDATE budgets SET warning_fired_at = now() "
        "WHERE id = :budget_id AND warning_fired_at IS NULL AND deleted_at IS NULL "
        "RETURNING id"
    ),
    BudgetThreshold.overrun: text(
        "UPDATE budgets SET overrun_fired_at = now() "
        "WHERE id = :budget_id AND overrun_fired_at IS NULL AND deleted_at IS NULL "
        "RETURNING id"
    ),
}


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

    async def scope_spends(self, trade_scope_ids: list[uuid.UUID]) -> dict[uuid.UUID, Decimal]:
        """Non-deleted cost-entry totals for many scopes in ONE grouped query.

        A batched restatement of FinanceService.trade_scope_spend's definition:
        all categories, no derived labor, soft-deleted excluded. The two
        implementations are pinned together by
        test_sweep_scope_spends_equivalence_matches_trade_scope_spend
        (backend/tests/test_phase_34_e2e.py) — edit either side only with that
        test in view (RESEARCH Pitfall 6). Scopes with no entries map to
        ZERO_MONEY.
        """
        if not trade_scope_ids:
            return {}
        result = await self.db.execute(
            select(CostEntry.trade_scope_id, func.sum(CostEntry.amount))
            .where(CostEntry.trade_scope_id.in_(trade_scope_ids), CostEntry.deleted_at.is_(None))
            .group_by(CostEntry.trade_scope_id)
        )
        spends = dict.fromkeys(trade_scope_ids, ZERO_MONEY)
        spends.update({scope_id: total.quantize(CENTS) for scope_id, total in result.all()})
        return spends

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

    async def claim_threshold(self, budget_id: uuid.UUID, threshold: BudgetThreshold) -> bool:
        """Atomically claim one threshold crossing for a budget.

        Executes an ``UPDATE ... WHERE <threshold>_fired_at IS NULL`` returning
        the id (Phase 25 mark_invoiced precedent) — the entire exactly-once mechanism:
        no locks, no unique index, no unique-violation catching. Returns False
        when another evaluator (a concurrent request or the nightly sweep)
        already claimed this crossing; the caller must then NOT create an alert.
        """
        result = await self.db.execute(_CLAIM_SQL[threshold], {"budget_id": budget_id})
        claimed = result.scalar_one_or_none() is not None
        if claimed:
            await self._expire_fired_state(budget_id)
        return claimed

    async def _expire_fired_state(self, budget_id: uuid.UUID) -> None:
        """Expire the in-session budget's fired columns after a raw-SQL claim,
        so the ORM object cannot serve a stale None to a later reader."""
        budget = await self.db.get(Budget, budget_id)
        if budget is not None:
            self.db.expire(budget, ["warning_fired_at", "overrun_fired_at"])

    async def alert_context(self, budget: Budget) -> BudgetAlertContext | None:
        """Resolve the anchor entity names an alert needs, in one query.

        Returns None when the anchor row is gone or soft-deleted — callers then
        skip the budget entirely (dashboard_alerts.project_id is NOT NULL, so
        no alert can be written without a live anchor).
        """
        if budget.project_id is not None:
            return await self._project_alert_context(budget.project_id)
        return await self._trade_scope_alert_context(budget.trade_scope_id)

    async def _project_alert_context(self, project_id: uuid.UUID) -> BudgetAlertContext | None:
        result = await self.db.execute(
            select(Project.id, Project.name).where(
                Project.id == project_id, Project.deleted_at.is_(None)
            )
        )
        row = result.first()
        if row is None:
            return None
        return BudgetAlertContext(project_id=row.id, project_name=row.name, trade_name=None)

    async def _trade_scope_alert_context(
        self, trade_scope_id: uuid.UUID | None
    ) -> BudgetAlertContext | None:
        result = await self.db.execute(
            select(TradeScope.project_id, Project.name, TradeScope.trade_name)
            .join(Project, TradeScope.project_id == Project.id)
            .where(TradeScope.id == trade_scope_id, TradeScope.deleted_at.is_(None))
        )
        row = result.first()
        if row is None:
            return None
        return BudgetAlertContext(
            project_id=row.project_id, project_name=row.name, trade_name=row.trade_name
        )
