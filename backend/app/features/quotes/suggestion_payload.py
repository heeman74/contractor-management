"""The CLOSED value set an AI quote suggestion may cite (FINAI-03/04, D-03).

Pure assembly: no DB, no Claude, no service — mirrors `profitability_payload`'s
shape for the quote-planning feature (Phase 37). The closure property is the
whole point: every Decimal this module hands the caller becomes citable through
`app.core.ai_grounding`, so a figure that is NOT a named field here is a figure
the model cannot use.

Two closed sets ride together: `AllowedFigures` for prose (money vs percent,
matched by sigil) and `AllowedLineValues` for the STRUCTURED unit_price/quantity
fields a suggested line carries, checked by exact Decimal membership rather than
text extraction. Counts, the confidence band, quantities and the trade name are
all emitted as STRINGS so the shipped flat collector skips them by
construction — the same escape hatch a prior AI feature relied on ("a project
named 2026 can never make $2,026 citable"), used deliberately here too, and the
fix for the percent-vs-money matching gap a prior phase's verifier flagged: this
module never puts a percent and a money figure in the same set.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Final

from app.core.ai_grounding import AllowedFigures
from app.features.quotes.quote_history_math import ComparableSummary, RateRow

LABOR_BASIS_UNBURDENED: Final = "unburdened"

_UNIT_PRICE_FIELD = "unit_price"
_QUANTITY_FIELD = "quantity"


@dataclass(frozen=True)
class AllowedLineValues:
    """The exact values a suggested line may carry in its STRUCTURED fields.

    Exact Decimal membership, never the whole-dollar loosening that money prose
    gets: a structured field is a number the model copied out of the payload,
    not a number it formatted for a sentence.
    """

    unit_prices: frozenset[Decimal]
    quantities: frozenset[Decimal]


@dataclass(frozen=True)
class SuggestionPayload:
    """The payload plus the two closed sets the caller validates a reply against."""

    payload: dict[str, object]
    allowed_figures: AllowedFigures
    allowed_lines: AllowedLineValues


def build_suggestion_payload(summary: ComparableSummary) -> SuggestionPayload:
    """The complete, CLOSED value set one trade's suggestion run may cite.

    Money set: every rate row's `median_quoted_unit_price`, plus
    `median_actual_total_per_comparable` and `median_actual_labor_cost`.
    Percent set: `quoted_vs_actual_variance_percent`. Neither set, and emitted
    as strings so nothing here becomes accidentally citable: `comparable_count`,
    `confidence_band`, every `typical_quantity`, and the trade name.
    """
    payload: dict[str, object] = {
        "trade": summary.trade,
        "comparable_count": str(summary.comparable_count),
        "confidence_band": summary.confidence_band,
        "labor_basis": LABOR_BASIS_UNBURDENED,
        "median_actual_total_per_comparable": summary.median_actual_total_per_comparable,
        "median_actual_labor_cost": summary.median_actual_labor_cost,
        "quoted_vs_actual_variance_percent": summary.quoted_vs_actual_variance_percent,
        "rate_rows": [_rate_row_payload(row) for row in summary.rate_rows],
    }
    money = _present_decimals(
        row.median_quoted_unit_price for row in summary.rate_rows
    ) | _present_decimals(
        (summary.median_actual_total_per_comparable, summary.median_actual_labor_cost)
    )
    percents = _present_decimals((summary.quoted_vs_actual_variance_percent,))
    allowed_lines = AllowedLineValues(
        unit_prices=frozenset(row.median_quoted_unit_price for row in summary.rate_rows),
        quantities=frozenset(Decimal(row.typical_quantity) for row in summary.rate_rows),
    )
    return SuggestionPayload(
        payload=payload,
        allowed_figures=AllowedFigures(money=money, percents=percents),
        allowed_lines=allowed_lines,
    )


def ungrounded_line_fields(
    line: Mapping[str, object], allowed: AllowedLineValues
) -> tuple[str, ...]:
    """Which of a suggested line's structured fields are absent from the closed set.

    A malformed or missing field coerces to None and is flagged rather than
    raising — a reply the model garbled is exactly what this guard exists to catch.
    """
    flagged: list[str] = []
    unit_price = _as_decimal(line.get(_UNIT_PRICE_FIELD))
    if unit_price is None or unit_price not in allowed.unit_prices:
        flagged.append(_UNIT_PRICE_FIELD)
    quantity = _as_decimal(line.get(_QUANTITY_FIELD))
    if quantity is None or quantity not in allowed.quantities:
        flagged.append(_QUANTITY_FIELD)
    return tuple(flagged)


def jsonb_payload(payload: Mapping[str, object]) -> dict:
    """The payload as JSONB-safe data, Decimals rendered as exact strings — the
    audit trail `quotes.ai_suggestion_payload` stores, re-readable verbatim."""
    return json.loads(json.dumps(payload, default=str))


def _rate_row_payload(row: RateRow) -> dict[str, object]:
    """One rate row as payload data — `typical_quantity` stays a string."""
    return {
        "item_type": row.item_type,
        "unit": row.unit,
        "median_quoted_unit_price": row.median_quoted_unit_price,
        "typical_quantity": row.typical_quantity,
        "sample_description": row.sample_description,
    }


def _present_decimals(values: Iterable[Decimal | None]) -> frozenset[Decimal]:
    """Every non-None Decimal in an iterable — an absent figure carries no
    citation right, not a fabricated zero."""
    return frozenset(value for value in values if value is not None)


def _as_decimal(value: object) -> Decimal | None:
    """A malformed or missing value coerces to None rather than raising."""
    if isinstance(value, bool):
        return None
    if isinstance(value, Decimal):
        return value
    if isinstance(value, int | float):
        return Decimal(str(value))
    if isinstance(value, str):
        try:
            return Decimal(value)
        except InvalidOperation:
            return None
    return None
