"""PortfolioService — company-wide financial rollup orchestration (MARG-04).

Serves `GET /financials/company` from ONE batched read path. Every database
await happens in `_fetch_portfolio_inputs`; every per-project function below is
pure and works from already-fetched rows, so the round-trip count is constant in
project count (CLAUDE.md's no-query-in-a-loop rule at company scale). The
shipped per-project path (`FinanceService.rollup_for_project`) is never called
from here — it is instead pinned to this one by
test_company_rollup_matches_rollup_for_project (backend/tests/test_phase_35_e2e.py).

D-12/D-09: every live project is included regardless of status and regardless of
its incomplete-data flag. `status` rides on each row so the UI can de-emphasize
a project, rather than the server silently dropping it from the totals.

No threshold, ordering or margin arithmetic lives here: tiers and totals come
from `portfolio_math`, margins from `margin_math`, budget blocks from the
shipped `_to_budget_vs_actual`.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import Row

from app.core.base_service import TenantScopedService, active_entity_or_404
from app.features.finance.budget_repository import BudgetRepository
from app.features.finance.budget_service import _to_budget_vs_actual
from app.features.finance.labor_derivation import (
    CENTS,
    ZERO_MONEY,
    WorkSession,
    summarize_labor,
)
from app.features.finance.margin_math import (
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    DocumentAmounts,
    MarginInputs,
    ResolvedRevenue,
    RevenueAnchor,
    anchor_revenues,
    combined_anchor_revenue,
    missing_cost_data,
    quoted_revenue,
    summarize_margin,
)
from app.features.finance.models import Budget, LaborRate
from app.features.finance.portfolio_math import (
    AnchoredBudget,
    AttentionEntry,
    PortfolioFigures,
    ProjectFinancialFigures,
    anchor_label_for,
    attention_entries,
    portfolio_totals,
)
from app.features.finance.portfolio_repository import PortfolioRepository
from app.features.finance.repository import FinanceRepository, LaborRateRepository
from app.features.finance.schemas import (
    AttentionRow,
    CompanyFinancialsResponse,
    CostBreakdownResponse,
    MarginTrendResponse,
    PortfolioTotals,
    ProjectFinancialsResponse,
    ProjectFinancialsRow,
    ProjectScopeBudgetRow,
    TrendBucketResponse,
    to_labor_cost_summary,
    to_margin_summary,
)
from app.features.finance.service import (
    FinanceService,
    ProjectCostRollup,
    ProjectMarginContext,
    _any_anchor_missing_cost_data,
    _build_breakdown,
    _group_rates_by_user,
    _labor_by_job,
)
from app.features.finance.trend_math import (
    DatedCost,
    TrendBucket,
    TrendInputs,
    trend_buckets,
    window_slice,
)
from app.features.projects.models import Project

type _AnchoredDocument = tuple[RevenueAnchor, DocumentAmounts]
type _ScopeLabels = dict[uuid.UUID, tuple[uuid.UUID, str]]

_ABSENT_REVENUE = ResolvedRevenue(total=None, basis=REVENUE_BASIS_NONE)
_PROJECT_NOT_FOUND = "Project not found"


@dataclass(frozen=True)
class ScopeBudget:
    """One trade-scope budget together with the trade name its label needs."""

    budget: Budget
    trade_name: str


@dataclass(frozen=True)
class BudgetInputs:
    """The tenant's active budgets, indexed per project, plus batched scope spends."""

    project_budgets: dict[uuid.UUID, Budget]
    scope_budgets: dict[uuid.UUID, list[ScopeBudget]]
    scope_spends: dict[uuid.UUID, Decimal]


@dataclass(frozen=True)
class PortfolioInputs:
    """Every row the company rollup needs, fetched once, keyed for O(1) project lookup."""

    projects: Sequence[Row]
    category_rows: dict[uuid.UUID, list[Row]]
    sessions: dict[uuid.UUID, list[WorkSession]]
    rates: dict[uuid.UUID, list[LaborRate]]
    invoices: dict[uuid.UUID, list[_AnchoredDocument]]
    quotes: dict[uuid.UUID, list[_AnchoredDocument]]
    project_level_quotes: dict[uuid.UUID, DocumentAmounts]
    budgets: BudgetInputs


@dataclass(frozen=True)
class ProjectCostBlocks:
    """One project's cost side: the shipped breakdown plus the margin context built from it.

    Both come out of one assembly pass, so the labor fold is applied exactly once:
    the margin needs the anchor costs and the grand total, while the profitability
    payload needs the category mix and the derived labor row — and a second pass
    could disagree with the first.
    """

    breakdown: CostBreakdownResponse
    context: ProjectMarginContext


@dataclass(frozen=True)
class ProjectRevenue:
    """A project's resolved revenue, its quote-basis share, and the D-12 honesty flag."""

    resolved: ResolvedRevenue | None
    quoted_share: Decimal
    has_missing_cost_data: bool


def _grouped_by_project[ItemT](
    pairs: Iterable[tuple[uuid.UUID, ItemT]],
) -> dict[uuid.UUID, list[ItemT]]:
    """Bucket (project id, item) pairs into per-project lists."""
    grouped: dict[uuid.UUID, list[ItemT]] = {}
    for project_id, item in pairs:
        grouped.setdefault(project_id, []).append(item)
    return grouped


def _documents_by_project(
    rows: Sequence[tuple[uuid.UUID, RevenueAnchor, DocumentAmounts]],
) -> dict[uuid.UUID, list[_AnchoredDocument]]:
    """Bucket project-keyed revenue documents per project, keeping their fetched order."""
    return _grouped_by_project(
        (project_id, (anchor, amounts)) for project_id, anchor, amounts in rows
    )


def _contractor_ids(sessions: Sequence[tuple[uuid.UUID, WorkSession]]) -> list[uuid.UUID]:
    """Every contractor with tracked time in the portfolio, in a deterministic order."""
    return sorted({session.contractor_id for _, session in sessions})


def _budget_inputs(
    budgets: Sequence[Budget], labels: _ScopeLabels, spends: dict[uuid.UUID, Decimal]
) -> BudgetInputs:
    """Index active budgets by the project each one hangs under.

    A scope budget whose scope is gone or soft-deleted has no label and is
    dropped — it can no longer be named, and naming it wrongly would mislabel an
    attention row.
    """
    scope_budgets: dict[uuid.UUID, list[ScopeBudget]] = {}
    for budget in budgets:
        label = labels.get(budget.trade_scope_id)
        if label is None:
            continue
        project_id, trade_name = label
        scope_budgets.setdefault(project_id, []).append(ScopeBudget(budget, trade_name))
    return BudgetInputs(
        project_budgets={
            budget.project_id: budget for budget in budgets if budget.project_id is not None
        },
        scope_budgets={
            project_id: sorted(scopes, key=lambda scope: scope.trade_name)
            for project_id, scopes in scope_budgets.items()
        },
        scope_spends=spends,
    )


def _category_rows(rows: Sequence[Row]) -> list[tuple[uuid.UUID, str, Decimal]]:
    """Collapse the anchor-keyed cost rows into the (id, name, total) shape
    `_build_breakdown` consumes, in the same name order the shipped rollup uses."""
    sums: dict[tuple[uuid.UUID, str], Decimal] = {}
    for row in rows:
        key = (row.category_id, row.category_name)
        sums[key] = sums.get(key, ZERO_MONEY) + row.total
    return sorted(
        ((category_id, name, total) for (category_id, name), total in sums.items()),
        key=lambda category: category[1],
    )


def _anchor_costs(rows: Sequence[Row]) -> dict[RevenueAnchor, Decimal]:
    """Sum the fetched cost rows per (job XOR scope) anchor — zero extra queries."""
    costs: dict[RevenueAnchor, Decimal] = {}
    for row in rows:
        anchor = RevenueAnchor(job_id=row.job_id, trade_scope_id=row.trade_scope_id)
        costs[anchor] = costs.get(anchor, ZERO_MONEY) + row.total
    return costs


def project_cost_blocks(project_id: uuid.UUID, inputs: PortfolioInputs) -> ProjectCostBlocks:
    """One project's whole cost side in ONE assembly pass, from already-fetched rows."""
    rows = inputs.category_rows.get(project_id, [])
    sessions = inputs.sessions.get(project_id, [])
    labor = summarize_labor(sessions, inputs.rates)
    breakdown = _build_breakdown(_category_rows(rows), labor, tracked_at_job_level=False)
    return ProjectCostBlocks(
        breakdown=breakdown,
        context=ProjectMarginContext(
            anchor_costs=_anchor_costs(rows),
            labor_by_job=_labor_by_job(sessions, inputs.rates),
            grand_total=breakdown.grand_total,
            unrated_seconds=labor.unrated_seconds,
        ),
    )


def _project_level_quote_revenue(
    project_id: uuid.UUID, inputs: PortfolioInputs
) -> ResolvedRevenue | None:
    """D-14 anchor of last resort: the project-anchored approved quote, or nothing."""
    quote = inputs.project_level_quotes.get(project_id)
    if quote is None:
        return None
    return ResolvedRevenue(total=quoted_revenue(quote), basis=REVENUE_BASIS_QUOTED)


def _quoted_share(contributors: Iterable[ResolvedRevenue]) -> Decimal:
    """The estimated (quote-basis) part of a project's revenue (D-09)."""
    quoted = [
        revenue.total
        for revenue in contributors
        if revenue.total is not None and revenue.basis == REVENUE_BASIS_QUOTED
    ]
    return sum(quoted, ZERO_MONEY).quantize(CENTS)


def _project_revenue(
    project_id: uuid.UUID, context: ProjectMarginContext, inputs: PortfolioInputs
) -> ProjectRevenue:
    """Revenue, its quote-basis share and the missing-cost flag, from fetched rows only.

    Both revenue legs are always present: `anchor_revenues` discards quotes at
    invoiced anchors (D-01), so a quote at an uninvoiced anchor still counts.
    """
    anchors = anchor_revenues(
        inputs.invoices.get(project_id, []), inputs.quotes.get(project_id, [])
    )
    resolved = combined_anchor_revenue(anchors)
    contributors: list[ResolvedRevenue] = list(anchors.values())
    if resolved is None:
        resolved = _project_level_quote_revenue(project_id, inputs)
        contributors = [] if resolved is None else [resolved]
    flagged = _any_anchor_missing_cost_data(anchors, context) or missing_cost_data(
        context.grand_total, None if resolved is None else resolved.total
    )
    return ProjectRevenue(
        resolved=resolved,
        quoted_share=_quoted_share(contributors),
        has_missing_cost_data=flagged,
    )


def _anchored_budgets(project: Row, spent: Decimal, budgets: BudgetInputs) -> list[AnchoredBudget]:
    """The project budget (spent = its grand_total) plus every scope budget under it."""
    anchored = [
        AnchoredBudget(
            label=anchor_label_for(project.name, scope.trade_name),
            spent=budgets.scope_spends[scope.budget.trade_scope_id],
            total=scope.budget.total,
        )
        for scope in budgets.scope_budgets.get(project.id, [])
    ]
    project_budget = budgets.project_budgets.get(project.id)
    if project_budget is None:
        return anchored
    project_anchor = AnchoredBudget(
        label=anchor_label_for(project.name, None), spent=spent, total=project_budget.total
    )
    return [project_anchor, *anchored]


def _project_figures(project: Row, inputs: PortfolioInputs) -> ProjectFinancialFigures:
    """One project's whole financial block, assembled from already-fetched data."""
    context = project_cost_blocks(project.id, inputs).context
    revenue = _project_revenue(project.id, context, inputs)
    return ProjectFinancialFigures(
        project_id=project.id,
        name=project.name,
        status=project.status,
        cost=context.grand_total,
        revenue=revenue.resolved,
        quoted_revenue=revenue.quoted_share,
        unrated_seconds=context.unrated_seconds,
        margin=summarize_margin(
            MarginInputs(
                revenue=revenue.resolved or _ABSENT_REVENUE,
                cost=context.grand_total,
                unrated_seconds=context.unrated_seconds,
                has_missing_cost_data=revenue.has_missing_cost_data,
            )
        ),
        budgets=_anchored_budgets(project, context.grand_total, inputs.budgets),
    )


def _to_portfolio_totals(totals: PortfolioFigures) -> PortfolioTotals:
    """Map the pure portfolio figures onto the wire block."""
    return PortfolioTotals(
        cost=totals.cost,
        quoted_revenue=totals.quoted_revenue,
        incomplete_project_count=totals.incomplete_project_count,
        margin=to_margin_summary(totals.margin),
    )


def _to_project_row(
    figures: ProjectFinancialFigures, budgets: BudgetInputs
) -> ProjectFinancialsRow:
    """Map one project's figures onto its overview row, project budget included."""
    budget = budgets.project_budgets.get(figures.project_id)
    return ProjectFinancialsRow(
        project_id=figures.project_id,
        name=figures.name,
        status=figures.status,
        cost=figures.cost,
        margin=to_margin_summary(figures.margin),
        budget=None if budget is None else _to_budget_vs_actual(budget, figures.cost),
    )


def _to_attention_row(entry: AttentionEntry) -> AttentionRow:
    """Map one pure attention entry onto its wire row."""
    return AttentionRow(
        project_id=entry.project_id,
        project_name=entry.project_name,
        project_status=entry.project_status,
        tier=entry.tier,
        anchor_label=entry.anchor_label,
        spent=entry.spent,
        budget_total=entry.budget_total,
        percent_used=entry.percent_used,
    )


def _rollup_breakdown(rollup: ProjectCostRollup) -> CostBreakdownResponse:
    """The shipped project rollup's aggregate half, verbatim.

    Nothing is re-derived here: a second definition of the category mix, the
    folded labor row, the margin or the project budget is exactly the Pitfall-1
    drift the equivalence tests exist to prevent.
    """
    return CostBreakdownResponse(
        categories=rollup.categories,
        labor=to_labor_cost_summary(rollup.labor),
        labor_tracked_at_job_level=False,
        grand_total=rollup.grand_total,
        margin=rollup.margin,
        budget=rollup.budget,
    )


def _budgets_by_scope(
    budgets: Iterable[Budget], scope_ids: Iterable[uuid.UUID]
) -> dict[uuid.UUID, Budget]:
    """This project's scope budgets indexed by scope, filtered from the fetched tenant list."""
    wanted = set(scope_ids)
    return {budget.trade_scope_id: budget for budget in budgets if budget.trade_scope_id in wanted}


def _scope_budget_row(scope: Row, budget: Budget | None, spent: Decimal) -> ProjectScopeBudgetRow:
    """One scope's drill-down row; `budget` is None when the scope has no active budget."""
    return ProjectScopeBudgetRow(
        trade_scope_id=scope.id,
        trade_name=scope.trade_name,
        spent=spent,
        budget=None if budget is None else _to_budget_vs_actual(budget, spent),
    )


def _scope_budget_rows(
    scopes: Sequence[Row], budgets: dict[uuid.UUID, Budget], spends: dict[uuid.UUID, Decimal]
) -> list[ProjectScopeBudgetRow]:
    """Every live scope in sort_order — one with no money still gets a row, spent 0.00."""
    return [_scope_budget_row(scope, budgets.get(scope.id), spends[scope.id]) for scope in scopes]


def _to_trend_response(
    project_id: uuid.UUID, window: str, buckets: Sequence[TrendBucket]
) -> MarginTrendResponse:
    """Map the pure trend buckets onto the wire block, margins through the shipped mapper."""
    return MarginTrendResponse(
        project_id=project_id,
        window=window,
        buckets=[
            TrendBucketResponse(
                month=bucket.month, cost=bucket.cost, margin=to_margin_summary(bucket.margin)
            )
            for bucket in buckets
        ],
    )


class PortfolioService(TenantScopedService[Project]):
    """Company-wide financial rollup for the web dashboard overview (MARG-04)."""

    repository_class = PortfolioRepository
    repository: PortfolioRepository

    async def all_project_figures(
        self,
    ) -> tuple[list[ProjectFinancialFigures], PortfolioInputs]:
        """Every project's shipped financial block plus the batched rows behind it.

        One company-wide read whose statement count is constant in project count
        (pinned by test_company_rollup_query_count_is_constant_in_project_count).
        The inputs travel with the figures because the D-03 quote-implied signal
        needs the raw per-anchor invoice and quote rows the figures already
        summarized.
        """
        inputs = await self._fetch_portfolio_inputs()
        return [_project_figures(project, inputs) for project in inputs.projects], inputs

    async def unsliced_trend_buckets(self, project_id: uuid.UUID) -> list[TrendBucket]:
        """The full cumulative bucket list, before any UI window slice.

        D-03 signal 1 must never be able to change with a window setting. Six
        bounded queries — the same profile as the shipped project rollup — then a
        pure Python replay in trend_math.
        """
        return trend_buckets(await self._trend_inputs(project_id))

    async def company_financials(self) -> CompanyFinancialsResponse:
        """Portfolio totals, every project's figures, and the ordered attention list."""
        figures, inputs = await self.all_project_figures()
        return CompanyFinancialsResponse(
            portfolio=_to_portfolio_totals(portfolio_totals(figures)),
            projects=[_to_project_row(project, inputs.budgets) for project in figures],
            attention=[_to_attention_row(entry) for entry in attention_entries(figures)],
        )

    async def project_financials(self, project_id: uuid.UUID) -> ProjectFinancialsResponse:
        """Category mix + derived labor + margin + budgets for one project (MARG-04).

        The shipped rollup supplies the project half, so no second definition of
        spend exists; the scope half costs three queries — scopes, active
        budgets, and ONE grouped BudgetRepository.scope_spends — never a per-scope
        spend call in a loop (Pitfall 6 / CLAUDE.md's no-query-in-a-loop rule).

        D-10: these figures deliberately do NOT come from the trend's final
        bucket, so switching the trend window never restates the headline numbers.
        """
        header = active_entity_or_404(
            await self.repository.project_header(project_id), _PROJECT_NOT_FOUND
        )
        rollup = await FinanceService(self.db).rollup_for_project(project_id)
        scopes = await self.repository.trade_scopes_for_project(project_id)
        scope_ids = [scope.id for scope in scopes]
        budget_repository = BudgetRepository(self.db)
        budgets = _budgets_by_scope(await budget_repository.list_active(), scope_ids)
        spends = await budget_repository.scope_spends(scope_ids)
        return ProjectFinancialsResponse(
            project_id=header.id,
            name=header.name,
            status=header.status,
            breakdown=_rollup_breakdown(rollup),
            scopes=_scope_budget_rows(scopes, budgets, spends),
        )

    async def margin_trend(self, project_id: uuid.UUID, window: str) -> MarginTrendResponse:
        """Monthly cumulative margin for one project (MARG-04, D-01/D-02).

        Buckets come from `unsliced_trend_buckets`, so the window slices the
        produced BUCKETS rather than the records: a month shared by two windows
        carries identical figures (Pitfall 2). Nothing is bucketed in SQL,
        because the effective-dated rate rule lives in exactly one place
        (labor_derivation) and must never be duplicated in a query (Phase 32).
        """
        active_entity_or_404(await self.repository.project_header(project_id), _PROJECT_NOT_FOUND)
        buckets = await self.unsliced_trend_buckets(project_id)
        return _to_trend_response(project_id, window, window_slice(buckets, window))

    async def _trend_inputs(self, project_id: uuid.UUID) -> TrendInputs:
        """Every database read the replay performs — all here, none inside a loop.

        The cost and session legs come from the SHIPPED FinanceRepository methods
        the project rollup uses, so the trend cannot drift from the figure its
        final bucket must reconcile with.
        """
        finance_repository = FinanceRepository(self.db)
        entries = await finance_repository.rollup_for_project(project_id)
        sessions = await finance_repository.completed_work_sessions_for_project(project_id)
        return TrendInputs(
            costs=[
                DatedCost(amount=entry.amount, incurred_date=entry.incurred_date)
                for entry in entries
            ],
            sessions=sessions,
            rates_by_contractor=await FinanceService(self.db).rates_by_contractor(sessions),
            invoices=await self.repository.dated_invoices_for_project(project_id),
            quotes=await self.repository.dated_quotes_for_project(project_id),
            fallback_quote=await self.repository.dated_project_level_quote(project_id),
            today=datetime.now(UTC).date(),
        )

    async def _fetch_portfolio_inputs(self) -> PortfolioInputs:
        """Every database read the company rollup performs — all here, none inside a loop."""
        budget_repository = BudgetRepository(self.db)
        sessions = await self.repository.work_sessions_by_project()
        budgets = await budget_repository.list_active()
        scope_ids = [budget.trade_scope_id for budget in budgets if budget.trade_scope_id]
        rates = await LaborRateRepository(self.db).list_rates_for_users(_contractor_ids(sessions))
        category_rows = await self.repository.category_totals_by_project()
        invoices = await self.repository.invoice_amounts_by_project()
        quotes = await self.repository.approved_quote_amounts_by_project()
        return PortfolioInputs(
            projects=await self.repository.list_projects(),
            category_rows=_grouped_by_project((row.project_id, row) for row in category_rows),
            sessions=_grouped_by_project(sessions),
            rates=_group_rates_by_user(rates),
            invoices=_documents_by_project(invoices),
            quotes=_documents_by_project(quotes),
            project_level_quotes=await self.repository.project_level_approved_quotes(),
            budgets=_budget_inputs(
                budgets,
                await self.repository.trade_scope_labels(scope_ids),
                await budget_repository.scope_spends(scope_ids),
            ),
        )
