"""Pure quote-history math for the quotes domain (FINAI-04/FINAI-05).

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no
repositories, no session — pure functions only, matching the shipped
`margin_math` / `budget_math` / `profitability_math` precedent for expressing
math as functions rather than a service (CLAUDE.md forbids standalone
*service* functions; the finance package's math modules are the established
exception).

Variance is the algebraic negative of margin percent when revenue resolves to
the quoted leg: `margin_percent_for(quoted - actual, quoted)` negated. The
percent comes from `margin_percent_for` so the zero-revenue guard and the
one-decimal ROUND_HALF_UP convention have exactly one home — this module never
restates them.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.features.finance.margin_math import DocumentAmounts, margin_percent_for, pre_tax_total

# portfolio_math has a private copy of this value; this is the public one for
# the quotes feature.
ZERO_PERCENT = Decimal("0")

BAND_HIGH = "high"
BAND_MEDIUM = "medium"
BAND_LOW = "low"
BAND_ORDER = (BAND_HIGH, BAND_MEDIUM, BAND_LOW)  # best to worst

MIN_COMPARABLES_FOR_SUGGESTION = 3  # D-09 refusal floor
HIGH_CONFIDENCE_MIN_SAMPLES = 8
MEDIUM_CONFIDENCE_MIN_SAMPLES = 4
HIGH_CONFIDENCE_MAX_SPREAD_RATIO = Decimal("1.5")
MEDIUM_CONFIDENCE_MAX_SPREAD_RATIO = Decimal("3.0")
SPREAD_LOW_PERCENTILE = Decimal("0.10")
SPREAD_HIGH_PERCENTILE = Decimal("0.90")


@dataclass(frozen=True)
class VarianceFigures:
    """One quoted-vs-actual comparison. Positive variance means the work cost
    more than it was quoted for — the direction that hurts."""

    quoted: Decimal
    actual: Decimal
    variance: Decimal
    variance_percent: Decimal | None


def variance_for(quoted: Decimal, actual: Decimal) -> VarianceFigures:
    """The full variance block for one quoted-vs-actual comparison."""
    return VarianceFigures(
        quoted=quoted,
        actual=actual,
        variance=actual - quoted,
        variance_percent=variance_percent_for(quoted, actual),
    )


def variance_percent_for(quoted: Decimal, actual: Decimal) -> Decimal | None:
    """The negation of the shipped margin percent — never a second formula."""
    margin_percent = margin_percent_for(quoted - actual, quoted)
    if margin_percent is None or margin_percent == ZERO_PERCENT:
        return margin_percent
    return -margin_percent


def prorated_pre_tax_totals(
    subtotals: Sequence[Decimal], amounts: DocumentAmounts
) -> list[Decimal]:
    """Each group's share of one quote's pre-tax total, allocated by subtotal.

    A quote-level discount belongs to the whole document, so a group's quoted
    leg is its pro-rata share of the discounted total. The cent remainder goes
    to the largest group, which makes the returned list sum EXACTLY to
    pre_tax_total(amounts) — a per-trade table whose rows do not add up to the
    quote is worse than no table.
    """
    subtotal_total = sum(subtotals, Decimal("0"))
    if subtotal_total <= Decimal("0"):
        return [Decimal("0") for _ in subtotals]

    target = pre_tax_total(amounts)
    shares = [
        (target * subtotal / subtotal_total).quantize(Decimal("0.01")) for subtotal in subtotals
    ]
    remainder = target - sum(shares, Decimal("0"))
    if remainder != Decimal("0"):
        largest_index = max(range(len(subtotals)), key=lambda index: subtotals[index])
        shares[largest_index] += remainder
    return shares


def band_by_count(comparable_count: int) -> str:
    """Confidence verdict from the sample-count axis alone."""
    if comparable_count >= HIGH_CONFIDENCE_MIN_SAMPLES:
        return BAND_HIGH
    if comparable_count >= MEDIUM_CONFIDENCE_MIN_SAMPLES:
        return BAND_MEDIUM
    return BAND_LOW


def band_by_spread(spread_ratio: Decimal | None) -> str:
    """Confidence verdict from the agreement-spread axis alone.

    An unknowable ratio (fewer than two comparables, or a zero p10) reads as
    the weakest evidence, never as an all-clear.
    """
    if spread_ratio is None:
        return BAND_LOW
    if spread_ratio <= HIGH_CONFIDENCE_MAX_SPREAD_RATIO:
        return BAND_HIGH
    if spread_ratio <= MEDIUM_CONFIDENCE_MAX_SPREAD_RATIO:
        return BAND_MEDIUM
    return BAND_LOW


def confidence_band(comparable_count: int, spread_ratio: Decimal | None) -> str:
    """The WORSE of the two axis verdicts (D-05).

    Twenty comparables ranging three-to-one is not confidence, it is a wide
    market with a lot of observations — so the count axis can never overrule
    the agreement axis, and an unknowable spread reads as the weakest
    evidence.
    """
    return max(
        (band_by_count(comparable_count), band_by_spread(spread_ratio)),
        key=BAND_ORDER.index,
    )


def spread_ratio_for(values: Sequence[Decimal]) -> Decimal | None:
    """p90 / p10 by nearest rank. None when fewer than two values, or when p10
    is zero — a ratio against zero is not a wide spread, it is an unknown one.

    Nearest rank: sort ascending, index = ceil(percentile * n) - 1, clamped to
    [0, n - 1].
    """
    if len(values) < 2:
        return None
    ordered = sorted(values)
    p10 = ordered[_nearest_rank_index(SPREAD_LOW_PERCENTILE, len(ordered))]
    p90 = ordered[_nearest_rank_index(SPREAD_HIGH_PERCENTILE, len(ordered))]
    if p10 == Decimal("0"):
        return None
    return p90 / p10


def median_of(values: Sequence[Decimal]) -> Decimal | None:
    """The mean of the two middle values for an even count, None when empty."""
    if not values:
        return None
    ordered = sorted(values)
    midpoint = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[midpoint]
    return (ordered[midpoint - 1] + ordered[midpoint]) / Decimal("2")


def _nearest_rank_index(percentile: Decimal, count: int) -> int:
    index = math.ceil(percentile * count) - 1
    return min(max(index, 0), count - 1)
