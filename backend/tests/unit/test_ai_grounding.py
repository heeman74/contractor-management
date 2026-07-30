"""Unit tests for the D-05 grounding validator and the strict Claude JSON call.

Pure unit tests — no DB, no network. Covers figure extraction, the closed
allowed-value set, the two representation tolerances the shipped formatters
make unavoidable, the fabricated-zero failure mode (Pitfall 9), and the
fail-closed parsing contract of call_claude_json_strict.
"""

from __future__ import annotations

import json
from decimal import Decimal
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.core.ai_grounding import (
    AllowedFigures,
    CitedFigure,
    collect_allowed_values,
    extract_figures,
    matches_allowed,
    validate_grounding,
    validate_typed_grounding,
)
from app.core.ai_utils import ClaudeJsonResponse, call_claude_json_strict


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


# ---------------------------------------------------------------------------
# validate_typed_grounding / matches_typed — the Phase 37 typed sibling (D-03)
# ---------------------------------------------------------------------------


class TestTypedGrounding:
    def test_percent_value_never_satisfies_a_dollar_citation(self) -> None:
        allowed = AllowedFigures(money=frozenset(), percents=_allowed("7"))

        result = validate_typed_grounding("The comparable count basis is $7.", allowed)

        assert result.ok is False
        assert result.unmatched == ("$7",)

    def test_money_value_never_satisfies_a_percent_citation(self) -> None:
        allowed = AllowedFigures(money=_allowed("7"), percents=frozenset())

        result = validate_typed_grounding("Margin moved 7%.", allowed)

        assert result.ok is False
        assert result.unmatched == ("7%",)

    def test_whole_dollar_loosening_survives_in_the_typed_form(self) -> None:
        allowed = AllowedFigures(money=_allowed("3200.41"), percents=frozenset())

        result = validate_typed_grounding("Materials ran $3,200 over the quote.", allowed)

        assert result.ok is True

    def test_whole_dollar_loosening_stays_one_directional_in_the_typed_form(self) -> None:
        allowed = AllowedFigures(money=_allowed("3200"), percents=frozenset())

        result = validate_typed_grounding("Materials ran $3,200.41 over the quote.", allowed)

        assert result.ok is False
        assert result.unmatched == ("$3,200.41",)

    def test_percent_matches_its_own_set_at_one_decimal(self) -> None:
        allowed = AllowedFigures(money=frozenset(), percents=_allowed("12.5"))

        result = validate_typed_grounding("Margin fell 12.5%.", allowed)

        assert result.ok is True

    def test_typed_grounding_ok_for_text_with_no_figures_at_all(self) -> None:
        allowed = AllowedFigures(money=frozenset(), percents=frozenset())

        result = validate_typed_grounding(
            "Plumbing needs a re-scope before drywall starts.", allowed
        )

        assert result.ok is True
        assert result.unmatched == ()

    def test_untyped_grounding_unchanged_by_typed_sibling(self) -> None:
        payload = {
            "over_quote_dollars": Decimal("3200.41"),
            "margin_decline_points": Decimal("6.2"),
        }

        result = validate_grounding(
            "Margin fell 6.2 points while plumbing ran $3,200 over the quote.",
            collect_allowed_values(payload),
        )

        assert result.ok is True


# ---------------------------------------------------------------------------
# call_claude_json_strict — the fail-closed sibling of call_claude_json
# ---------------------------------------------------------------------------

_FINDING_JSON = {"confirmed": True, "narrative": "Margin fell 6.2%."}
_ONE_TURN: tuple[dict[str, str], ...] = ({"role": "user", "content": "payload"},)


def _make_mock_anthropic_response(
    content: dict | str,
    *,
    usage: tuple[int, int] | None = None,
) -> MagicMock:
    """Build a mock Anthropic message response with content[0].text (Phase 26 helper)."""
    text = json.dumps(content) if isinstance(content, dict) else content

    mock_content = MagicMock()
    mock_content.text = text

    mock_response = MagicMock()
    mock_response.content = [mock_content]
    if usage is None:
        del mock_response.usage
    else:
        mock_response.usage.input_tokens, mock_response.usage.output_tokens = usage
    return mock_response


def _patched_claude(mock_response: MagicMock) -> tuple[object, AsyncMock]:
    """Patch the client factory and hand back the patcher plus the create AsyncMock."""
    patcher = patch("app.core.ai_utils.get_anthropic_client")
    mock_client = patcher.start()
    create = AsyncMock(return_value=mock_response)
    mock_client.return_value.messages.create = create
    return patcher, create


async def test_strict_call_returns_parsed_data_and_raw_text() -> None:
    patcher, _ = _patched_claude(_make_mock_anthropic_response(_FINDING_JSON))
    try:
        response = await call_claude_json_strict("system", _ONE_TURN)
    finally:
        patcher.stop()

    assert isinstance(response, ClaudeJsonResponse)
    assert response.data == _FINDING_JSON
    assert response.raw_text == json.dumps(_FINDING_JSON)


async def test_strict_call_parses_a_fenced_json_response() -> None:
    fenced = f"```json\n{json.dumps(_FINDING_JSON)}\n```"
    patcher, _ = _patched_claude(_make_mock_anthropic_response(fenced))
    try:
        response = await call_claude_json_strict("system", _ONE_TURN)
    finally:
        patcher.stop()

    assert response.data == _FINDING_JSON
    assert response.raw_text == json.dumps(_FINDING_JSON)


async def test_strict_call_raises_on_empty_content() -> None:
    empty = MagicMock()
    empty.content = []
    patcher, _ = _patched_claude(empty)
    try:
        with pytest.raises(ValueError, match="Empty response"):
            await call_claude_json_strict("system", _ONE_TURN)
    finally:
        patcher.stop()


async def test_strict_call_raises_on_unparseable_json() -> None:
    patcher, _ = _patched_claude(_make_mock_anthropic_response("I think the margin looks fine."))
    try:
        with pytest.raises(ValueError):  # noqa: PT011 — json.JSONDecodeError is a ValueError
            await call_claude_json_strict("system", _ONE_TURN)
    finally:
        patcher.stop()


async def test_strict_call_tolerates_a_response_without_usage() -> None:
    patcher, _ = _patched_claude(_make_mock_anthropic_response(_FINDING_JSON))
    try:
        response = await call_claude_json_strict("system", _ONE_TURN)
    finally:
        patcher.stop()

    assert response.input_tokens is None
    assert response.output_tokens is None


async def test_strict_call_reads_usage_tokens_when_present() -> None:
    patcher, _ = _patched_claude(_make_mock_anthropic_response(_FINDING_JSON, usage=(1200, 340)))
    try:
        response = await call_claude_json_strict("system", _ONE_TURN)
    finally:
        patcher.stop()

    assert response.input_tokens == 1200
    assert response.output_tokens == 340


async def test_strict_call_passes_a_multi_turn_message_list_through_unchanged() -> None:
    conversation = (
        {"role": "user", "content": "payload"},
        {"role": "assistant", "content": "first answer"},
        {"role": "user", "content": "these figures are ungrounded"},
    )
    patcher, create = _patched_claude(_make_mock_anthropic_response(_FINDING_JSON))
    try:
        await call_claude_json_strict("system", conversation)
    finally:
        patcher.stop()

    assert create.await_args.kwargs["messages"] == list(conversation)
    assert create.await_args.kwargs["system"] == "system"
