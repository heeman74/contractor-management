"""Phase 36 — Profitability math: unit tests for the pure D-03 detection module.

Pure unit tests (no DB, no async, no fixtures beyond module-level builders). Cover:
- skip_reason_for: the D-01 eligibility gate and each named skip reason
- margin_decline_points: signal 1, read CUMULATIVELY, with the None-percent guard
- negative_margin_dollars: signal 2, read off dollars rather than percent
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from app.features.finance.margin_math import (
    REVENUE_BASIS_INVOICED,
    REVENUE_BASIS_NONE,
    MarginFigures,
    MarginInputs,
    ResolvedRevenue,
    summarize_margin,
)
from app.features.finance.portfolio_math import ProjectFinancialFigures
from app.features.finance.profitability_math import (
    MARGIN_DECLINE_POINTS,
    PROFITABILITY_ELIGIBLE_STATUSES,
    SkipReason,
    margin_decline_points,
    negative_margin_dollars,
    skip_reason_for,
)
from app.features.finance.trend_math import TREND_WINDOW_3M, TrendBucket, window_slice

PROJECT_ID = uuid.UUID("44444444-4444-4444-4444-444444444444")
ACTIVE_STATUS = "active"
INELIGIBLE_STATUSES = ("planning", "on_hold", "complete", "archived", "draft")


def _margin_figures(
    revenue: Decimal | None,
    cost: Decimal,
    *,
    unrated_seconds: int = 0,
    has_missing_cost_data: bool = False,
) -> MarginFigures:
    """A shipped margin block built by the shipped summarizer, never hand-assembled."""
    basis = REVENUE_BASIS_NONE if revenue is None else REVENUE_BASIS_INVOICED
    return summarize_margin(
        MarginInputs(
            revenue=ResolvedRevenue(total=revenue, basis=basis),
            cost=cost,
            unrated_seconds=unrated_seconds,
            has_missing_cost_data=has_missing_cost_data,
        )
    )


def _figures(
    *,
    status: str = ACTIVE_STATUS,
    revenue: Decimal | None = Decimal("1000.00"),
    cost: Decimal = Decimal("600.00"),
    unrated_seconds: int = 0,
    has_missing_cost_data: bool = False,
) -> ProjectFinancialFigures:
    """One project's shipped financial block with only the detection fields varied."""
    margin = _margin_figures(
        revenue,
        cost,
        unrated_seconds=unrated_seconds,
        has_missing_cost_data=has_missing_cost_data,
    )
    resolved = None if revenue is None else ResolvedRevenue(revenue, REVENUE_BASIS_INVOICED)
    return ProjectFinancialFigures(
        project_id=PROJECT_ID,
        name="Riverside Remodel",
        status=status,
        cost=cost,
        revenue=resolved,
        quoted_revenue=Decimal("0.00"),
        unrated_seconds=unrated_seconds,
        margin=margin,
        budgets=(),
    )


def _bucket(month: str, revenue: Decimal | None, cost: Decimal) -> TrendBucket:
    """One cumulative as-of bucket — revenue and cost are totals since inception."""
    return TrendBucket(month=month, cost=cost, margin=_margin_figures(revenue, cost))


def test_eligible_project_has_no_skip_reason() -> None:
    assert skip_reason_for(_figures()) is None


def test_eligible_statuses_are_active_only() -> None:
    assert PROFITABILITY_ELIGIBLE_STATUSES == (ACTIVE_STATUS,)


def test_skip_reason_not_active_for_every_ineligible_status() -> None:
    for status in INELIGIBLE_STATUSES:
        assert skip_reason_for(_figures(status=status)) is SkipReason.NOT_ACTIVE


def test_skip_reason_no_revenue_source_when_revenue_is_absent() -> None:
    assert skip_reason_for(_figures(revenue=None)) is SkipReason.NO_REVENUE_SOURCE


def test_skip_reason_no_cost_data_at_zero_cost() -> None:
    assert skip_reason_for(_figures(cost=Decimal("0.00"))) is SkipReason.NO_COST_DATA


def test_skip_reason_incomplete_data_for_unrated_labor() -> None:
    assert skip_reason_for(_figures(unrated_seconds=3600)) is SkipReason.INCOMPLETE_DATA


def test_skip_reason_no_cost_data_precedes_the_fabricated_margin_case() -> None:
    """Pitfall 9: revenue with zero cost would fabricate a 100% margin. Never analyzed."""
    fabricated = _figures(cost=Decimal("0.00"), has_missing_cost_data=True)

    assert fabricated.margin.incomplete is True
    assert skip_reason_for(fabricated) is SkipReason.NO_COST_DATA


def test_skip_reason_incomplete_data_when_another_anchor_lacks_cost() -> None:
    """A project with cost of its own still skips when the D-12 flag is raised."""
    flagged = _figures(has_missing_cost_data=True)

    assert skip_reason_for(flagged) is SkipReason.INCOMPLETE_DATA


def test_margin_decline_points_is_the_drop_across_the_last_two_buckets() -> None:
    buckets = [
        _bucket("2026-01", Decimal("1000.00"), Decimal("800.00")),
        _bucket("2026-02", Decimal("2000.00"), Decimal("1700.00")),
    ]

    assert margin_decline_points(buckets) == Decimal("5.0")


def test_margin_decline_points_below_the_trigger_is_not_a_candidate() -> None:
    buckets = [
        _bucket("2026-01", Decimal("1000.00"), Decimal("800.00")),
        _bucket("2026-02", Decimal("1000.00"), Decimal("849.00")),
    ]

    decline = margin_decline_points(buckets)

    assert decline == Decimal("4.9")
    assert decline < MARGIN_DECLINE_POINTS


def test_margin_decline_points_reads_cumulative_not_per_month_deltas() -> None:
    """RESEARCH Pitfall 4: the CUMULATIVE reading is the correct one.

    Per month the margin IMPROVES from 10% to 20%; cumulatively it ERODES from
    35.0% to 30.0% because the strong first month is being diluted. Buckets are
    as-of replays from project inception, so the cumulative drop is the signal.
    """
    buckets = [
        _bucket("2026-01", Decimal("1000.00"), Decimal("400.00")),
        _bucket("2026-02", Decimal("2000.00"), Decimal("1300.00")),
        _bucket("2026-03", Decimal("3000.00"), Decimal("2100.00")),
    ]

    assert [bucket.margin.margin_percent for bucket in buckets] == [
        Decimal("60.0"),
        Decimal("35.0"),
        Decimal("30.0"),
    ]
    assert margin_decline_points(buckets) == MARGIN_DECLINE_POINTS


def test_margin_decline_points_ignores_improvement() -> None:
    buckets = [
        _bucket("2026-01", Decimal("1000.00"), Decimal("900.00")),
        _bucket("2026-02", Decimal("2000.00"), Decimal("1400.00")),
    ]

    assert margin_decline_points(buckets) == Decimal("-20.0")


def test_margin_decline_points_needs_two_buckets() -> None:
    assert margin_decline_points([]) is None
    assert (
        margin_decline_points([_bucket("2026-01", Decimal("1000.00"), Decimal("800.00"))]) is None
    )


def test_margin_decline_points_never_coerces_an_absent_percent() -> None:
    """A None percent would read as a 100-point cliff if coerced to zero."""
    revenue_less = _bucket("2026-01", None, Decimal("800.00"))
    zero_revenue = _bucket("2026-02", Decimal("0.00"), Decimal("800.00"))
    earned = _bucket("2026-03", Decimal("1000.00"), Decimal("800.00"))

    assert revenue_less.margin.margin_percent is None
    assert zero_revenue.margin.margin_percent is None
    assert margin_decline_points([revenue_less, earned]) is None
    assert margin_decline_points([earned, zero_revenue]) is None


def test_margin_decline_is_unchanged_by_a_ui_trend_window() -> None:
    """The window setting slices what the chart draws — never what detection sees."""
    buckets = [
        _bucket("2025-12", Decimal("500.00"), Decimal("100.00")),
        _bucket("2026-01", Decimal("1000.00"), Decimal("400.00")),
        _bucket("2026-02", Decimal("2000.00"), Decimal("1300.00")),
        _bucket("2026-03", Decimal("3000.00"), Decimal("2100.00")),
    ]
    windowed = window_slice(buckets, TREND_WINDOW_3M)

    assert len(windowed) < len(buckets)
    assert margin_decline_points(windowed) == margin_decline_points(buckets)


def test_negative_margin_dollars_returns_the_loss() -> None:
    losing = _figures(revenue=Decimal("1000.00"), cost=Decimal("1350.00"))

    assert negative_margin_dollars(losing) == Decimal("-350.00")


def test_negative_margin_dollars_fires_at_zero_revenue() -> None:
    """margin_percent is None here while the dollar loss is real — dollars are safer."""
    unbilled = _figures(revenue=Decimal("0.00"), cost=Decimal("500.00"))

    assert unbilled.margin.margin_percent is None
    assert negative_margin_dollars(unbilled) == Decimal("-500.00")


def test_negative_margin_dollars_is_none_for_a_profitable_project() -> None:
    assert negative_margin_dollars(_figures()) is None


def test_negative_margin_dollars_is_none_at_break_even() -> None:
    break_even = _figures(revenue=Decimal("1000.00"), cost=Decimal("1000.00"))

    assert negative_margin_dollars(break_even) is None


def test_negative_margin_dollars_is_none_without_revenue() -> None:
    assert negative_margin_dollars(_figures(revenue=None)) is None
