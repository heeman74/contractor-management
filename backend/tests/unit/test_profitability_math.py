"""Phase 36 — Profitability math: unit tests for the pure D-03 detection module.

Pure unit tests (no DB, no async, no fixtures beyond module-level builders). Cover:
- skip_reason_for: the D-01 eligibility gate and each named skip reason
- margin_decline_points: signal 1, read CUMULATIVELY, with the None-percent guard
- negative_margin_dollars: signal 2, read off dollars rather than percent
- quote_implied_gap: signal 3, built from raw quote rows with the tautology guard
- band_for / fingerprint_for / candidate_for: bands, D-06 dedup key, one candidate
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from app.features.finance.margin_math import (
    REVENUE_BASIS_INVOICED,
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    DocumentAmounts,
    MarginFigures,
    MarginInputs,
    ResolvedRevenue,
    RevenueAnchor,
    summarize_margin,
)
from app.features.finance.portfolio_math import ProjectFinancialFigures
from app.features.finance.profitability_math import (
    CRITICAL_DECLINE_POINTS,
    CRITICAL_QUOTE_GAP_POINTS,
    MARGIN_DECLINE_POINTS,
    PRIMARY_SIGNAL_ORDER,
    PROFITABILITY_ELIGIBLE_STATUSES,
    QUOTE_IMPLIED_GAP_POINTS,
    SEVERITY_BAND_CRITICAL,
    SEVERITY_BAND_WARNING,
    SIGNAL_MARGIN_DECLINE,
    SIGNAL_NEGATIVE_MARGIN,
    SIGNAL_QUOTE_GAP,
    DetectionInputs,
    QuoteGap,
    QuoteGapInputs,
    SkipReason,
    band_for,
    candidate_for,
    fingerprint_for,
    latest_quote_per_anchor,
    margin_decline_points,
    negative_margin_dollars,
    quote_implied_gap,
    skip_reason_for,
)
from app.features.finance.trend_math import TREND_WINDOW_3M, TrendBucket, window_slice

PROJECT_ID = uuid.UUID("44444444-4444-4444-4444-444444444444")
ACTIVE_STATUS = "active"
INELIGIBLE_STATUSES = ("planning", "on_hold", "complete", "archived", "draft")
INVOICED_ANCHOR = RevenueAnchor(job_id=uuid.UUID("55555555-5555-5555-5555-555555555555"))
QUOTED_ANCHOR = RevenueAnchor(trade_scope_id=uuid.UUID("66666666-6666-6666-6666-666666666666"))
UNQUOTED_ANCHOR = RevenueAnchor(job_id=uuid.UUID("77777777-7777-7777-7777-777777777777"))
UNBILLED_ANCHOR = RevenueAnchor(job_id=uuid.UUID("88888888-8888-8888-8888-888888888888"))


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


def _amounts(subtotal: str) -> DocumentAmounts:
    """An undiscounted, untaxed document so the pre-tax leg equals the subtotal."""
    return DocumentAmounts(
        subtotal=Decimal(subtotal),
        discount_type=None,
        discount_value=Decimal("0"),
        tax_rate=Decimal("0"),
    )


def _invoiced(total: str) -> ResolvedRevenue:
    return ResolvedRevenue(total=Decimal(total), basis=REVENUE_BASIS_INVOICED)


def _gap_inputs(*, billed: str, quoted: str, cost: str) -> QuoteGapInputs:
    """One invoiced anchor that also carries an approved quote — the signal-3 shape."""
    return QuoteGapInputs(
        resolved={INVOICED_ANCHOR: _invoiced(billed)},
        latest_quotes={INVOICED_ANCHOR: _amounts(quoted)},
        anchor_costs={INVOICED_ANCHOR: Decimal(cost)},
    )


NO_QUOTE_GAP_INPUTS = QuoteGapInputs(resolved={}, latest_quotes={}, anchor_costs={})


def _quote_gap_of(points: Decimal) -> QuoteGap:
    """A gap result at a chosen magnitude, for banding tests that skip the arithmetic."""
    return QuoteGap(
        points=points,
        billed_margin_percent=Decimal("50.0"),
        quote_implied_margin_percent=Decimal("50.0") + points,
        over_quote_dollars=Decimal("100.00"),
    )


def _declining_buckets(latest_cost: Decimal) -> list[TrendBucket]:
    """Two cumulative buckets at constant revenue, so cost alone sets the decline."""
    return [
        _bucket("2026-01", Decimal("1000.00"), Decimal("800.00")),
        _bucket("2026-02", Decimal("1000.00"), latest_cost),
    ]


def _detection_inputs(
    *,
    figures: ProjectFinancialFigures | None = None,
    buckets: list[TrendBucket] | None = None,
    gap_inputs: QuoteGapInputs | None = None,
) -> DetectionInputs:
    """One project's detection pass with only the signals under test made to fire."""
    return DetectionInputs(
        figures=_figures() if figures is None else figures,
        buckets=[] if buckets is None else buckets,
        quote_gap_inputs=NO_QUOTE_GAP_INPUTS if gap_inputs is None else gap_inputs,
    )


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


def test_latest_quote_per_anchor_keeps_the_newest_row_per_anchor() -> None:
    """Rows arrive newest-first per anchor, so the first row seen is the latest quote."""
    rows = [
        (INVOICED_ANCHOR, _amounts("2000.00")),
        (INVOICED_ANCHOR, _amounts("1500.00")),
        (QUOTED_ANCHOR, _amounts("800.00")),
    ]

    latest = latest_quote_per_anchor(rows)

    assert latest[INVOICED_ANCHOR].subtotal == Decimal("2000.00")
    assert latest[QUOTED_ANCHOR].subtotal == Decimal("800.00")


def test_latest_quote_per_anchor_is_empty_without_rows() -> None:
    assert latest_quote_per_anchor([]) == {}


def test_quote_implied_gap_fires_at_exactly_five_points() -> None:
    gap = quote_implied_gap(
        _gap_inputs(
            billed="1000.00",
            quoted="2000.00",
            cost="100.00",
        )
    )

    assert gap is not None
    assert gap.billed_margin_percent == Decimal("90.0")
    assert gap.quote_implied_margin_percent == Decimal("95.0")
    assert gap.points == QUOTE_IMPLIED_GAP_POINTS


def test_quote_implied_gap_below_the_trigger_is_not_a_candidate() -> None:
    gap = quote_implied_gap(_gap_inputs(billed="1000.00", quoted="2000.00", cost="98.00"))

    assert gap is not None
    assert gap.points == Decimal("4.9")
    assert gap.points < QUOTE_IMPLIED_GAP_POINTS


def test_quote_implied_gap_over_quote_dollars_is_implied_minus_billed() -> None:
    gap = quote_implied_gap(_gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00"))

    assert gap is not None
    assert gap.over_quote_dollars == Decimal("1000.00")


def test_quote_implied_gap_uses_the_quote_at_an_invoiced_anchor() -> None:
    """The shipped D-01 resolution discards this quote; the signal needs exactly it.

    A gap can only exist because the invoiced anchor's approved quote survived —
    if the resolution helper had supplied the quote leg, there would be no quote
    here at all and the comparable set would be empty.
    """
    inputs = _gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00")

    assert inputs.resolved[INVOICED_ANCHOR].basis == REVENUE_BASIS_INVOICED
    assert INVOICED_ANCHOR in inputs.latest_quotes
    assert quote_implied_gap(inputs) is not None


def test_quote_implied_gap_compares_only_the_shared_anchor_set() -> None:
    """An unquoted invoiced anchor and an uninvoiced quote both drop out."""
    shared = _gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00")
    with_strangers = QuoteGapInputs(
        resolved={**shared.resolved, UNQUOTED_ANCHOR: _invoiced("5000.00")},
        latest_quotes={**shared.latest_quotes, UNBILLED_ANCHOR: _amounts("9000.00")},
        anchor_costs={
            **shared.anchor_costs,
            UNQUOTED_ANCHOR: Decimal("4000.00"),
            UNBILLED_ANCHOR: Decimal("50.00"),
        },
    )

    assert quote_implied_gap(with_strangers) == quote_implied_gap(shared)


def test_quote_implied_gap_is_none_for_a_quote_only_project() -> None:
    """Pitfall 5: billed revenue IS quote revenue, so the gap is vacuously zero."""
    quote_only = QuoteGapInputs(
        resolved={QUOTED_ANCHOR: ResolvedRevenue(Decimal("2000.00"), REVENUE_BASIS_QUOTED)},
        latest_quotes={QUOTED_ANCHOR: _amounts("2000.00")},
        anchor_costs={QUOTED_ANCHOR: Decimal("100.00")},
    )

    assert quote_implied_gap(quote_only) is None


def test_quote_implied_gap_is_none_without_a_shared_anchor() -> None:
    disjoint = QuoteGapInputs(
        resolved={INVOICED_ANCHOR: _invoiced("1000.00")},
        latest_quotes={UNBILLED_ANCHOR: _amounts("2000.00")},
        anchor_costs={INVOICED_ANCHOR: Decimal("100.00")},
    )

    assert quote_implied_gap(disjoint) is None


def test_quote_implied_gap_is_none_at_zero_quote_revenue() -> None:
    """margin_percent_for is None at zero revenue — never coerced into a percent."""
    zero_quote = _gap_inputs(billed="1000.00", quoted="0.00", cost="100.00")

    assert quote_implied_gap(zero_quote) is None


def test_quote_implied_gap_is_none_at_zero_billed_revenue() -> None:
    zero_billed = _gap_inputs(billed="0.00", quoted="2000.00", cost="100.00")

    assert quote_implied_gap(zero_billed) is None


def test_quote_implied_gap_sums_cost_through_the_supplied_anchor_costs() -> None:
    """Anchor costs arrive from the shipped contributing_anchor_cost helper, so
    job-anchored derived labor is already folded in exactly once."""
    without_labor = _gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00")
    with_labor = _gap_inputs(billed="1000.00", quoted="2000.00", cost="500.00")

    lean = quote_implied_gap(without_labor)
    burdened = quote_implied_gap(with_labor)

    assert lean is not None
    assert burdened is not None
    assert burdened.points > lean.points


def test_band_for_negative_margin_is_critical_at_any_magnitude() -> None:
    """Money is already lost — magnitude does not soften that."""
    assert band_for(SIGNAL_NEGATIVE_MARGIN, None, None) == SEVERITY_BAND_CRITICAL
    assert band_for(SIGNAL_NEGATIVE_MARGIN, Decimal("0.1"), None) == SEVERITY_BAND_CRITICAL


def test_band_for_decline_at_the_critical_boundary() -> None:
    assert band_for(SIGNAL_MARGIN_DECLINE, CRITICAL_DECLINE_POINTS, None) == SEVERITY_BAND_CRITICAL
    assert band_for(SIGNAL_MARGIN_DECLINE, Decimal("9.9"), None) == SEVERITY_BAND_WARNING


def test_band_for_quote_gap_at_the_critical_boundary() -> None:
    critical = _quote_gap_of(CRITICAL_QUOTE_GAP_POINTS)
    warning = _quote_gap_of(Decimal("9.9"))

    assert band_for(SIGNAL_QUOTE_GAP, None, critical) == SEVERITY_BAND_CRITICAL
    assert band_for(SIGNAL_QUOTE_GAP, None, warning) == SEVERITY_BAND_WARNING


def test_fingerprint_for_renders_project_signal_and_band() -> None:
    fingerprint = fingerprint_for(PROJECT_ID, SIGNAL_QUOTE_GAP, SEVERITY_BAND_WARNING)

    assert fingerprint == f"{PROJECT_ID}:{SIGNAL_QUOTE_GAP}:{SEVERITY_BAND_WARNING}"


def test_fingerprint_is_identical_across_repeated_detection_runs() -> None:
    inputs = _detection_inputs(buckets=_declining_buckets(Decimal("851.00")))

    first = candidate_for(inputs)
    second = candidate_for(inputs)

    assert first is not None
    assert second is not None
    assert first.fingerprint == second.fingerprint


def test_fingerprint_changes_when_the_band_worsens() -> None:
    """D-06 re-fires on worsening precisely because the band sits in the fingerprint."""
    warning = candidate_for(_detection_inputs(buckets=_declining_buckets(Decimal("851.00"))))
    critical = candidate_for(_detection_inputs(buckets=_declining_buckets(Decimal("900.00"))))

    assert warning is not None
    assert critical is not None
    assert warning.band == SEVERITY_BAND_WARNING
    assert critical.band == SEVERITY_BAND_CRITICAL
    assert warning.fingerprint != critical.fingerprint


def test_candidate_for_is_none_when_no_signal_fires() -> None:
    assert candidate_for(_detection_inputs()) is None


def test_candidate_for_reports_the_margin_decline_signal() -> None:
    candidate = candidate_for(_detection_inputs(buckets=_declining_buckets(Decimal("851.00"))))

    assert candidate is not None
    assert candidate.signal == SIGNAL_MARGIN_DECLINE
    assert candidate.project_id == PROJECT_ID
    assert candidate.margin_decline_points == Decimal("5.1")
    assert candidate.negative_margin_dollars is None
    assert candidate.quote_gap is None


def test_candidate_for_reports_the_quote_gap_signal() -> None:
    candidate = candidate_for(
        _detection_inputs(gap_inputs=_gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00"))
    )

    assert candidate is not None
    assert candidate.signal == SIGNAL_QUOTE_GAP
    assert candidate.band == SEVERITY_BAND_WARNING
    assert candidate.quote_gap is not None
    assert candidate.quote_gap.points == QUOTE_IMPLIED_GAP_POINTS


def test_candidate_for_drops_signal_figures_that_did_not_fire() -> None:
    """A 2-point drift is not a finding, so the AI never sees it as one."""
    candidate = candidate_for(
        _detection_inputs(
            buckets=_declining_buckets(Decimal("820.00")),
            gap_inputs=_gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00"),
        )
    )

    assert candidate is not None
    assert candidate.signal == SIGNAL_QUOTE_GAP
    assert candidate.margin_decline_points is None


def test_candidate_for_picks_the_most_severe_fact_when_all_three_fire() -> None:
    candidate = candidate_for(
        _detection_inputs(
            figures=_figures(revenue=Decimal("1000.00"), cost=Decimal("1350.00")),
            buckets=_declining_buckets(Decimal("900.00")),
            gap_inputs=_gap_inputs(billed="1000.00", quoted="2000.00", cost="100.00"),
        )
    )

    assert candidate is not None
    assert candidate.signal == PRIMARY_SIGNAL_ORDER[0] == SIGNAL_NEGATIVE_MARGIN
    assert candidate.band == SEVERITY_BAND_CRITICAL
    assert candidate.negative_margin_dollars == Decimal("-350.00")
    assert candidate.margin_decline_points is not None
    assert candidate.quote_gap is not None
