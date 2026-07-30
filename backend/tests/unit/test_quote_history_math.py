"""Unit tests for the DB-free quote-history math module (FINAI-04/FINAI-05).

Pure unit tests — no DB, no network. Covers quoted-vs-actual variance
(derived from the shipped margin_percent_for, never a second formula) and
per-group pre-tax proration.
"""

from __future__ import annotations

from decimal import Decimal

from app.features.finance.margin_math import DocumentAmounts, margin_percent_for, pre_tax_total
from app.features.quotes.quote_history_math import (
    prorated_pre_tax_totals,
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
