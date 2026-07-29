"""Pure revenue-resolution and margin math for the finance domain (MARG-01/MARG-03).

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no repositories.
It is the single home for the document discount/tax math shared with the invoice
and quote response schemas, and for the margin rules of Phase 33:

- Revenue is pre-tax — subtotal minus discount — on both the invoice and the
  approved-quote leg (D-13).
- Invoices win outright: once any invoice exists for an anchor, the approved
  quote is ignored entirely — never summed, never max()ed (D-01).
- Incomplete data yields a partial number plus a flag, never a suppressed or
  silently fabricated figure (D-06).
- An absent revenue source is not a data-quality flag; the margin is simply
  absent (D-07).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from app.features.finance.labor_derivation import CENTS, ZERO_MONEY

REVENUE_BASIS_INVOICED = "invoiced"
REVENUE_BASIS_QUOTED = "quoted"
REVENUE_BASIS_MIXED = "mixed"
REVENUE_BASIS_NONE = "none"
INCOMPLETE_UNRATED_LABOR = "unrated_labor"
INCOMPLETE_NO_COST_DATA = "no_cost_data"
DISCOUNT_TYPE_PERCENT = "percent"
DISCOUNT_TYPE_FIXED = "fixed"
PERCENT_MULTIPLIER = Decimal("100")
PERCENT_PLACES = Decimal("0.1")


@dataclass(frozen=True)
class RevenueAnchor:
    """The (job XOR trade scope) a revenue document hangs off. Hashable — used as a dict key."""

    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None


@dataclass(frozen=True)
class DocumentAmounts:
    """The money fields of one invoice or quote: line-item subtotal plus its discount/tax terms."""

    subtotal: Decimal
    discount_type: str | None
    discount_value: Decimal
    tax_rate: Decimal


@dataclass(frozen=True)
class AnchorRevenue:
    """The candidate revenue totals gathered for one anchor before resolution."""

    invoiced_total: Decimal | None = None
    quoted_total: Decimal | None = None


@dataclass(frozen=True)
class ResolvedRevenue:
    """The single revenue figure an anchor resolves to, with its basis."""

    total: Decimal | None
    basis: str


@dataclass(frozen=True)
class MarginInputs:
    """Everything summarize_margin needs: resolved revenue, cost, and data-quality signals."""

    revenue: ResolvedRevenue
    cost: Decimal
    unrated_seconds: int = 0
    has_missing_cost_data: bool = False


@dataclass(frozen=True)
class MarginFigures:
    """The wire-ready margin block: figures plus honesty flags."""

    revenue: Decimal | None
    revenue_basis: str
    margin: Decimal | None
    margin_percent: Decimal | None
    incomplete: bool
    incomplete_reasons: tuple[str, ...]


def discount_for(amounts: DocumentAmounts) -> Decimal:
    """Discount amount for one document — bit-for-bit the shipped schema math."""
    if amounts.discount_type == DISCOUNT_TYPE_PERCENT:
        return (amounts.subtotal * amounts.discount_value / PERCENT_MULTIPLIER).quantize(CENTS)
    if amounts.discount_type == DISCOUNT_TYPE_FIXED:
        return min(amounts.discount_value, amounts.subtotal)
    return ZERO_MONEY


def pre_tax_total(amounts: DocumentAmounts) -> Decimal:
    """Subtotal minus discount — the D-13 revenue leg of one document."""
    return amounts.subtotal - discount_for(amounts)


def tax_for(amounts: DocumentAmounts) -> Decimal:
    """Tax computed on the discounted subtotal."""
    return (pre_tax_total(amounts) * amounts.tax_rate / PERCENT_MULTIPLIER).quantize(CENTS)


def document_total(amounts: DocumentAmounts) -> Decimal:
    """Discounted subtotal plus tax — the display total of one document."""
    return pre_tax_total(amounts) + tax_for(amounts)


def revenue_from(documents: Iterable[DocumentAmounts]) -> Decimal:
    """Pre-tax revenue summed across documents, quantized to cents."""
    total = sum((pre_tax_total(document) for document in documents), ZERO_MONEY)
    return total.quantize(CENTS)


def resolve_anchor_revenue(anchor: AnchorRevenue) -> ResolvedRevenue:
    """One anchor's revenue: invoices win outright, else the approved quote, else nothing."""
    if anchor.invoiced_total is not None:
        return ResolvedRevenue(total=anchor.invoiced_total, basis=REVENUE_BASIS_INVOICED)
    if anchor.quoted_total is not None:
        return ResolvedRevenue(total=anchor.quoted_total, basis=REVENUE_BASIS_QUOTED)
    return ResolvedRevenue(total=None, basis=REVENUE_BASIS_NONE)


def combine_revenue_bases(bases: Iterable[str]) -> str:
    """Rollup basis across anchors: none entries drop out, differing real bases mix."""
    distinct = {basis for basis in bases if basis != REVENUE_BASIS_NONE}
    if not distinct:
        return REVENUE_BASIS_NONE
    if len(distinct) == 1:
        return next(iter(distinct))
    return REVENUE_BASIS_MIXED


def missing_cost_data(cost: Decimal, revenue: Decimal | None) -> bool:
    """Pitfall-9 signal: revenue exists but no cost at all was recorded."""
    return revenue is not None and revenue > ZERO_MONEY and cost <= ZERO_MONEY


def margin_percent_for(margin: Decimal, revenue: Decimal) -> Decimal | None:
    """Margin as a percentage of revenue, one decimal place, or None at zero revenue."""
    if revenue <= ZERO_MONEY:
        return None
    return (margin / revenue * PERCENT_MULTIPLIER).quantize(PERCENT_PLACES, rounding=ROUND_HALF_UP)


def _incomplete_reasons(inputs: MarginInputs) -> tuple[str, ...]:
    """Data-quality reasons in their fixed wire order."""
    reasons: list[str] = []
    if inputs.unrated_seconds > 0:
        reasons.append(INCOMPLETE_UNRATED_LABOR)
    if inputs.has_missing_cost_data:
        reasons.append(INCOMPLETE_NO_COST_DATA)
    return tuple(reasons)


def summarize_margin(inputs: MarginInputs) -> MarginFigures:
    """The full margin block for one anchor or rollup, honesty flags included."""
    revenue = inputs.revenue.total
    if revenue is None:
        return MarginFigures(
            revenue=None,
            revenue_basis=REVENUE_BASIS_NONE,
            margin=None,
            margin_percent=None,
            incomplete=False,
            incomplete_reasons=(),
        )
    margin = (revenue - inputs.cost).quantize(CENTS)
    reasons = _incomplete_reasons(inputs)
    return MarginFigures(
        revenue=revenue,
        revenue_basis=inputs.revenue.basis,
        margin=margin,
        margin_percent=margin_percent_for(margin, revenue),
        incomplete=bool(reasons),
        incomplete_reasons=reasons,
    )


def quoted_revenue(quote: DocumentAmounts) -> Decimal:
    """One quote's pre-tax revenue leg, quantized to cents like the invoice leg."""
    return pre_tax_total(quote).quantize(CENTS)


def anchor_revenues(
    invoice_rows: Sequence[tuple[RevenueAnchor, DocumentAmounts]],
    quote_rows: Sequence[tuple[RevenueAnchor, DocumentAmounts]],
) -> dict[RevenueAnchor, ResolvedRevenue]:
    """Per-anchor D-01 resolution: sum this anchor's invoices, else its FIRST quote row
    (the query returns newest-first), then resolve_anchor_revenue. A quote at an anchor
    that has invoices is discarded — never mixed, never max()ed (Pitfall 2).

    It lives here rather than in the service so the Phase 35 trend can replay the same
    resolution at a past date instead of carrying a second implementation.
    """
    invoices_by_anchor: dict[RevenueAnchor, list[DocumentAmounts]] = {}
    for anchor, amounts in invoice_rows:
        invoices_by_anchor.setdefault(anchor, []).append(amounts)
    resolved = {
        anchor: resolve_anchor_revenue(AnchorRevenue(invoiced_total=revenue_from(documents)))
        for anchor, documents in invoices_by_anchor.items()
    }
    for anchor, quote in quote_rows:
        if anchor not in resolved:
            resolved[anchor] = resolve_anchor_revenue(
                AnchorRevenue(quoted_total=quoted_revenue(quote))
            )
    return resolved


def combined_anchor_revenue(
    resolved_anchors: dict[RevenueAnchor, ResolvedRevenue],
) -> ResolvedRevenue | None:
    """Project revenue summed across resolved anchors, or None when no anchor resolved any."""
    totals = [revenue.total for revenue in resolved_anchors.values() if revenue.total is not None]
    if not totals:
        return None
    return ResolvedRevenue(
        total=sum(totals, ZERO_MONEY).quantize(CENTS),
        basis=combine_revenue_bases(revenue.basis for revenue in resolved_anchors.values()),
    )
