"""Pure portfolio aggregation and attention-tier math for the finance domain (MARG-04).

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no repositories.
It writes no threshold and no margin arithmetic of its own — tiers come from the
shipped `budget_math.crossed_thresholds` / `percent_used`, and every portfolio
figure comes from `margin_math`. What is new here is only the D-08 tier ladder
and the order it ranks projects in.

D-11: a tier is derived from LIVE spent-vs-total state, never from the
`warning_fired_at` / `overrun_fired_at` columns. Those are an alert-dedup claim —
they null on re-arm and persist after spend drops — so consulting them would let
this list contradict the budget bars rendered beside it on the same screen.

D-09/D-12: every project rolls into the totals regardless of status and regardless
of its incomplete flag. Excluding one would misstate the portfolio; the entry
carries the status instead so the UI can de-emphasize it.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.features.finance.budget_math import BudgetThreshold, crossed_thresholds, percent_used
from app.features.finance.labor_derivation import CENTS, ZERO_MONEY
from app.features.finance.margin_math import (
    INCOMPLETE_NO_COST_DATA,
    REVENUE_BASIS_NONE,
    MarginFigures,
    MarginInputs,
    ResolvedRevenue,
    combine_revenue_bases,
    summarize_margin,
)

ATTENTION_TIER_OVERRUN = "overrun"
ATTENTION_TIER_WARNING = "warning"
ATTENTION_TIER_INCOMPLETE = "incomplete"
SCOPE_ANCHOR_LABEL_TEMPLATE = "{project_name} — {trade_name} scope"

_TIER_RANK: dict[str, int] = {
    ATTENTION_TIER_OVERRUN: 0,
    ATTENTION_TIER_WARNING: 1,
    ATTENTION_TIER_INCOMPLETE: 2,
}
_BUDGET_TIERS: tuple[tuple[str, BudgetThreshold], ...] = (
    (ATTENTION_TIER_OVERRUN, BudgetThreshold.overrun),
    (ATTENTION_TIER_WARNING, BudgetThreshold.warning),
)
_ZERO_PERCENT = Decimal("0")
_ABSENT_REVENUE = ResolvedRevenue(total=None, basis=REVENUE_BASIS_NONE)


@dataclass(frozen=True)
class AnchoredBudget:
    """One budget with the name its anchor carries in alert copy and in the attention list."""

    label: str
    spent: Decimal
    total: Decimal


@dataclass(frozen=True)
class ProjectFinancialFigures:
    """One project's shipped financial block, already resolved by the per-project math."""

    project_id: uuid.UUID
    name: str
    status: str
    cost: Decimal
    revenue: ResolvedRevenue | None
    quoted_revenue: Decimal
    unrated_seconds: int
    margin: MarginFigures
    budgets: Sequence[AnchoredBudget]


@dataclass(frozen=True)
class AttentionEntry:
    """One row of the D-08 attention list. The three budget fields are None for the
    incomplete tier — that tier has no percent, and fabricating one would be a lie."""

    project_id: uuid.UUID
    project_name: str
    project_status: str
    tier: str
    anchor_label: str
    spent: Decimal | None
    budget_total: Decimal | None
    percent_used: Decimal | None


@dataclass(frozen=True)
class PortfolioFigures:
    """Company-wide totals across every project, flagged and inactive ones included."""

    cost: Decimal
    quoted_revenue: Decimal | None
    incomplete_project_count: int
    margin: MarginFigures


def anchor_label_for(project_name: str, trade_name: str | None) -> str:
    """Name a budget's anchor the way the shipped alert copy names it."""
    if trade_name is None:
        return project_name
    return SCOPE_ANCHOR_LABEL_TEMPLATE.format(project_name=project_name, trade_name=trade_name)


def worst_crossed_budget(budgets: Sequence[AnchoredBudget]) -> tuple[str, AnchoredBudget] | None:
    """The budget that sets the project's tier: worst overrun, else worst warning.

    "Worst" is the highest percent_used within a tier, so a scope budget at 150% wins
    over its project budget at 90% and supplies the tier, the percent and the label.
    """
    by_tier = _budgets_by_tier(budgets)
    for tier, _ in _BUDGET_TIERS:
        crossed = by_tier[tier]
        if crossed:
            return tier, max(crossed, key=_percent_used_of)
    return None


def attention_entry_for(project: ProjectFinancialFigures) -> AttentionEntry | None:
    """This project's attention row, or None when it needs no attention."""
    crossed = worst_crossed_budget(project.budgets)
    if crossed is not None:
        return _budget_entry(project, *crossed)
    if project.margin.incomplete:
        return _incomplete_entry(project)
    return None


def attention_entries(projects: Sequence[ProjectFinancialFigures]) -> list[AttentionEntry]:
    """Every project needing attention, in D-08 order — no cap, no pagination."""
    entries = [attention_entry_for(project) for project in projects]
    return sorted((entry for entry in entries if entry is not None), key=_attention_sort_key)


def portfolio_totals(projects: Sequence[ProjectFinancialFigures]) -> PortfolioFigures:
    """Company-wide cost, revenue and margin — every project counts (D-09/D-12)."""
    cost = sum((project.cost for project in projects), ZERO_MONEY).quantize(CENTS)
    return PortfolioFigures(
        cost=cost,
        quoted_revenue=_portfolio_quoted_revenue(projects),
        incomplete_project_count=sum(1 for project in projects if _is_incomplete_tier(project)),
        margin=_portfolio_margin(projects, cost),
    )


def _budgets_by_tier(budgets: Sequence[AnchoredBudget]) -> dict[str, list[AnchoredBudget]]:
    """Partition budgets by the worst threshold each has crossed RIGHT NOW (D-11)."""
    partitions: dict[str, list[AnchoredBudget]] = {tier: [] for tier, _ in _BUDGET_TIERS}
    for budget in budgets:
        crossed = crossed_thresholds(budget.spent, budget.total)
        for tier, threshold in _BUDGET_TIERS:
            if threshold in crossed:
                partitions[tier].append(budget)
                break
    return partitions


def _percent_used_of(budget: AnchoredBudget) -> Decimal:
    """This budget's spend as a percent of its total, via the shipped rule."""
    return percent_used(budget.spent, budget.total)


def _budget_entry(
    project: ProjectFinancialFigures, tier: str, budget: AnchoredBudget
) -> AttentionEntry:
    """An overrun or warning row, named and measured by its offending budget."""
    return AttentionEntry(
        project_id=project.project_id,
        project_name=project.name,
        project_status=project.status,
        tier=tier,
        anchor_label=budget.label,
        spent=budget.spent,
        budget_total=budget.total,
        percent_used=_percent_used_of(budget),
    )


def _incomplete_entry(project: ProjectFinancialFigures) -> AttentionEntry:
    """An incomplete-data row: the project itself, with no budget figures to report."""
    return AttentionEntry(
        project_id=project.project_id,
        project_name=project.name,
        project_status=project.status,
        tier=ATTENTION_TIER_INCOMPLETE,
        anchor_label=project.name,
        spent=None,
        budget_total=None,
        percent_used=None,
    )


def _attention_sort_key(entry: AttentionEntry) -> tuple[int, Decimal, str]:
    """D-08 order: tier rank, then worst percent first, then project name."""
    percent = _ZERO_PERCENT if entry.percent_used is None else entry.percent_used
    return _TIER_RANK[entry.tier], -percent, entry.project_name


def _is_incomplete_tier(project: ProjectFinancialFigures) -> bool:
    """Whether this project lands in the incomplete TIER, not merely carries the flag.

    The D-09 badge count and the attention list read this one predicate, so a project
    that is both flagged and overrun is counted once, in the tier it actually renders in,
    and the badge can never disagree with the list beside it.
    """
    entry = attention_entry_for(project)
    return entry is not None and entry.tier == ATTENTION_TIER_INCOMPLETE


def _portfolio_margin(projects: Sequence[ProjectFinancialFigures], cost: Decimal) -> MarginFigures:
    """The portfolio margin block, through the same summarize_margin every anchor uses."""
    return summarize_margin(
        MarginInputs(
            revenue=_combined_portfolio_revenue(projects) or _ABSENT_REVENUE,
            cost=cost,
            unrated_seconds=sum(project.unrated_seconds for project in projects),
            has_missing_cost_data=any(
                INCOMPLETE_NO_COST_DATA in project.margin.incomplete_reasons for project in projects
            ),
        )
    )


def _combined_portfolio_revenue(
    projects: Sequence[ProjectFinancialFigures],
) -> ResolvedRevenue | None:
    """Revenue summed across projects that resolved one, or None when none did."""
    resolved = [
        project.revenue
        for project in projects
        if project.revenue is not None and project.revenue.total is not None
    ]
    if not resolved:
        return None
    return ResolvedRevenue(
        total=sum((revenue.total for revenue in resolved), ZERO_MONEY).quantize(CENTS),
        basis=combine_revenue_bases(revenue.basis for revenue in resolved),
    )


def _portfolio_quoted_revenue(projects: Sequence[ProjectFinancialFigures]) -> Decimal | None:
    """The estimated (quote-basis) share of portfolio revenue, absent when nothing is quoted."""
    total = sum((project.quoted_revenue for project in projects), ZERO_MONEY).quantize(CENTS)
    return total if total > ZERO_MONEY else None
