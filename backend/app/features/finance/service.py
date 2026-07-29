"""FinanceService — business logic for the cost-entry domain.

Wraps FinanceRepository; the router stays thin and delegates every operation
here (CLAUDE.md: router functions keep thin — delegate to service layer).

All CLAUDE.md rules apply:
- Inherits TenantScopedService[CostEntry]
- No db.commit() — get_db handles transaction lifecycle
- db.flush() when a generated id is needed before commit
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.base_service import TenantScopedService
from app.features.finance.budget_service import BudgetService
from app.features.finance.labor_derivation import (
    CENTS,
    LABOR_CATEGORY_NAME,
    ZERO_MONEY,
    LaborTotals,
    WorkSession,
    resolve_rate_row_for_work_date,
    summarize_labor,
)
from app.features.finance.margin_math import (
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    AnchorRevenue,
    MarginInputs,
    ResolvedRevenue,
    RevenueAnchor,
    anchor_revenues,
    combined_anchor_revenue,
    missing_cost_data,
    quoted_revenue,
    resolve_anchor_revenue,
    revenue_from,
    summarize_margin,
)
from app.features.finance.models import CostCategory, CostEntry, CostReceipt, LaborRate
from app.features.finance.repository import (
    FinanceRepository,
    LaborRateRepository,
    RevenueRepository,
)
from app.features.finance.schemas import (
    BudgetVsActual,
    CategoryTotal,
    CostBreakdownResponse,
    CostEntryCreate,
    CostEntryUpdate,
    LaborCostSummary,
    LaborRateCreate,
    MarginSummary,
    to_margin_summary,
)
from app.features.jobs.models import Job
from app.features.projects.models import TradeScope

_MANUAL_LABOR_DETAIL = "Labor cost is derived from tracked time."


def _group_rates_by_user(rates: Iterable[LaborRate]) -> dict[uuid.UUID, list[LaborRate]]:
    """Group resolver-ordered rate rows per worker, preserving the ascending sort."""
    grouped: dict[uuid.UUID, list[LaborRate]] = {}
    for rate in rates:
        grouped.setdefault(rate.user_id, []).append(rate)
    return grouped


@dataclass(frozen=True)
class ProjectCostSide:
    """Cost half of the project rollup — the single definition of project spend."""

    entries: list[CostEntry]
    sessions: list[WorkSession]
    rates: dict[uuid.UUID, list[LaborRate]]
    derived_labor: LaborTotals
    breakdown: CostBreakdownResponse


@dataclass(frozen=True)
class ProjectCostRollup:
    """Everything the project rollup endpoint needs from one service call."""

    entries: list[CostEntry]
    total: Decimal
    categories: list[CategoryTotal]
    labor: LaborTotals
    grand_total: Decimal
    margin: MarginSummary
    budget: BudgetVsActual | None


@dataclass(frozen=True)
class ProjectMarginContext:
    """Everything the project margin needs from the rollup that already ran."""

    anchor_costs: dict[RevenueAnchor, Decimal]
    labor_by_job: dict[uuid.UUID | None, LaborTotals]
    grand_total: Decimal
    unrated_seconds: int


@dataclass(frozen=True)
class MarginCostSide:
    """The cost half of the margin equation, already computed by the shipped breakdown."""

    total: Decimal
    unrated_seconds: int = 0


def _anchor_costs_from_entries(entries: Iterable[CostEntry]) -> dict[RevenueAnchor, Decimal]:
    """Sum already-fetched rollup entries per (job XOR scope) anchor — zero extra queries."""
    costs: dict[RevenueAnchor, Decimal] = {}
    for entry in entries:
        anchor = RevenueAnchor(job_id=entry.job_id, trade_scope_id=entry.trade_scope_id)
        costs[anchor] = costs.get(anchor, ZERO_MONEY) + entry.amount
    return costs


def _labor_by_job(
    sessions: Iterable[WorkSession],
    rates_by_contractor: dict[uuid.UUID, Sequence[LaborRate]],
) -> dict[uuid.UUID | None, LaborTotals]:
    """Per-job labor totals from the SAME sessions and rates the project total uses."""
    sessions_by_job: dict[uuid.UUID | None, list[WorkSession]] = {}
    for session in sessions:
        sessions_by_job.setdefault(session.job_id, []).append(session)
    return {
        job_id: summarize_labor(job_sessions, rates_by_contractor)
        for job_id, job_sessions in sessions_by_job.items()
    }


def _contributing_anchor_cost(anchor: RevenueAnchor, context: ProjectMarginContext) -> Decimal:
    """One anchor's cost-entry sum plus, for job anchors, its derived labor total."""
    cost = context.anchor_costs.get(anchor, ZERO_MONEY)
    if anchor.job_id is None:
        return cost
    labor = context.labor_by_job.get(anchor.job_id)
    return cost if labor is None else cost + labor.total


def _any_anchor_missing_cost_data(
    resolved_anchors: dict[RevenueAnchor, ResolvedRevenue], context: ProjectMarginContext
) -> bool:
    """D-12: any revenue-bearing anchor with zero cost flags the whole project."""
    return any(
        missing_cost_data(_contributing_anchor_cost(anchor, context), revenue.total)
        for anchor, revenue in resolved_anchors.items()
    )


def _build_breakdown(
    category_rows: Sequence[tuple[uuid.UUID, str, Decimal]],
    labor: LaborTotals | None,
    *,
    tracked_at_job_level: bool,
) -> CostBreakdownResponse:
    """Assemble a breakdown from GROUP BY rows plus (optionally) derived labor.

    Legacy manual labor-category entries are folded into the derived labor row so
    nothing hides and nothing double-counts (RESEARCH Pitfall 1). With no labor row
    to fold into (trade scopes), they stay visible as an ordinary category row —
    a trade scope derives no labor, so no double-count is possible there.
    """
    labor_total = labor.total if labor is not None else ZERO_MONEY
    categories: list[CategoryTotal] = []
    for category_id, category_name, total in category_rows:
        if labor is not None and category_name == LABOR_CATEGORY_NAME:
            labor_total += total
            continue
        categories.append(
            CategoryTotal(
                category_id=category_id,
                category_name=category_name,
                total=total.quantize(CENTS),
            )
        )
    grand_total = sum((category.total for category in categories), labor_total)
    labor_summary = (
        LaborCostSummary(
            total=labor_total.quantize(CENTS),
            rated_seconds=labor.rated_seconds,
            unrated_seconds=labor.unrated_seconds,
        )
        if labor is not None
        else None
    )
    return CostBreakdownResponse(
        categories=categories,
        labor=labor_summary,
        labor_tracked_at_job_level=tracked_at_job_level,
        grand_total=grand_total.quantize(CENTS),
    )


def _folded_labor(breakdown: CostBreakdownResponse, derived: LaborTotals) -> LaborTotals:
    """Derived labor with legacy manual labor-category entries folded in (Pitfall 1)."""
    folded_total = breakdown.labor.total if breakdown.labor is not None else derived.total
    return LaborTotals(
        total=folded_total,
        rated_seconds=derived.rated_seconds,
        unrated_seconds=derived.unrated_seconds,
    )


def _category_rows_from_entries(
    entries: Iterable[CostEntry],
) -> list[tuple[uuid.UUID, str, Decimal]]:
    """Group already-fetched (category-eager-loaded) entries — zero extra queries."""
    sums: dict[tuple[uuid.UUID, str], Decimal] = {}
    for entry in entries:
        key = (entry.category_id, entry.category.name)
        sums[key] = sums.get(key, ZERO_MONEY) + entry.amount
    return sorted(
        ((category_id, name, total) for (category_id, name), total in sums.items()),
        key=lambda row: row[1],
    )


class FinanceService(TenantScopedService[CostEntry]):
    """Service implementing cost-entry CRUD, category listing, and project rollup."""

    repository_class = FinanceRepository
    repository: FinanceRepository

    async def _reject_reserved_labor_category(self, category_id: uuid.UUID | None) -> None:
        """422 when a manual cost entry targets the reserved labor category.

        Labor is computed from tracked time x effective rate (COST-05); a manual
        labor entry would appear in both the category totals and the derived labor
        row (RESEARCH Pitfall 1 double-count).
        """
        if category_id is None:
            return
        if await self.repository.is_reserved_labor_category(category_id):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=_MANUAL_LABOR_DETAIL,
            )

    async def create_cost_entry(self, data: CostEntryCreate, company_id: uuid.UUID) -> CostEntry:
        """Create a cost entry anchored to a job XOR a trade scope (XOR enforced by schema)."""
        await self._reject_reserved_labor_category(data.category_id)
        entry = CostEntry(
            company_id=company_id,
            job_id=data.job_id,
            trade_scope_id=data.trade_scope_id,
            category_id=data.category_id,
            amount=data.amount,
            incurred_date=data.incurred_date,
            vendor=data.vendor,
            note=data.note,
        )
        await self.repository.create(entry)
        await self._evaluate_budgets_for_entry(entry)
        return await self.repository.get_entry_or_404(entry.id)

    async def _evaluate_budgets_for_entry(self, entry: CostEntry) -> None:
        """Re-check the budgets this cost entry affects (D-02, D-04).

        A scope-anchored entry affects the scope budget AND its project's budget;
        a job-anchored entry affects the project budget via jobs.project_id (a job
        with no project affects nothing). At most two evaluations, in this same
        transaction — a rollback un-does the alert and the threshold claim together.
        Every call site runs AFTER its mutation's flush, so the evaluation sees the
        post-mutation spend (RESEARCH Pitfall 5). BudgetService is imported at
        module level here — the service<->budget_service cycle is broken from the
        budget_service side (its lazy FinanceService import, the
        app/core/security.py::effective_permissions convention).
        """
        budget_service = BudgetService(self.db)
        if entry.trade_scope_id is not None:
            await budget_service.evaluate_for_trade_scope(entry.trade_scope_id)
            project_id = await self._project_id_for_trade_scope(entry.trade_scope_id)
        else:
            project_id = await self._project_id_for_job(entry.job_id)
        if project_id is not None:
            await budget_service.evaluate_for_project(project_id)

    async def _project_id_for_trade_scope(self, trade_scope_id: uuid.UUID) -> uuid.UUID | None:
        """The scope's project id in one column-only query (never a full-row load)."""
        result = await self.db.execute(
            select(TradeScope.project_id).where(TradeScope.id == trade_scope_id)
        )
        return result.scalar_one_or_none()

    async def _project_id_for_job(self, job_id: uuid.UUID | None) -> uuid.UUID | None:
        """The job's (nullable) project id in one column-only query."""
        result = await self.db.execute(select(Job.project_id).where(Job.id == job_id))
        return result.scalar_one_or_none()

    async def list_for_job(self, job_id: uuid.UUID) -> list[CostEntry]:
        """List non-soft-deleted cost entries for a job."""
        return await self.repository.list_for_job(job_id)

    async def list_for_trade_scope(self, trade_scope_id: uuid.UUID) -> list[CostEntry]:
        """List non-soft-deleted cost entries for a trade scope."""
        return await self.repository.list_for_trade_scope(trade_scope_id)

    async def get_entry_or_404(self, entry_id: uuid.UUID) -> CostEntry:
        """Fetch a single cost entry, or raise 404 if missing/soft-deleted."""
        return await self.repository.get_entry_or_404(entry_id)

    async def _project_cost_side(self, project_id: uuid.UUID) -> ProjectCostSide:
        """Entries + sessions + rates + derived labor + breakdown, computed once.

        3 cost/labor round trips. Rates are fetched ONCE and shared by the project
        labor total and the per-job margin split. Every project spend figure —
        rollup, budget block, alert evaluation — routes through this breakdown.
        """
        entries = await self.repository.rollup_for_project(project_id)
        sessions = await self.repository.completed_work_sessions_for_project(project_id)
        rates = await self.rates_by_contractor(sessions)
        derived_labor = summarize_labor(sessions, rates)
        breakdown = _build_breakdown(
            _category_rows_from_entries(entries), derived_labor, tracked_at_job_level=False
        )
        return ProjectCostSide(
            entries=entries,
            sessions=sessions,
            rates=rates,
            derived_labor=derived_labor,
            breakdown=breakdown,
        )

    async def project_spend(self, project_id: uuid.UUID) -> Decimal:
        """Project spend = the rollup's grand_total (cost entries + derived labor)."""
        return (await self._project_cost_side(project_id)).breakdown.grand_total

    async def trade_scope_spend(self, trade_scope_id: uuid.UUID) -> Decimal:
        """Scope spend = the scope breakdown's grand_total (all categories; labor is
        job-anchored, D-08, and is honestly excluded — the screen says so too)."""
        rows = await self.repository.category_totals_for_trade_scope(trade_scope_id)
        return _build_breakdown(rows, None, tracked_at_job_level=True).grand_total

    async def rollup_for_project(self, project_id: uuid.UUID) -> ProjectCostRollup:
        """Itemized entries + category totals + derived project labor + margin + budget.

        _project_cost_side's 3 round trips + 2 revenue + at most 1 D-14 quote + 1 budget.
        `total` keeps its pre-Phase-32 meaning (cost-entry sum) — mobile parses it strictly.
        """
        cost_side = await self._project_cost_side(project_id)
        entries, breakdown = cost_side.entries, cost_side.breakdown
        margin_context = ProjectMarginContext(
            anchor_costs=_anchor_costs_from_entries(entries),
            labor_by_job=_labor_by_job(cost_side.sessions, cost_side.rates),
            grand_total=breakdown.grand_total,
            unrated_seconds=cost_side.derived_labor.unrated_seconds,
        )
        return ProjectCostRollup(
            entries=entries,
            total=sum((entry.amount for entry in entries), Decimal("0")),
            categories=breakdown.categories,
            labor=_folded_labor(breakdown, cost_side.derived_labor),
            grand_total=breakdown.grand_total,
            margin=await self._project_margin(project_id, margin_context),
            budget=await BudgetService(self.db).budget_vs_actual_for_project(
                project_id, spent=breakdown.grand_total
            ),
        )

    async def _project_margin(
        self, project_id: uuid.UUID, context: ProjectMarginContext
    ) -> MarginSummary:
        """Project revenue and margin through the D-12 dual-outerjoin traversal.

        Both revenue legs are always fetched (two bounded queries): a quote at an
        anchor without invoices still counts, so the quote leg cannot be skipped just
        because SOME anchor is invoiced — anchor_revenues discards quotes at invoiced
        anchors instead. D-14 without a double-count: a project-anchored approved quote
        is the anchor of last resort — it counts only when NO anchor in the project
        resolved any revenue. Any invoice anywhere makes an anchor revenue-bearing,
        satisfying D-14's "entire project has zero invoices" condition while preventing
        a project quote from being added on top of the per-scope quotes it spawned.
        """
        revenue_repository = RevenueRepository(self.db)
        invoice_rows = await revenue_repository.invoice_amounts_by_anchor_for_project(project_id)
        quote_rows = await revenue_repository.approved_quote_amounts_by_anchor_for_project(
            project_id
        )
        resolved_anchors = anchor_revenues(invoice_rows, quote_rows)
        revenue = combined_anchor_revenue(resolved_anchors)
        if revenue is None:
            revenue = await self._project_fallback_revenue(revenue_repository, project_id)
        flagged = _any_anchor_missing_cost_data(resolved_anchors, context) or missing_cost_data(
            context.grand_total, revenue.total
        )
        return to_margin_summary(
            summarize_margin(
                MarginInputs(
                    revenue=revenue,
                    cost=context.grand_total,
                    unrated_seconds=context.unrated_seconds,
                    has_missing_cost_data=flagged,
                )
            )
        )

    async def _project_fallback_revenue(
        self, revenue_repository: RevenueRepository, project_id: uuid.UUID
    ) -> ResolvedRevenue:
        """D-14 anchor of last resort: the latest project-level approved quote, or nothing."""
        quote = await revenue_repository.latest_project_level_approved_quote_amounts(project_id)
        if quote is None:
            return ResolvedRevenue(total=None, basis=REVENUE_BASIS_NONE)
        return ResolvedRevenue(total=quoted_revenue(quote), basis=REVENUE_BASIS_QUOTED)

    async def rates_by_contractor(
        self, sessions: list[WorkSession]
    ) -> dict[uuid.UUID, list[LaborRate]]:
        """Every rate row for the contractors seen, in ONE bounded query (CLAUDE.md N+1 rule)."""
        contractor_ids = {session.contractor_id for session in sessions}
        if not contractor_ids:
            return {}
        rates = await LaborRateRepository(self.db).list_rates_for_users(sorted(contractor_ids))
        return _group_rates_by_user(rates)

    async def _derive_labor(self, sessions: list[WorkSession]) -> LaborTotals:
        """Cost tracked time from one bounded rate fetch — never a query per session."""
        return summarize_labor(sessions, await self.rates_by_contractor(sessions))

    async def _resolve_anchor_revenue(self, anchor: RevenueAnchor) -> ResolvedRevenue:
        """Invoices at this anchor, else its latest approved quote, else nothing (D-01/D-03).

        The quote query only runs when the anchor has no invoices — invoices win outright.
        """
        revenue_repository = RevenueRepository(self.db)
        invoices = await revenue_repository.invoice_amounts_for_anchor(anchor)
        if invoices:
            return resolve_anchor_revenue(AnchorRevenue(invoiced_total=revenue_from(invoices)))
        quote = await revenue_repository.latest_approved_quote_amounts_for_anchor(anchor)
        quoted_total = quoted_revenue(quote) if quote is not None else None
        return resolve_anchor_revenue(AnchorRevenue(quoted_total=quoted_total))

    async def _anchor_margin(self, anchor: RevenueAnchor, cost: MarginCostSide) -> MarginSummary:
        """The full margin block for one job or trade-scope anchor."""
        revenue = await self._resolve_anchor_revenue(anchor)
        return to_margin_summary(
            summarize_margin(
                MarginInputs(
                    revenue=revenue,
                    cost=cost.total,
                    unrated_seconds=cost.unrated_seconds,
                    has_missing_cost_data=missing_cost_data(cost.total, revenue.total),
                )
            )
        )

    async def job_cost_breakdown(self, job_id: uuid.UUID) -> CostBreakdownResponse:
        """Category totals + derived labor + margin for a job (3 cost + 1-2 revenue round trips)."""
        category_rows = await self.repository.category_totals_for_job(job_id)
        sessions = await self.repository.completed_work_sessions_for_job(job_id)
        labor = await self._derive_labor(sessions)
        breakdown = _build_breakdown(category_rows, labor, tracked_at_job_level=False)
        margin = await self._anchor_margin(
            RevenueAnchor(job_id=job_id),
            MarginCostSide(total=breakdown.grand_total, unrated_seconds=labor.unrated_seconds),
        )
        return breakdown.model_copy(update={"margin": margin})

    async def trade_scope_cost_breakdown(self, trade_scope_id: uuid.UUID) -> CostBreakdownResponse:
        """Category totals + margin for a scope (1 cost + 1-2 revenue round trips).

        Labor is job-anchored in v4.0 (D-08): labor=None, labor_tracked_at_job_level=True,
        unrated_seconds stays 0 — only no_cost_data can flag here (D-05).
        """
        category_rows = await self.repository.category_totals_for_trade_scope(trade_scope_id)
        breakdown = _build_breakdown(category_rows, None, tracked_at_job_level=True)
        margin = await self._anchor_margin(
            RevenueAnchor(trade_scope_id=trade_scope_id),
            MarginCostSide(total=breakdown.grand_total),
        )
        budget = await BudgetService(self.db).budget_vs_actual_for_trade_scope(
            trade_scope_id, spent=breakdown.grand_total
        )
        return breakdown.model_copy(update={"margin": margin, "budget": budget})

    async def update_cost_entry(self, entry_id: uuid.UUID, data: CostEntryUpdate) -> CostEntry:
        """Update a cost entry's amount/category/date/vendor/note (anchor is immutable)."""
        await self._reject_reserved_labor_category(data.category_id)
        entry = await self.repository.get_entry_or_404(entry_id)
        updates = data.model_dump(exclude_unset=True)
        for field, value in updates.items():
            setattr(entry, field, value)
        await self.db.flush()
        await self._evaluate_budgets_for_entry(entry)
        return await self.repository.get_entry_or_404(entry_id)

    async def delete_cost_entry(self, entry_id: uuid.UUID) -> None:
        """Soft-delete a cost entry (D-05) — excluded from lists/rollups afterward.

        The entry is fetched first so its anchor is known; soft_delete flushes,
        and the evaluation then sees the post-delete spend (Pitfall 5).
        """
        entry = await self.repository.get_entry_or_404(entry_id)
        await self.repository.soft_delete(entry_id)
        await self._evaluate_budgets_for_entry(entry)

    async def list_categories(self) -> list[CostCategory]:
        """List the current tenant's cost categories."""
        return await self.repository.list_categories()

    async def add_receipt(
        self,
        cost_entry_id: uuid.UUID,
        company_id: uuid.UUID,
        remote_url: str,
        caption: str | None,
    ) -> CostReceipt:
        """Create a receipt row attached to a cost entry."""
        receipt = CostReceipt(
            company_id=company_id,
            cost_entry_id=cost_entry_id,
            remote_url=remote_url,
            caption=caption,
        )
        return await self.repository.create(receipt)

    async def list_receipts(self, cost_entry_id: uuid.UUID) -> list[CostReceipt]:
        """List non-soft-deleted receipts for a cost entry."""
        return await self.repository.list_receipts_for_entry(cost_entry_id)

    async def delete_receipt(self, cost_entry_id: uuid.UUID, receipt_id: uuid.UUID) -> None:
        """Soft-delete a receipt, 404ing if it does not belong to the given cost entry."""
        receipt = await self.repository.get_receipt_or_404(receipt_id)
        if receipt.cost_entry_id != cost_entry_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Receipt not found")
        await self.repository.soft_delete_receipt(receipt_id)


class LaborRateService(TenantScopedService[LaborRate]):
    """Service for append-only labor rates (COST-04) — no update, no delete."""

    repository_class = LaborRateRepository
    repository: LaborRateRepository

    async def create_labor_rate(self, data: LaborRateCreate, company_id: uuid.UUID) -> LaborRate:
        """Append a rate row after confirming the worker belongs to this company."""
        if not await self.repository.user_exists(data.user_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
        rate = LaborRate(
            company_id=company_id,
            user_id=data.user_id,
            hourly_cost=data.hourly_cost,
            effective_from=data.effective_from,
        )
        return await self.repository.create(rate)

    async def list_rate_history(self, user_id: uuid.UUID) -> list[LaborRate]:
        """Full history for one worker (newest effective_from first)."""
        return await self.repository.list_history_for_user(user_id)

    async def list_current_rates(self, as_of: date | None = None) -> list[LaborRate]:
        """One currently-effective rate row per worker, for the Team page column.

        Fetches every rate in ONE query and resolves the current row per worker with
        the shared resolve_rate_row_for_work_date helper — the rule lives in exactly
        one place (labor_derivation), never duplicated in SQL. Future-dated rows are
        naturally excluded because their effective_from is greater than as_of.
        """
        today = as_of or datetime.now(UTC).date()
        grouped = _group_rates_by_user(await self.repository.list_all_rates())
        resolved = (
            resolve_rate_row_for_work_date(user_rates, today) for user_rates in grouped.values()
        )
        return [rate for rate in resolved if rate is not None]
