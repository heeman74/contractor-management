"""Unit tests for the D-05 grounding validator (app.core.ai_grounding).

Pure unit tests — no DB, no network. Covers figure extraction, the closed
allowed-value set, the two representation tolerances the shipped formatters
make unavoidable, and the fabricated-zero failure mode (Pitfall 9).
"""

from __future__ import annotations

from decimal import Decimal

from app.core.ai_grounding import (
    CitedFigure,
    collect_allowed_values,
    extract_figures,
    matches_allowed,
    validate_grounding,
)


def _allowed(*values: str) -> frozenset[Decimal]:
    return frozenset(Decimal(value) for value in values)


def _money(literal: str) -> CitedFigure:
    (figure,) = extract_figures(literal)
    assert not figure.is_percent
    return figure


def _percent(literal: str) -> CitedFigure:
    (figure,) = extract_figures(literal)
    assert figure.is_percent
    return figure


# ---------------------------------------------------------------------------
# collect_allowed_values — the closed set
# ---------------------------------------------------------------------------


def test_collect_allowed_values_walks_nested_mappings() -> None:
    payload = {
        "margin": {"percent": Decimal("6.2"), "dollars": Decimal("-350.00")},
        "budget": {"remaining": Decimal("1200.50")},
    }

    assert collect_allowed_values(payload) == _allowed("6.2", "-350.00", "1200.50")


def test_collect_allowed_values_walks_sequences_of_mappings() -> None:
    payload = {"categories": [{"amount": Decimal("100")}, {"amount": Decimal("250.25")}]}

    assert collect_allowed_values(payload) == _allowed("100", "250.25")


def test_collect_allowed_values_collects_ints() -> None:
    payload = {"cost_entry_count": 12}

    assert collect_allowed_values(payload) == _allowed("12")


def test_collect_allowed_values_skips_strings() -> None:
    payload = {"project_name": "2026", "trade_name": "Plumbing"}

    assert collect_allowed_values(payload) == frozenset()


def test_collect_allowed_values_excludes_bool() -> None:
    payload = {"confirmed": True, "incomplete": False}

    assert collect_allowed_values(payload) == frozenset()


def test_payload_string_year_does_not_make_a_dollar_figure_citable() -> None:
    allowed = collect_allowed_values({"project_name": "2026 Renovation"})

    result = validate_grounding("Costs rose by $2,026 this quarter.", allowed)

    assert result.ok is False
    assert result.unmatched == ("$2,026",)


# ---------------------------------------------------------------------------
# extract_figures
# ---------------------------------------------------------------------------


def test_extract_figures_finds_every_money_form() -> None:
    text = "Totals: $3,200 and $3,200.41 and $3200 and -$350.00."

    figures = extract_figures(text)

    assert [figure.literal for figure in figures] == [
        "$3,200",
        "$3,200.41",
        "$3200",
        "-$350.00",
    ]
    assert [figure.value for figure in figures] == [
        Decimal("3200"),
        Decimal("3200.41"),
        Decimal("3200"),
        Decimal("-350.00"),
    ]
    assert all(not figure.is_percent for figure in figures)


def test_extract_figures_finds_every_percent_form() -> None:
    figures = extract_figures("Margin moved 6.2% then -4% then 6%.")

    assert [figure.literal for figure in figures] == ["6.2%", "-4%", "6%"]
    assert [figure.value for figure in figures] == [
        Decimal("6.2"),
        Decimal("-4"),
        Decimal("6"),
    ]
    assert all(figure.is_percent for figure in figures)


def test_extract_figures_returns_source_order_across_both_patterns() -> None:
    figures = extract_figures("Margin fell 6.2% while costs rose $3,200 against 4% planned.")

    assert [figure.literal for figure in figures] == ["6.2%", "$3,200", "4%"]


def test_extract_figures_finds_nothing_in_sigil_free_prose() -> None:
    assert extract_figures("Plumbing is running behind the approved scope.") == ()


# ---------------------------------------------------------------------------
# matches_allowed — money
# ---------------------------------------------------------------------------


def test_money_matches_payload_value_to_the_cent() -> None:
    assert matches_allowed(_money("$3,200.41"), _allowed("3200.41")) is True


def test_money_matches_payload_value_rounded_down_to_the_whole_dollar() -> None:
    assert matches_allowed(_money("$3,200"), _allowed("3200.41")) is True


def test_money_matches_payload_value_rounded_up_to_the_whole_dollar() -> None:
    assert matches_allowed(_money("$3,201"), _allowed("3200.51")) is True


def test_money_on_the_wrong_side_of_the_rounding_boundary_is_unmatched() -> None:
    assert matches_allowed(_money("$3,200"), _allowed("3200.51")) is False


def test_money_matches_the_stripped_trailing_cents_the_alert_formatter_emits() -> None:
    assert matches_allowed(_money("$10,000"), _allowed("10000.00")) is True


def test_negative_money_matches_a_negative_payload_value() -> None:
    assert matches_allowed(_money("-$350.00"), _allowed("-350.00")) is True


def test_money_absent_from_the_payload_is_unmatched() -> None:
    assert matches_allowed(_money("$4,100"), _allowed("3200.41")) is False


# ---------------------------------------------------------------------------
# matches_allowed — percent
# ---------------------------------------------------------------------------


def test_percent_matches_a_payload_value_at_one_decimal_place() -> None:
    assert matches_allowed(_percent("6.2%"), _allowed("6.2")) is True


def test_whole_percent_matches_the_stripped_trailing_zero_the_formatter_emits() -> None:
    assert matches_allowed(_percent("6%"), _allowed("6.0")) is True


def test_percent_off_by_a_tenth_is_unmatched() -> None:
    assert matches_allowed(_percent("6.3%"), _allowed("6.2")) is False


def test_a_percent_never_matches_a_money_value_of_the_same_magnitude() -> None:
    result = validate_grounding("Margin fell 6.2%.", collect_allowed_values({"gap": Decimal("9")}))

    assert result.unmatched == ("6.2%",)


# ---------------------------------------------------------------------------
# The fabricated zero (Pitfall 9)
# ---------------------------------------------------------------------------


def test_fabricated_zero_dollars_is_unmatched() -> None:
    assert matches_allowed(_money("$0"), _allowed("3200.41")) is False


def test_zero_dollars_is_matched_when_the_payload_carries_a_real_zero() -> None:
    assert matches_allowed(_money("$0"), _allowed("3200.41", "0.00")) is True


# ---------------------------------------------------------------------------
# validate_grounding
# ---------------------------------------------------------------------------


def test_validate_grounding_ok_when_every_figure_matches() -> None:
    payload = {"over_quote_dollars": Decimal("3200.41"), "margin_decline_points": Decimal("6.2")}

    result = validate_grounding(
        "Margin fell 6.2 points while plumbing ran $3,200 over the quote.",
        collect_allowed_values(payload),
    )

    assert result.ok is True
    assert result.unmatched == ()


def test_validate_grounding_reports_every_unmatched_literal_verbatim() -> None:
    payload = {"over_quote_dollars": Decimal("3200.41")}

    result = validate_grounding(
        "Margin fell 9.9% and materials ran $4,100 over the quote, on top of $3,200.41 in labor.",
        collect_allowed_values(payload),
    )

    assert result.ok is False
    assert result.unmatched == ("9.9%", "$4,100")


def test_validate_grounding_ok_for_text_with_no_figures_at_all() -> None:
    result = validate_grounding("Plumbing needs a re-scope before drywall starts.", frozenset())

    assert result.ok is True
    assert result.unmatched == ()
