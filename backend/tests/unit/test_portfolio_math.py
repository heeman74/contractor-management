"""Phase 35 — Portfolio math: unit tests for attention tiering and portfolio totals.

Pure unit tests (no DB, no async). Cover:
- the D-08 tier ladder: overrun -> warning -> incomplete -> absent
- D-11: tiers derive from live crossed_thresholds, never from fired timestamps
- worst-anchor selection across a project budget and its scope budgets
- D-09/D-12 honest aggregates: every project rolls in regardless of status or flag
- absent (never fabricated) percents, revenue, and quoted revenue
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, fields, replace
from decimal import Decimal

from app.features.finance.margin_math import (
    INCOMPLETE_NO_COST_DATA,
    INCOMPLETE_UNRATED_LABOR,
    REVENUE_BASIS_INVOICED,
    REVENUE_BASIS_MIXED,
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    MarginFigures,
    ResolvedRevenue,
)
from app.features.finance.portfolio_math import (
    ATTENTION_TIER_INCOMPLETE,
    ATTENTION_TIER_OVERRUN,
    ATTENTION_TIER_WARNING,
    AnchoredBudget,
    ProjectFinancialFigures,
    anchor_label_for,
    attention_entries,
    attention_entry_for,
    portfolio_totals,
    worst_crossed_budget,
)

PROJECT_STATUS_ACTIVE = "active"
PROJECT_STATUS_ARCHIVED = "archived"
ZERO = Decimal("0.00")


@dataclass(frozen=True)
class _Money:
    """Readable budget shorthand for the tests: spend as a percent of a $1,000 budget."""

    total = Decimal("1000.00")


def _budget(label: str, percent: str) -> AnchoredBudget:
    spent = (_Money.total * Decimal(percent) / Decimal("100")).quantize(Decimal("0.01"))
    return AnchoredBudget(label=label, spent=spent, total=_Money.total)


def _margin(
    *,
    revenue: str | None = "1000.00",
    basis: str = REVENUE_BASIS_INVOICED,
    reasons: tuple[str, ...] = (),
) -> MarginFigures:
    if revenue is None:
        return MarginFigures(
            revenue=None,
            revenue_basis=REVENUE_BASIS_NONE,
            margin=None,
            margin_percent=None,
            incomplete=False,
            incomplete_reasons=(),
        )
    return MarginFigures(
        revenue=Decimal(revenue),
        revenue_basis=basis,
        margin=Decimal(revenue) - Decimal("600.00"),
        margin_percent=Decimal("40.0"),
        incomplete=bool(reasons),
        incomplete_reasons=reasons,
    )


def _project(name: str, **overrides) -> ProjectFinancialFigures:
    base = ProjectFinancialFigures(
        project_id=uuid.uuid5(uuid.NAMESPACE_DNS, name),
        name=name,
        status=PROJECT_STATUS_ACTIVE,
        cost=Decimal("600.00"),
        revenue=ResolvedRevenue(total=Decimal("1000.00"), basis=REVENUE_BASIS_INVOICED),
        quoted_revenue=ZERO,
        unrated_seconds=0,
        margin=_margin(),
        budgets=(),
    )
    return replace(base, **overrides)


def _tiers(projects) -> list[str]:
    return [entry.tier for entry in attention_entries(projects)]


def _names(projects) -> list[str]:
    return [entry.project_name for entry in attention_entries(projects)]


# ---------------------------------------------------------------------------
# The D-08 tier ladder
# ---------------------------------------------------------------------------


def test_overrun_budget_puts_the_project_in_the_overrun_tier():
    project = _project("Maple", budgets=(_budget("Maple", "130"),))
    entry = attention_entry_for(project)
    assert entry.tier == ATTENTION_TIER_OVERRUN
    assert entry.percent_used == Decimal("130.0")


def test_warning_budget_puts_the_project_in_the_warning_tier():
    entry = attention_entry_for(_project("Maple", budgets=(_budget("Maple", "85"),)))
    assert entry.tier == ATTENTION_TIER_WARNING
    assert entry.percent_used == Decimal("85.0")


def test_incomplete_margin_without_a_crossed_budget_lands_in_the_incomplete_tier():
    project = _project(
        "Maple",
        margin=_margin(reasons=(INCOMPLETE_UNRATED_LABOR,)),
        budgets=(_budget("Maple", "40"),),
    )
    assert attention_entry_for(project).tier == ATTENTION_TIER_INCOMPLETE


def test_healthy_project_is_absent_from_the_list():
    assert attention_entry_for(_project("Maple", budgets=(_budget("Maple", "40"),))) is None
    assert attention_entries([_project("Maple")]) == []


def test_overrun_outranks_an_incomplete_flag_on_the_same_project():
    project = _project(
        "Maple",
        margin=_margin(reasons=(INCOMPLETE_UNRATED_LABOR,)),
        budgets=(_budget("Maple", "130"),),
    )
    assert attention_entry_for(project).tier == ATTENTION_TIER_OVERRUN


# ---------------------------------------------------------------------------
# Ordering
# ---------------------------------------------------------------------------


def test_tier_order_is_overrun_then_warning_then_incomplete():
    projects = [
        _project("Incomplete", margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,))),
        _project("Warning", budgets=(_budget("Warning", "85"),)),
        _project("Overrun", budgets=(_budget("Overrun", "130"),)),
    ]
    assert _tiers(projects) == [
        ATTENTION_TIER_OVERRUN,
        ATTENTION_TIER_WARNING,
        ATTENTION_TIER_INCOMPLETE,
    ]


def test_budget_tiers_sort_by_descending_percent_used():
    projects = [
        _project("Milder", budgets=(_budget("Milder", "110"),)),
        _project("Worst", budgets=(_budget("Worst", "180"),)),
        _project("Middle", budgets=(_budget("Middle", "140"),)),
    ]
    assert _names(projects) == ["Worst", "Middle", "Milder"]


def test_incomplete_tier_sorts_by_ascending_project_name():
    projects = [
        _project("Zephyr", margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,))),
        _project("Alder", margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,))),
    ]
    assert _names(projects) == ["Alder", "Zephyr"]


# ---------------------------------------------------------------------------
# D-11 — live threshold state, never the alert-claim timestamps
# ---------------------------------------------------------------------------


def test_overrun_tier_ignores_fired_timestamps_by_construction():
    """No input or output field can carry a fired timestamp, so none can be consulted."""
    field_names = {field.name for field in fields(AnchoredBudget)}
    field_names |= {field.name for field in fields(ProjectFinancialFigures)}
    assert not any("fired" in name for name in field_names)
    assert attention_entry_for(_project("Maple", budgets=(_budget("Maple", "130"),))).tier == (
        ATTENTION_TIER_OVERRUN
    )


# ---------------------------------------------------------------------------
# Worst anchor and its label
# ---------------------------------------------------------------------------


def test_worst_anchor_across_project_and_scope_budgets_wins():
    project = _project(
        "Maple",
        budgets=(_budget("Maple", "90"), _budget("Maple — Framing scope", "150")),
    )
    entry = attention_entry_for(project)
    assert entry.anchor_label == "Maple — Framing scope"
    assert entry.percent_used == Decimal("150.0")
    assert entry.tier == ATTENTION_TIER_OVERRUN


def test_worst_crossed_budget_is_none_when_nothing_crossed():
    assert worst_crossed_budget((_budget("Maple", "40"),)) is None
    assert worst_crossed_budget(()) is None


def test_project_anchor_label_is_the_project_name():
    assert anchor_label_for("Maple", None) == "Maple"


def test_scope_anchor_label_names_the_trade_scope():
    assert anchor_label_for("Maple", "Framing") == "Maple — Framing scope"


def test_incomplete_entries_carry_no_percent():
    entry = attention_entry_for(
        _project("Maple", margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,)))
    )
    assert entry.anchor_label == "Maple"
    assert entry.spent is None
    assert entry.budget_total is None
    assert entry.percent_used is None


# ---------------------------------------------------------------------------
# Portfolio totals — D-09 / D-12 honest aggregates
# ---------------------------------------------------------------------------


def test_portfolio_totals_include_flagged_and_inactive_projects():
    projects = [
        _project("Active", cost=Decimal("600.00")),
        _project("Archived", status=PROJECT_STATUS_ARCHIVED, cost=Decimal("250.00")),
        _project(
            "Flagged",
            cost=Decimal("150.00"),
            margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,)),
        ),
    ]
    totals = portfolio_totals(projects)
    assert totals.cost == Decimal("1000.00")
    assert totals.margin.revenue == Decimal("3000.00")


def test_incomplete_project_count_matches_the_incomplete_tier_size():
    """The D-09 badge and the attention list read the same set, so they cannot disagree."""
    projects = [
        _project("Flagged", margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,))),
        _project(
            "FlaggedAndOverrun",
            margin=_margin(reasons=(INCOMPLETE_NO_COST_DATA,)),
            budgets=(_budget("FlaggedAndOverrun", "130"),),
        ),
        _project("Healthy"),
    ]
    incomplete = [
        entry for entry in attention_entries(projects) if entry.tier == ATTENTION_TIER_INCOMPLETE
    ]
    assert portfolio_totals(projects).incomplete_project_count == len(incomplete) == 1


def test_portfolio_margin_carries_unrated_labor_across_projects():
    projects = [_project("Maple", unrated_seconds=3600), _project("Alder")]
    totals = portfolio_totals(projects)
    assert totals.margin.incomplete is True
    assert INCOMPLETE_UNRATED_LABOR in totals.margin.incomplete_reasons


def test_portfolio_revenue_is_none_when_no_project_resolved_any():
    projects = [_project("Maple", revenue=None, margin=_margin(revenue=None))]
    totals = portfolio_totals(projects)
    assert totals.margin.revenue is None
    assert totals.margin.revenue_basis == REVENUE_BASIS_NONE


def test_portfolio_revenue_basis_mixes_across_projects():
    projects = [
        _project("Invoiced"),
        _project(
            "Quoted",
            revenue=ResolvedRevenue(total=Decimal("500.00"), basis=REVENUE_BASIS_QUOTED),
            quoted_revenue=Decimal("500.00"),
        ),
    ]
    totals = portfolio_totals(projects)
    assert totals.margin.revenue == Decimal("1500.00")
    assert totals.margin.revenue_basis == REVENUE_BASIS_MIXED


def test_quoted_revenue_is_none_when_no_quote_basis_anchor():
    assert portfolio_totals([_project("Maple")]).quoted_revenue is None


def test_quoted_revenue_sums_the_estimated_share():
    projects = [
        _project("Maple", quoted_revenue=Decimal("500.00")),
        _project("Alder", quoted_revenue=Decimal("250.00")),
    ]
    assert portfolio_totals(projects).quoted_revenue == Decimal("750.00")


def test_portfolio_totals_of_no_projects_are_empty_not_fabricated():
    totals = portfolio_totals([])
    assert totals.cost == ZERO
    assert totals.quoted_revenue is None
    assert totals.margin.revenue is None
    assert totals.incomplete_project_count == 0
