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

from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.features.finance.margin_math import DocumentAmounts, margin_percent_for, pre_tax_total

# portfolio_math has a private copy of this value; this is the public one for
# the quotes feature.
ZERO_PERCENT = Decimal("0")


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
