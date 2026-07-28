"""BudgetService — budget CRUD and budget-vs-actual assembly (D-10, BUDG-01/02).

Wraps BudgetRepository; the router stays thin and delegates every operation
here (CLAUDE.md: router functions keep thin — delegate to service layer).
Never commits — get_db handles the transaction lifecycle.
"""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass
from decimal import Decimal
from typing import TYPE_CHECKING

from fastapi import HTTPException, status

from app.core.base_service import TenantScopedService
from app.core.logging_config import get_logger
from app.features.dashboard.alert_types import (
    BUDGET_OVERRUN_ALERT_TYPE,
    BUDGET_WARNING_ALERT_TYPE,
)
from app.features.dashboard.models import DashboardAlert
from app.features.dashboard.repository import AlertRepository
from app.features.finance.budget_math import (
    BudgetFacts,
    BudgetThreshold,
    budget_alert_text,
    crossed_thresholds,
    percent_used,
    push_title_for,
)
from app.features.finance.budget_repository import BudgetAlertContext, BudgetRepository
from app.features.finance.models import Budget
from app.features.finance.schemas import BudgetCreate, BudgetUpdate, BudgetVsActual

if TYPE_CHECKING:
    from app.features.finance.service import FinanceService

logger = get_logger(__name__)

_PROJECT_DUPLICATE_DETAIL = "A budget already exists for this project"
_SCOPE_DUPLICATE_DETAIL = "A budget already exists for this trade scope"
_BREAKDOWNS_DORMANT_DETAIL = "Per-category budget allocation is not available yet"

_FINANCE_VIEW_PERMISSION = "finance.view"
_BUDGET_ALERT_PUSH_TYPE = "budget_alert"
_NO_SCOPE_PUSH_VALUE = ""  # FCM data values must all be strings — "" means no scope

# Module-level task registry: keeps fire-and-forget push tasks alive until done
# (asyncio only holds weak references — the checklists precedent).
_BUDGET_PUSH_TASKS: set[asyncio.Task[None]] = set()

_ALERT_TYPE_BY_THRESHOLD: dict[BudgetThreshold, str] = {
    BudgetThreshold.warning: BUDGET_WARNING_ALERT_TYPE,
    BudgetThreshold.overrun: BUDGET_OVERRUN_ALERT_TYPE,
}
_SEVERITY_BY_THRESHOLD: dict[BudgetThreshold, str] = {
    BudgetThreshold.warning: "warning",
    BudgetThreshold.overrun: "critical",
}


@dataclass(frozen=True)
class FiredBudgetAlert:
    """One threshold that just fired — the hand-off to notification dispatch."""

    alert_id: uuid.UUID
    alert_type: str
    company_id: uuid.UUID
    project_id: uuid.UUID
    trade_scope_id: uuid.UUID | None
    title: str
    body: str


def _push_data(fired: FiredBudgetAlert) -> dict[str, str]:
    """FCM data payload for one fired alert — every value a string (FCM constraint)."""
    return {
        "type": _BUDGET_ALERT_PUSH_TYPE,
        "alert_type": fired.alert_type,
        "alert_id": str(fired.alert_id),
        "project_id": str(fired.project_id),
        "trade_scope_id": (
            str(fired.trade_scope_id) if fired.trade_scope_id else _NO_SCOPE_PUSH_VALUE
        ),
    }


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

    async def evaluate_budget(
        self, budget: Budget, *, spent: Decimal | None = None
    ) -> list[FiredBudgetAlert]:
        """Fire every newly crossed threshold for one budget, exactly once (BUDG-03).

        Never commits — the caller's transaction owns it, so a rollback
        un-claims the threshold too.
        """
        if spent is None:
            spent = await self._spend_for(budget)
        thresholds = crossed_thresholds(spent, budget.total)
        if not thresholds:
            return []
        context = await self.repository.alert_context(budget)
        if context is None:  # anchor gone/soft-deleted — never burn a claim
            return []
        fired: list[FiredBudgetAlert] = []
        for threshold in thresholds:
            alert = await self._fire_threshold(budget, threshold, spent, context)
            if alert is not None:
                fired.append(alert)
        if fired:
            self._schedule_budget_pushes(fired, await self._recipients_for(budget.company_id))
        return fired

    async def evaluate_for_project(self, project_id: uuid.UUID) -> list[FiredBudgetAlert]:
        """Evaluate the project's active budget, if any."""
        budget = await self.repository.active_for_project(project_id)
        if budget is None:
            return []
        return await self.evaluate_budget(budget)

    async def evaluate_for_trade_scope(self, trade_scope_id: uuid.UUID) -> list[FiredBudgetAlert]:
        """Evaluate the trade scope's active budget, if any."""
        budget = await self.repository.active_for_trade_scope(trade_scope_id)
        if budget is None:
            return []
        return await self.evaluate_budget(budget)

    async def _spend_for(self, budget: Budget) -> Decimal:
        """Current spend at the budget's anchor — always the single spend definition."""
        if budget.project_id is not None:
            return await self._finance_service().project_spend(budget.project_id)
        assert budget.trade_scope_id is not None  # XOR guaranteed at creation
        return await self._finance_service().trade_scope_spend(budget.trade_scope_id)

    async def _fire_threshold(
        self,
        budget: Budget,
        threshold: BudgetThreshold,
        spent: Decimal,
        context: BudgetAlertContext,
    ) -> FiredBudgetAlert | None:
        """Claim one crossing and write its dashboard alert; None if already claimed."""
        if not await self.repository.claim_threshold(budget.id, threshold):
            return None
        facts = BudgetFacts(
            project_name=context.project_name,
            trade_name=context.trade_name,
            spent=spent,
            total=budget.total,
        )
        impact_text = budget_alert_text(facts, threshold)
        alert = await AlertRepository(self.db).create(
            self._build_alert(budget, threshold, context, impact_text)
        )
        return FiredBudgetAlert(
            alert_id=alert.id,
            alert_type=alert.alert_type,
            company_id=budget.company_id,
            project_id=context.project_id,
            trade_scope_id=budget.trade_scope_id,
            title=push_title_for(threshold),
            body=impact_text,  # UI-SPEC: the push body is byte-identical to impact_text
        )

    def _build_alert(
        self,
        budget: Budget,
        threshold: BudgetThreshold,
        context: BudgetAlertContext,
        impact_text: str,
    ) -> DashboardAlert:
        """Assemble the DashboardAlert row for one fired threshold."""
        return DashboardAlert(
            company_id=budget.company_id,
            project_id=context.project_id,
            trade_scope_id=budget.trade_scope_id,
            severity=_SEVERITY_BY_THRESHOLD[threshold],
            alert_type=_ALERT_TYPE_BY_THRESHOLD[threshold],
            days_behind=None,
            impact_text=impact_text,
            remediation_text=None,
            affected_scope_ids=[],
            is_read=False,
            rescheduling_payload=None,
            rescheduling_accepted=None,
        )

    async def _recipients_for(self, company_id: uuid.UUID) -> list[uuid.UUID]:
        """finance.view holders per the live matrix, resolved in the CURRENT session
        (RLS + test visibility) before any background task is scheduled (D-05)."""
        from app.features.rbac.repository import RbacRepository

        return await RbacRepository(self.db).user_ids_with_permission(
            company_id, _FINANCE_VIEW_PERMISSION
        )

    @staticmethod
    def _schedule_budget_pushes(
        fired: list[FiredBudgetAlert], recipient_ids: list[uuid.UUID]
    ) -> None:
        """Fire-and-forget one FCM push per fired alert (checklists pattern)."""
        for alert in fired:
            task = asyncio.create_task(
                BudgetService._send_budget_push_safe(
                    company_id=alert.company_id,
                    recipient_ids=recipient_ids,
                    title=alert.title,
                    body=alert.body,
                    data=_push_data(alert),
                )
            )
            _BUDGET_PUSH_TASKS.add(task)
            task.add_done_callback(_BUDGET_PUSH_TASKS.discard)

    @staticmethod
    async def _send_budget_push_safe(
        company_id: uuid.UUID,
        recipient_ids: list[uuid.UUID],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> None:
        """Send one budget push in its own session — the request session is closed
        by the time this task runs (RESEARCH Pitfall 3). Never raises."""
        try:
            from app.core.database import async_session_factory
            from app.core.tenant import set_current_tenant_id
            from app.features.notifications.service import NotificationService

            set_current_tenant_id(company_id)
            async with async_session_factory() as db:
                await NotificationService(db).send_budget_alert_notification(
                    recipient_ids=recipient_ids, title=title, body=body, data=data
                )
                await db.commit()
        except Exception:
            logger.exception("budget alert push failed for company %s — continuing", company_id)
