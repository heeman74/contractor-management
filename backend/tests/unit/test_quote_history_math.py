"""Unit tests for the DB-free quote-history math module (FINAI-04/FINAI-05).

Pure unit tests — no DB, no network. Covers quoted-vs-actual variance
(derived from the shipped margin_percent_for, never a second formula) and
per-group pre-tax proration.
"""

from __future__ import annotations

from decimal import Decimal

from app.features.finance.margin_math import DocumentAmounts, margin_percent_for, pre_tax_total
from app.features.quotes.quote_history_math import (
    BAND_HIGH,
    BAND_LOW,
    BAND_MEDIUM,
    MIN_COMPARABLES_FOR_SUGGESTION,
    ComparableAnchor,
    ComparableLine,
    band_by_count,
    band_by_spread,
    confidence_band,
    median_of,
    prorated_pre_tax_totals,
    spread_ratio_for,
    summarize_comparables,
    variance_for,
    variance_percent_for,
)

# ---------------------------------------------------------------------------
# variance_for / variance_percent_for
# ---------------------------------------------------------------------------


def test_variance_under_quoted() -> None:
    figures = variance_for(Decimal("10000"), Decimal("11200"))

    assert figures.variance == Decimal("1200")
    assert figures.variance_percent == Decimal("12.0")


def test_variance_over_quoted() -> None:
    figures = variance_for(Decimal("10000"), Decimal("9000"))

    assert figures.variance == Decimal("-1000")
    assert figures.variance_percent == Decimal("-10.0")


def test_variance_exactly_even_has_no_negative_zero() -> None:
    figures = variance_for(Decimal("10000"), Decimal("10000"))

    assert figures.variance == Decimal("0")
    assert figures.variance_percent == Decimal("0.0")
    assert str(figures.variance_percent) == "0.0"


def test_variance_percent_none_at_zero_quoted() -> None:
    figures = variance_for(Decimal("0"), Decimal("500"))

    assert figures.variance == Decimal("500")
    assert figures.variance_percent is None


def test_variance_percent_is_negated_margin_percent() -> None:
    cases = [
        (Decimal("10000"), Decimal("11200")),
        (Decimal("10000"), Decimal("9000")),
        (Decimal("10000"), Decimal("10000")),
    ]

    for quoted, actual in cases:
        expected_margin_percent = margin_percent_for(quoted - actual, quoted)
        computed = variance_percent_for(quoted, actual)
        if expected_margin_percent == Decimal("0"):
            assert computed == expected_margin_percent
        else:
            assert computed == -expected_margin_percent


def test_variance_percent_none_at_zero_quoted_matches_margin_percent_for() -> None:
    assert variance_percent_for(Decimal("0"), Decimal("500")) is None
    assert margin_percent_for(Decimal("0") - Decimal("500"), Decimal("0")) is None


# ---------------------------------------------------------------------------
# prorated_pre_tax_totals
# ---------------------------------------------------------------------------


def _amounts(subtotal: Decimal) -> DocumentAmounts:
    return DocumentAmounts(
        subtotal=subtotal,
        discount_type="percent",
        discount_value=Decimal("10"),
        tax_rate=Decimal("8"),
    )


def test_prorated_totals_sum_to_pre_tax_total() -> None:
    amounts = _amounts(Decimal("1000.00"))
    subtotals = [Decimal("300.00"), Decimal("400.00"), Decimal("300.00")]

    shares = prorated_pre_tax_totals(subtotals, amounts)

    assert sum(shares, Decimal("0")) == pre_tax_total(amounts)


def test_prorated_totals_remainder_goes_to_largest_group() -> None:
    amounts = _amounts(Decimal("100.00"))
    subtotals = [Decimal("33.33"), Decimal("33.33"), Decimal("33.34")]

    shares = prorated_pre_tax_totals(subtotals, amounts)

    target = pre_tax_total(amounts)
    subtotal_total = sum(subtotals, Decimal("0"))
    naive_shares = [
        (target * subtotal / subtotal_total).quantize(Decimal("0.01")) for subtotal in subtotals
    ]
    assert sum(naive_shares, Decimal("0")) != target, (
        "fixture must exercise a real rounding remainder"
    )

    largest_index = subtotals.index(max(subtotals))
    assert shares[largest_index] != naive_shares[largest_index]
    assert sum(shares, Decimal("0")) == target


def test_prorated_totals_zero_subtotal_input_returns_all_zeros() -> None:
    amounts = _amounts(Decimal("500.00"))

    shares = prorated_pre_tax_totals([Decimal("0"), Decimal("0")], amounts)

    assert shares == [Decimal("0"), Decimal("0")]


# ---------------------------------------------------------------------------
# band_by_count / band_by_spread — the two independent confidence axes
# ---------------------------------------------------------------------------


def test_band_by_count_axis_alone() -> None:
    assert band_by_count(9) == BAND_HIGH
    assert band_by_count(5) == BAND_MEDIUM
    assert band_by_count(3) == BAND_LOW


def test_band_by_count_boundaries() -> None:
    assert band_by_count(8) == BAND_HIGH
    assert band_by_count(7) == BAND_MEDIUM
    assert band_by_count(4) == BAND_MEDIUM
    assert band_by_count(3) == BAND_LOW


def test_band_by_spread_axis_alone() -> None:
    assert band_by_spread(Decimal("1.2")) == BAND_HIGH
    assert band_by_spread(Decimal("2.0")) == BAND_MEDIUM
    assert band_by_spread(Decimal("5.0")) == BAND_LOW


def test_band_by_spread_boundaries() -> None:
    assert band_by_spread(Decimal("1.5")) == BAND_HIGH
    assert band_by_spread(Decimal("1.51")) == BAND_MEDIUM
    assert band_by_spread(Decimal("3.0")) == BAND_MEDIUM
    assert band_by_spread(Decimal("3.01")) == BAND_LOW


def test_band_by_spread_unknown_is_low() -> None:
    assert band_by_spread(None) == BAND_LOW


def test_confidence_band_takes_the_worse_axis() -> None:
    assert confidence_band(9, Decimal("1.2")) == BAND_HIGH
    assert confidence_band(9, Decimal("2.0")) == BAND_MEDIUM
    assert confidence_band(9, Decimal("5.0")) == BAND_LOW
    assert confidence_band(5, Decimal("1.0")) == BAND_MEDIUM
    assert confidence_band(3, Decimal("1.0")) == BAND_LOW


def test_confidence_band_twenty_samples_at_three_times_spread_is_not_high() -> None:
    assert confidence_band(20, Decimal("3.0")) == BAND_MEDIUM
    assert confidence_band(20, Decimal("3.01")) == BAND_LOW


def test_confidence_band_unknown_spread_is_low_even_at_high_count() -> None:
    assert confidence_band(20, None) == BAND_LOW


# ---------------------------------------------------------------------------
# spread_ratio_for / median_of
# ---------------------------------------------------------------------------


def test_spread_ratio_for_nearest_rank() -> None:
    values = [Decimal(str(value)) for value in range(1, 11)]  # 1..10

    ratio = spread_ratio_for(values)

    assert ratio == Decimal("9")  # p90 = 9, p10 = 1 by nearest rank


def test_spread_ratio_none_cases() -> None:
    assert spread_ratio_for([Decimal("5")]) is None
    assert spread_ratio_for([]) is None
    assert spread_ratio_for([Decimal("0"), Decimal("5")]) is None


def test_median_of_even_and_empty() -> None:
    assert median_of([Decimal("1"), Decimal("2"), Decimal("3"), Decimal("4")]) == Decimal("2.5")
    assert median_of([]) is None
    assert median_of([Decimal("5")]) == Decimal("5")


# ---------------------------------------------------------------------------
# summarize_comparables — the pure reduction from fetched rows to citable rates
# ---------------------------------------------------------------------------


def _anchor(
    *,
    actual_cost: Decimal,
    is_job_anchored: bool = True,
    quoted_pre_tax: Decimal | None = None,
    labor_cost: Decimal = Decimal("0"),
) -> ComparableAnchor:
    return ComparableAnchor(
        is_job_anchored=is_job_anchored,
        actual_cost=actual_cost,
        quoted_pre_tax=quoted_pre_tax,
        labor_cost=labor_cost,
    )


def _line(
    *,
    item_type: str = "labor",
    unit: str = "hr",
    description: str = "Rough-in",
    quantity: str,
    unit_price: str,
) -> ComparableLine:
    return ComparableLine(
        item_type=item_type,
        unit=unit,
        description=description,
        quantity=Decimal(quantity),
        unit_price=Decimal(unit_price),
    )


def test_summarize_comparables_rate_row_per_item_type_unit_group() -> None:
    anchors = [_anchor(actual_cost=Decimal("500.00")) for _ in range(3)]
    lines = [
        _line(quantity="4", unit_price="70.00"),
        _line(quantity="6", unit_price="80.00"),
        _line(
            item_type="material",
            unit="each",
            description="Fitting",
            quantity="10",
            unit_price="5.00",
        ),
    ]

    summary = summarize_comparables("plumbing", anchors, lines)

    by_group = {(row.item_type, row.unit): row for row in summary.rate_rows}
    assert by_group[("labor", "hr")].median_quoted_unit_price == Decimal("75.00")
    assert by_group[("material", "each")].median_quoted_unit_price == Decimal("5.00")


def test_summarize_comparables_group_with_no_lines_yields_no_row() -> None:
    anchors = [_anchor(actual_cost=Decimal("500.00")) for _ in range(3)]
    lines = [_line(quantity="4", unit_price="70.00")]

    summary = summarize_comparables("plumbing", anchors, lines)

    groups = {(row.item_type, row.unit) for row in summary.rate_rows}
    assert groups == {("labor", "hr")}
    assert ("material", "each") not in groups


def test_summarize_comparables_median_actual_total_per_comparable() -> None:
    anchors = [
        _anchor(actual_cost=cost) for cost in (Decimal("100"), Decimal("300"), Decimal("500"))
    ]

    summary = summarize_comparables("plumbing", anchors, [])

    assert summary.median_actual_total_per_comparable == Decimal("300")


def test_summarize_comparables_labor_only_from_job_anchors() -> None:
    job_anchor = _anchor(
        actual_cost=Decimal("500"), is_job_anchored=True, labor_cost=Decimal("200")
    )
    scope_anchor = _anchor(
        actual_cost=Decimal("400"), is_job_anchored=False, labor_cost=Decimal("0")
    )

    summary = summarize_comparables("plumbing", [job_anchor, scope_anchor, job_anchor], [])

    assert summary.median_actual_labor_cost == Decimal("200")


def test_summarize_comparables_all_scope_anchored_has_no_labor_rate() -> None:
    scope_anchors = [_anchor(actual_cost=Decimal("400"), is_job_anchored=False) for _ in range(3)]

    summary = summarize_comparables("plumbing", scope_anchors, [])

    assert summary.median_actual_labor_cost is None


def test_summarize_comparables_variance_from_summed_quoted_and_actual() -> None:
    anchors = [
        _anchor(actual_cost=Decimal("1100"), quoted_pre_tax=Decimal("1000")),
        _anchor(actual_cost=Decimal("2200"), quoted_pre_tax=Decimal("2000")),
        _anchor(actual_cost=Decimal("500"), quoted_pre_tax=None),  # no quoted leg — excluded
    ]

    summary = summarize_comparables("plumbing", anchors, [])

    expected = variance_for(Decimal("3000"), Decimal("3300")).variance_percent
    assert summary.quoted_vs_actual_variance_percent == expected == Decimal("10.0")


def test_summarize_comparables_confidence_band_uses_line_price_spread() -> None:
    anchors = [_anchor(actual_cost=Decimal("500")) for _ in range(9)]  # count axis alone: HIGH
    tight_lines = [_line(quantity="1", unit_price="100") for _ in range(10)]

    tight_summary = summarize_comparables("plumbing", anchors, tight_lines)
    assert tight_summary.confidence_band == BAND_HIGH

    wide_lines = [
        _line(quantity="1", unit_price=str(price))
        for price in (10, 20, 30, 40, 50, 60, 70, 80, 90, 1000)
    ]
    wide_summary = summarize_comparables("plumbing", anchors, wide_lines)
    assert wide_summary.confidence_band == BAND_LOW


def test_summarize_comparables_below_threshold_has_no_rate_rows() -> None:
    assert MIN_COMPARABLES_FOR_SUGGESTION == 3
    anchors = [_anchor(actual_cost=Decimal("500")) for _ in range(2)]
    lines = [_line(quantity="1", unit_price="100")]

    summary = summarize_comparables("plumbing", anchors, lines)

    assert summary.rate_rows == ()
    assert summary.comparable_count == 2
