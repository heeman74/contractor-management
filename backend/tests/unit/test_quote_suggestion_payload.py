"""Unit tests for the CLOSED quote-suggestion payload (FINAI-03/04, D-03).

Pure unit tests — no DB, no network. Two of these are the phase's closed-set
proof, asserted directly against the shipped flat collector: a comparable count
and a typical quantity must never become citable numbers.
"""

from __future__ import annotations

from decimal import Decimal

from app.core.ai_grounding import collect_allowed_values
from app.features.quotes.quote_history_math import ComparableSummary, RateRow
from app.features.quotes.suggestion_payload import (
    AllowedLineValues,
    build_suggestion_payload,
    ungrounded_line_fields,
)


def _rate_row(
    *,
    item_type: str = "labor",
    unit: str = "hr",
    median_quoted_unit_price: str = "75.00",
    typical_quantity: str = "4.500",
    sample_description: str = "Rough-in plumbing",
) -> RateRow:
    return RateRow(
        item_type=item_type,
        unit=unit,
        median_quoted_unit_price=Decimal(median_quoted_unit_price),
        typical_quantity=typical_quantity,
        sample_description=sample_description,
    )


def _summary(**overrides: object) -> ComparableSummary:
    defaults: dict[str, object] = {
        "trade": "plumbing",
        "comparable_count": 5,
        "confidence_band": "medium",
        "rate_rows": (
            _rate_row(),
            _rate_row(
                item_type="material",
                unit="each",
                median_quoted_unit_price="12.50",
                typical_quantity="10.000",
                sample_description="PVC fittings",
            ),
        ),
        "median_actual_total_per_comparable": Decimal("1450.00"),
        "median_actual_labor_cost": Decimal("320.00"),
        "quoted_vs_actual_variance_percent": Decimal("-8.5"),
    }
    defaults.update(overrides)
    return ComparableSummary(**defaults)  # type: ignore[arg-type]


def test_collect_allowed_values_includes_every_money_figure() -> None:
    built = build_suggestion_payload(_summary())

    allowed = collect_allowed_values(built.payload)

    assert Decimal("75.00") in allowed
    assert Decimal("12.50") in allowed
    assert Decimal("1450.00") in allowed
    assert Decimal("320.00") in allowed


def test_collect_allowed_values_excludes_count_band_and_quantities() -> None:
    built = build_suggestion_payload(_summary(comparable_count=5))

    allowed = collect_allowed_values(built.payload)

    assert Decimal("5") not in allowed
    assert Decimal("4.500") not in allowed
    assert Decimal("10.000") not in allowed


def test_allowed_figures_money_and_percent_sets_are_disjoint_and_exact() -> None:
    built = build_suggestion_payload(_summary())

    assert built.allowed_figures.money == frozenset(
        [Decimal("75.00"), Decimal("12.50"), Decimal("1450.00"), Decimal("320.00")]
    )
    assert built.allowed_figures.percents == frozenset([Decimal("-8.5")])
    assert not (built.allowed_figures.money & built.allowed_figures.percents)


def test_allowed_figures_money_excludes_none_labor_cost() -> None:
    built = build_suggestion_payload(_summary(median_actual_labor_cost=None))

    assert None not in built.allowed_figures.money
    assert Decimal("1450.00") in built.allowed_figures.money


def test_allowed_line_values_holds_every_rate_row() -> None:
    built = build_suggestion_payload(_summary())

    assert built.allowed_lines.unit_prices == frozenset([Decimal("75.00"), Decimal("12.50")])
    assert built.allowed_lines.quantities == frozenset([Decimal("4.500"), Decimal("10.000")])


_ALLOWED_LINES = AllowedLineValues(
    unit_prices=frozenset([Decimal("75.00")]), quantities=frozenset([Decimal("4.500")])
)


def test_ungrounded_line_fields_flags_unknown_unit_price() -> None:
    flagged = ungrounded_line_fields({"unit_price": "99.00", "quantity": "4.500"}, _ALLOWED_LINES)

    assert flagged == ("unit_price",)


def test_ungrounded_line_fields_flags_unknown_quantity() -> None:
    flagged = ungrounded_line_fields({"unit_price": "75.00", "quantity": "9.000"}, _ALLOWED_LINES)

    assert flagged == ("quantity",)


def test_ungrounded_line_fields_empty_for_allowed_copy() -> None:
    flagged = ungrounded_line_fields({"unit_price": "75.00", "quantity": "4.500"}, _ALLOWED_LINES)

    assert flagged == ()


def test_ungrounded_line_fields_exact_cents_no_whole_dollar_loosening() -> None:
    flagged = ungrounded_line_fields({"unit_price": "75.01", "quantity": "4.500"}, _ALLOWED_LINES)

    assert flagged == ("unit_price",)


def test_ungrounded_line_fields_flags_missing_fields() -> None:
    flagged = ungrounded_line_fields({}, _ALLOWED_LINES)

    assert flagged == ("unit_price", "quantity")


def test_ungrounded_line_fields_flags_non_numeric_values() -> None:
    flagged = ungrounded_line_fields(
        {"unit_price": "not-a-number", "quantity": "4.500"}, _ALLOWED_LINES
    )

    assert flagged == ("unit_price",)
