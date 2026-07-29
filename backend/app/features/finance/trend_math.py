"""Pure monthly-trend math for the finance domain (MARG-04).

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no repositories.
It adds no arithmetic of its own — every figure it emits comes from the shipped
`margin_math` / `labor_derivation` functions, replayed at a past cut-off date.
What is genuinely new here is only WHICH records a month contains.

D-02 bucket semantics:

| Rule | Value |
|---|---|
| Bucket key | "YYYY-MM" (UTC) |
| Bucket edge | that month's last calendar day, INCLUSIVE |
| Cost entry lands in | every bucket whose edge >= incurred_date |
| Work session lands in | every bucket whose edge >= work_date_for(clocked_in_at) |
| Invoice revenue lands in | every bucket whose edge >= the UTC date of issued_at |
| Approved-quote revenue lands in | every bucket whose edge >= the UTC date of approved_at, |
|  | falling back to created_at when approved_at is NULL |
| Revenue per bucket | RESOLVED via anchor_revenues -> combined_anchor_revenue, never accumulated |
| Bucket range | dense (no gaps) from the earliest dated record's month through `today` |
| Window | slices the returned BUCKETS, never the input records |

The `COALESCE(approved_at, created_at)` fallback is the caller's job: it arrives here
already resolved as `DatedDocument.effective_date`. Legacy approved quotes with a NULL
approved_at must still be dated rather than dropped, or the final bucket would silently
disagree with the all-time rollup it is supposed to reconcile with.

Cumulative revenue is a resolution, not a sum: an anchor quoted at $10k and later
invoiced at $3k shows revenue DROPPING at the invoice month. That is honest — it is
what the rollup would have said at each point in time — and `revenue_basis` tells the
UI why. Do not smooth it.
"""

from __future__ import annotations

import calendar
import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal

from app.features.finance.labor_derivation import (
    CENTS,
    ZERO_MONEY,
    EffectiveDatedRate,
    LaborTotals,
    WorkSession,
    summarize_labor,
    work_date_for,
)
from app.features.finance.margin_math import (
    REVENUE_BASIS_NONE,
    REVENUE_BASIS_QUOTED,
    DocumentAmounts,
    MarginFigures,
    MarginInputs,
    ResolvedRevenue,
    RevenueAnchor,
    anchor_revenues,
    combined_anchor_revenue,
    missing_cost_data,
    quoted_revenue,
    summarize_margin,
)

MONTH_KEY_FORMAT = "%Y-%m"
TREND_WINDOW_3M = "3m"
TREND_WINDOW_6M = "6m"
TREND_WINDOW_12M = "12m"
TREND_WINDOW_ALL = "all"
TREND_WINDOW_MONTHS: dict[str, int | None] = {
    TREND_WINDOW_3M: 3,
    TREND_WINDOW_6M: 6,
    TREND_WINDOW_12M: 12,
    TREND_WINDOW_ALL: None,
}
DEFAULT_TREND_WINDOW = TREND_WINDOW_12M

_ABSENT_REVENUE = ResolvedRevenue(total=None, basis=REVENUE_BASIS_NONE)
_ZERO_LABOR = LaborTotals(total=ZERO_MONEY, rated_seconds=0, unrated_seconds=0)


@dataclass(frozen=True)
class DatedCost:
    """One cost entry reduced to the two fields bucketing needs."""

    amount: Decimal
    incurred_date: date


@dataclass(frozen=True)
class DatedDocument:
    """One invoice or approved quote with the date it becomes effective for the trend."""

    anchor: RevenueAnchor
    amounts: DocumentAmounts
    effective_date: date


@dataclass(frozen=True)
class CumulativeCost:
    """The cost side of one bucket: cost entries and derived labor, both cumulative."""

    entries: Decimal
    labor: LaborTotals


@dataclass(frozen=True)
class TrendInputs:
    """Every dated record a project's trend replays, plus the day the trend ends on.

    `quotes` arrives newest-first per anchor (the shipped query order), which is what
    makes the first matching quote row per anchor the one D-01 resolves against.
    """

    costs: Sequence[DatedCost]
    sessions: Sequence[WorkSession]
    rates_by_contractor: Mapping[uuid.UUID, Sequence[EffectiveDatedRate]]
    invoices: Sequence[DatedDocument]
    quotes: Sequence[DatedDocument]
    fallback_quote: DatedDocument | None
    today: date


@dataclass(frozen=True)
class TrendBucket:
    """One month of the cumulative trend, carrying the full shipped margin block."""

    month: str
    cost: Decimal
    margin: MarginFigures


def month_key(day: date) -> str:
    """The "YYYY-MM" bucket a calendar day belongs to."""
    return day.strftime(MONTH_KEY_FORMAT)


def month_edge(month: str) -> date:
    """The inclusive last calendar day of a "YYYY-MM" bucket."""
    first = datetime.strptime(month, MONTH_KEY_FORMAT).date()
    return first.replace(day=calendar.monthrange(first.year, first.month)[1])


def dense_month_keys(first: date, last: date) -> list[str]:
    """Every month key from `first` through `last` inclusive, with no gaps."""
    keys: list[str] = []
    year, month = first.year, first.month
    while (year, month) <= (last.year, last.month):
        keys.append(month_key(date(year, month, 1)))
        year, month = _next_month(year, month)
    return keys


def trend_buckets(inputs: TrendInputs) -> list[TrendBucket]:
    """Dense cumulative monthly buckets, each one a full as-of margin replay.

    Returns no buckets at all when nothing is dated — a project with no records has
    no history, and a fabricated $0 month would read as a real data point.
    """
    first = _earliest_record_date(inputs)
    if first is None:
        return []
    months = dense_month_keys(first, inputs.today)
    entry_prefix = _cost_prefix_sums(inputs.costs, months)
    labor_prefix = _labor_prefix_totals(inputs.sessions, inputs.rates_by_contractor, months)
    return [
        _bucket_for(month, CumulativeCost(entry_prefix[month], labor_prefix[month]), inputs)
        for month in months
    ]


def window_slice(buckets: Sequence[TrendBucket], window: str) -> list[TrendBucket]:
    """The last N buckets of a window — it slices BUCKETS, never records (Pitfall 2).

    Cumulative values always run from project inception, so any month shared by two
    windows carries identical figures.
    """
    months = TREND_WINDOW_MONTHS[window]
    return list(buckets) if months is None else list(buckets[-months:])


def _next_month(year: int, month: int) -> tuple[int, int]:
    """The calendar month after (year, month) — never datetime arithmetic."""
    if month == calendar.DECEMBER:
        return year + 1, calendar.JANUARY
    return year, month + 1


def _earliest_record_date(inputs: TrendInputs) -> date | None:
    """The first day any record lands on, across all four record kinds."""
    documents = [*inputs.invoices, *inputs.quotes]
    if inputs.fallback_quote is not None:
        documents.append(inputs.fallback_quote)
    dates = [cost.incurred_date for cost in inputs.costs]
    dates += [work_date_for(session.clocked_in_at) for session in inputs.sessions]
    dates += [document.effective_date for document in documents]
    return min(dates, default=None)


def _cost_prefix_sums(costs: Sequence[DatedCost], months: Sequence[str]) -> dict[str, Decimal]:
    """Cumulative cost-entry total at each month edge — grouped once, never re-scanned."""
    monthly = _entry_sums_by_month(costs)
    running = ZERO_MONEY
    prefix: dict[str, Decimal] = {}
    for month in months:
        running += monthly.get(month, ZERO_MONEY)
        prefix[month] = running
    return prefix


def _entry_sums_by_month(costs: Sequence[DatedCost]) -> dict[str, Decimal]:
    """Cost-entry amounts summed into their own month, in one pass."""
    monthly: dict[str, Decimal] = {}
    for cost in costs:
        month = month_key(cost.incurred_date)
        monthly[month] = monthly.get(month, ZERO_MONEY) + cost.amount
    return monthly


def _labor_prefix_totals(
    sessions: Sequence[WorkSession],
    rates_by_contractor: Mapping[uuid.UUID, Sequence[EffectiveDatedRate]],
    months: Sequence[str],
) -> dict[str, LaborTotals]:
    """Cumulative derived labor at each month edge."""
    monthly = _labor_by_month(sessions, rates_by_contractor)
    running = _ZERO_LABOR
    prefix: dict[str, LaborTotals] = {}
    for month in months:
        running = _add_labor(running, monthly.get(month, _ZERO_LABOR))
        prefix[month] = running
    return prefix


def _labor_by_month(
    sessions: Sequence[WorkSession],
    rates_by_contractor: Mapping[uuid.UUID, Sequence[EffectiveDatedRate]],
) -> dict[str, LaborTotals]:
    """Each month's sessions costed by the SHIPPED summarize_labor.

    summarize_labor quantizes per session, so a sum of month partitions is bit-identical
    to one whole-set call — this is how the effective-dated rate rule stays in exactly
    one place (Phase 32) and never leaks into SQL.
    """
    partitions: dict[str, list[WorkSession]] = {}
    for session in sessions:
        month = month_key(work_date_for(session.clocked_in_at))
        partitions.setdefault(month, []).append(session)
    return {
        month: summarize_labor(partition, dict(rates_by_contractor))
        for month, partition in partitions.items()
    }


def _add_labor(left: LaborTotals, right: LaborTotals) -> LaborTotals:
    """Component-wise labor accumulation for the running prefix."""
    return LaborTotals(
        total=left.total + right.total,
        rated_seconds=left.rated_seconds + right.rated_seconds,
        unrated_seconds=left.unrated_seconds + right.unrated_seconds,
    )


def _bucket_for(month: str, cost_side: CumulativeCost, inputs: TrendInputs) -> TrendBucket:
    """One bucket: the cumulative cost at this edge against the revenue resolved there."""
    edge = month_edge(month)
    cost = (cost_side.entries + cost_side.labor.total).quantize(CENTS)
    revenue = _revenue_at(edge, inputs) or _ABSENT_REVENUE
    return TrendBucket(
        month=month,
        cost=cost,
        margin=summarize_margin(
            MarginInputs(
                revenue=revenue,
                cost=cost,
                unrated_seconds=cost_side.labor.unrated_seconds,
                has_missing_cost_data=_missing_cost_flag(revenue, cost),
            )
        ),
    )


def _revenue_at(edge: date, inputs: TrendInputs) -> ResolvedRevenue | None:
    """The D-01 resolution replayed over only the documents effective on or before `edge`."""
    resolved = anchor_revenues(
        _effective_rows(inputs.invoices, edge), _effective_rows(inputs.quotes, edge)
    )
    combined = combined_anchor_revenue(resolved)
    if combined is not None:
        return combined
    return _fallback_revenue_at(edge, inputs.fallback_quote)


def _effective_rows(
    documents: Sequence[DatedDocument], edge: date
) -> list[tuple[RevenueAnchor, DocumentAmounts]]:
    """The (anchor, amounts) rows effective by `edge`, in the caller's query order."""
    return [
        (document.anchor, document.amounts)
        for document in documents
        if document.effective_date <= edge
    ]


def _fallback_revenue_at(edge: date, quote: DatedDocument | None) -> ResolvedRevenue | None:
    """D-14 anchor of last resort: the project-level approved quote, once it is effective."""
    if quote is None or quote.effective_date > edge:
        return None
    return ResolvedRevenue(total=quoted_revenue(quote.amounts), basis=REVENUE_BASIS_QUOTED)


def _missing_cost_flag(revenue: ResolvedRevenue, cost: Decimal) -> bool:
    """D-12 at trend granularity: applied to the project total, not per anchor.

    The trend carries no per-anchor cost split (labor is job-anchored while cost entries
    are prefix-summed project-wide), so a revenue-bearing project with zero cost at an
    edge flags that bucket. Deliberately coarser than the rollup's per-anchor sweep.
    """
    return missing_cost_data(cost, revenue.total)
