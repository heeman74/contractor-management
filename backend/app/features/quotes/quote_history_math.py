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


# ---------------------------------------------------------------------------
# Comparable reduction (FINAI-03/D-13) — same-trade anchors and their approved-
# quote lines, already fetched by the caller, reduced to citable rates.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ComparableAnchor:
    """One completed, invoiced anchor of the matched trade — cost and labor
    already resolved by the caller (this module reduces them, never fetches
    them)."""

    is_job_anchored: bool
    actual_cost: Decimal
    quoted_pre_tax: Decimal | None
    labor_cost: Decimal


@dataclass(frozen=True)
class ComparableLine:
    """One approved-quote line item at a comparable anchor."""

    item_type: str
    unit: str
    description: str
    quantity: Decimal
    unit_price: Decimal


@dataclass(frozen=True)
class RateRow:
    """One rate the model is permitted to select. `typical_quantity` is a string
    by construction — a Decimal here would make the number citable as money."""

    item_type: str
    unit: str
    median_quoted_unit_price: Decimal
    typical_quantity: str
    sample_description: str


@dataclass(frozen=True)
class ComparableSummary:
    """Everything one trade's comparable set reduces to — the payload's entire
    numeric substance."""

    trade: str
    comparable_count: int
    confidence_band: str
    rate_rows: tuple[RateRow, ...]
    median_actual_total_per_comparable: Decimal | None
    median_actual_labor_cost: Decimal | None
    quoted_vs_actual_variance_percent: Decimal | None


def summarize_comparables(
    trade: str, anchors: Sequence[ComparableAnchor], lines: Sequence[ComparableLine]
) -> ComparableSummary:
    """Reduce one trade's comparable anchors and their quote lines to citable rates.

    D-13's pricing rule, stated here rather than merely inferred:
    `median_quoted_unit_price` comes from what the company CHARGED at comparable
    anchors, never from its actual unit cost. v4.0 labor cost is unburdened
    (wage only), so pricing a labor line from the cost rate would quote at or
    below true cost (PITFALLS #2). The actual-cost and variance figures ride
    along as separately named fields so the basis can STATE the correction
    rather than apply it — D-12's no-multiplier rule holds because nothing here
    multiplies anything.

    The confidence spread rides on the SAME population the rate rows' medians
    came from — every comparable line's unit price, pooled across groups —
    never an anchor-level figure and never an AI self-report.
    """
    comparable_count = len(anchors)
    rate_rows = _rate_rows(lines) if comparable_count >= MIN_COMPARABLES_FOR_SUGGESTION else ()
    spread_ratio = spread_ratio_for([line.unit_price for line in lines])
    return ComparableSummary(
        trade=trade,
        comparable_count=comparable_count,
        confidence_band=confidence_band(comparable_count, spread_ratio),
        rate_rows=rate_rows,
        median_actual_total_per_comparable=median_of([anchor.actual_cost for anchor in anchors]),
        median_actual_labor_cost=_median_job_anchored_labor(anchors),
        quoted_vs_actual_variance_percent=_quoted_vs_actual_variance_percent(anchors),
    )


def _median_job_anchored_labor(anchors: Sequence[ComparableAnchor]) -> Decimal | None:
    """The unburdened labor median, from job-anchored comparables only — a
    trade-scope anchor structurally carries no labor cost."""
    return median_of([anchor.labor_cost for anchor in anchors if anchor.is_job_anchored])


def _quoted_vs_actual_variance_percent(anchors: Sequence[ComparableAnchor]) -> Decimal | None:
    """Variance across every comparable with a known quoted leg, summed then
    compared — never averaged per-anchor, so one large job cannot be swamped by
    several small ones. Comparables with no quoted leg contribute to neither sum."""
    quoted_total = ZERO_PERCENT
    actual_total = ZERO_PERCENT
    for anchor in anchors:
        if anchor.quoted_pre_tax is None:
            continue
        quoted_total += anchor.quoted_pre_tax
        actual_total += anchor.actual_cost
    return variance_for(quoted_total, actual_total).variance_percent


def _rate_rows(lines: Sequence[ComparableLine]) -> tuple[RateRow, ...]:
    """One rate row per (item_type, unit) group present in the comparable lines —
    a group with no lines simply has no entry, never a zero."""
    groups: dict[tuple[str, str], list[ComparableLine]] = {}
    for line in lines:
        groups.setdefault((line.item_type, line.unit), []).append(line)
    return tuple(
        _rate_row_for(item_type, unit, group) for (item_type, unit), group in sorted(groups.items())
    )


def _rate_row_for(item_type: str, unit: str, group: Sequence[ComparableLine]) -> RateRow:
    """One group's rate row — group is always non-empty (see `_rate_rows`)."""
    return RateRow(
        item_type=item_type,
        unit=unit,
        median_quoted_unit_price=_median_nonempty([line.unit_price for line in group]),
        typical_quantity=str(_median_nonempty([line.quantity for line in group])),
        sample_description=_most_common_description(group),
    )


def _median_nonempty(values: Sequence[Decimal]) -> Decimal:
    """`median_of`, guaranteed non-None for the always-nonempty groups this
    module builds rows from."""
    median = median_of(values)
    assert median is not None
    return median


def _most_common_description(group: Sequence[ComparableLine]) -> str:
    """The description repeated most often in the group, ties broken by first
    appearance — a real line's own words, never a generated summary."""
    counts: dict[str, int] = {}
    for line in group:
        counts[line.description] = counts.get(line.description, 0) + 1
    best_count = max(counts.values())
    return next(line.description for line in group if counts[line.description] == best_count)
