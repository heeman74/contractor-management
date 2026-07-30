"""QuoteComparableRepository — the bounded, same-trade comparable query (D-01/D-03).

Fetches completed, invoiced work of one trade in a FIXED number of round trips,
regardless of how many comparables exist, and composes the shipped finance query
builders rather than restating their traversal (`invoice_amounts_query`,
`approved_quote_amounts_query`, `costable_sessions_query` — a second definition
would drift from the margin rollup, exactly what 35-05's equivalence test exists
to catch as a regression here).

Trade key ladder (Trap 3 — free text everywhere; normalised with
`strip().casefold()`): job anchors key on `Job.trade_type` (NOT NULL); scope
anchors on `TradeScope.trade_name` (NOT NULL).

Eligibility — an anchor is a comparable when it has at least one invoice AND its
actual cost is greater than zero (PITFALLS #9: an invoiced anchor with no cost
entries would otherwise poison the dataset as a fabricated 100%-margin
comparable) — is applied here, in Python, AFTER the fetch, never as a SQL WHERE
clause: the predicate composes the shipped `missing_cost_data` rather than
re-deriving `cost <= 0` inline, and stays as readable and testable as any other
reduction step.

A comparable's actual cost is `contributing_anchor_cost` itself, called on a
`ProjectMarginContext` built from this trade's own batched cost/labor read — the
same function the margin rollup and the profitability detector both call, so
this feature's notion of "cost" can never drift from theirs. Trap 6: a
trade-scope anchor structurally carries no labor (`TimeEntry.job_id` is the only
FK tracked time has), so labor is folded in for job anchors only.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import Row, func, or_, select

from app.core.base_repository import TenantScopedRepository
from app.features.finance.labor_derivation import (
    ZERO_MONEY,
    LaborTotals,
    WorkSession,
    summarize_labor,
)
from app.features.finance.margin_math import (
    DocumentAmounts,
    RevenueAnchor,
    missing_cost_data,
    pre_tax_total,
)
from app.features.finance.models import CostEntry, LaborRate
from app.features.finance.repository import (
    LaborRateRepository,
    approved_quote_amounts_query,
    costable_sessions_query,
    invoice_amounts_query,
    to_anchored_amounts,
    to_work_sessions,
)
from app.features.finance.service import ProjectMarginContext, contributing_anchor_cost
from app.features.invoices.models import Invoice
from app.features.jobs.models import Job, TimeEntry
from app.features.projects.models import TradeScope
from app.features.quotes.models import Quote, QuoteLineItem
from app.features.quotes.quote_history_math import ComparableAnchor, ComparableLine

# A sentinel used only to invoke the shared zero-cost predicate; invoiced-ness
# itself is checked separately, by anchor membership in the invoice rows.
_SENTINEL_POSITIVE_REVENUE = Decimal("1")


@dataclass(frozen=True)
class ComparableRows:
    """The bounded, same-trade comparable set — plain data, no ORM entities.

    `anchors` and `lines` are `quote_history_math`'s own types: the shape a
    comparable reduces to is defined exactly once, in the pure math module that
    consumes it, not restated here.
    """

    anchors: tuple[ComparableAnchor, ...]
    lines: tuple[ComparableLine, ...]


class QuoteComparableRepository(TenantScopedRepository[Quote]):
    """Same-trade completed work, in a fixed number of round trips.

    Every predicate here is composed from the shipped finance query builders
    rather than restated: a second definition of the invoice or approved-quote
    traversal would drift from the margin rollup, which is exactly what 35-05's
    equivalence test exists to catch.
    """

    model = Quote

    async def comparables_for_trade(self, trade_key: str) -> ComparableRows:
        """Every comparable anchor of one trade, plus the lines behind them.

        Eight round trips, all column-only and constant in comparable count:
        job anchors, scope anchors, cost sums, costable sessions, labor rates,
        invoice amounts, approved-quote amounts, and the line items of the
        approved quotes that survive eligibility filtering.
        """
        normalized_trade = trade_key.strip().casefold()
        job_ids = [row.id for row in await self._job_anchor_rows(normalized_trade)]
        scope_ids = [row.id for row in await self._scope_anchor_rows(normalized_trade)]
        if not job_ids and not scope_ids:
            return ComparableRows(anchors=(), lines=())

        anchor_costs = await self._anchor_cost_sums(job_ids, scope_ids)
        sessions = await self._costable_sessions(job_ids)
        rates_by_contractor = await self._rates_for_sessions(sessions)
        labor_by_job = _labor_totals_by_job(sessions, rates_by_contractor)
        context = ProjectMarginContext(
            anchor_costs=anchor_costs,
            labor_by_job=labor_by_job,
            grand_total=ZERO_MONEY,
            unrated_seconds=0,
        )

        invoiced_anchors = await self._invoiced_anchor_set(job_ids, scope_ids)
        quotes_by_anchor = await self._latest_quote_by_anchor(job_ids, scope_ids)

        comparable_anchors: list[ComparableAnchor] = []
        comparable_quote_ids: list[uuid.UUID] = []
        for anchor in _all_anchors(job_ids, scope_ids):
            if anchor not in invoiced_anchors:
                continue
            cost = contributing_anchor_cost(anchor, context)
            if not _has_cost_data(cost):
                continue
            quote = quotes_by_anchor.get(anchor)
            labor_totals = None if anchor.job_id is None else labor_by_job.get(anchor.job_id)
            comparable_anchors.append(
                ComparableAnchor(
                    is_job_anchored=anchor.job_id is not None,
                    actual_cost=cost,
                    quoted_pre_tax=None if quote is None else pre_tax_total(quote[1]),
                    labor_cost=ZERO_MONEY if labor_totals is None else labor_totals.total,
                )
            )
            if quote is not None:
                comparable_quote_ids.append(quote[0])

        lines = await self._comparable_lines(comparable_quote_ids)
        return ComparableRows(anchors=tuple(comparable_anchors), lines=lines)

    async def _job_anchor_rows(self, trade_key: str) -> Sequence[Row]:
        """(id, trade_type) for every live job whose normalised trade matches."""
        result = await self.db.execute(
            select(Job.id, Job.trade_type).where(
                Job.deleted_at.is_(None),
                func.lower(func.trim(Job.trade_type)) == trade_key,
            )
        )
        return result.all()

    async def _scope_anchor_rows(self, trade_key: str) -> Sequence[Row]:
        """(id, trade_name) for every live trade scope whose normalised trade matches."""
        result = await self.db.execute(
            select(TradeScope.id, TradeScope.trade_name).where(
                TradeScope.deleted_at.is_(None),
                func.lower(func.trim(TradeScope.trade_name)) == trade_key,
            )
        )
        return result.all()

    async def _anchor_cost_sums(
        self, job_ids: Sequence[uuid.UUID], scope_ids: Sequence[uuid.UUID]
    ) -> dict[RevenueAnchor, Decimal]:
        """Per-anchor cost-entry sums, in one GROUP BY round trip."""
        result = await self.db.execute(
            select(
                CostEntry.job_id,
                CostEntry.trade_scope_id,
                func.sum(CostEntry.amount).label("total"),
            )
            .where(CostEntry.deleted_at.is_(None), _anchor_in_filter(CostEntry, job_ids, scope_ids))
            .group_by(CostEntry.job_id, CostEntry.trade_scope_id)
        )
        return {
            RevenueAnchor(job_id=row.job_id, trade_scope_id=row.trade_scope_id): row.total
            for row in result.all()
        }

    async def _costable_sessions(self, job_ids: Sequence[uuid.UUID]) -> list[WorkSession]:
        """Costable tracked time for the job anchors only — trade scopes track none."""
        if not job_ids:
            return []
        result = await self.db.execute(
            costable_sessions_query().where(TimeEntry.job_id.in_(job_ids))
        )
        return to_work_sessions(result.tuples().all())

    async def _rates_for_sessions(
        self, sessions: Sequence[WorkSession]
    ) -> dict[uuid.UUID, list[LaborRate]]:
        """Active rate rows for every contractor seen, in one bounded query."""
        contractor_ids = sorted({session.contractor_id for session in sessions})
        rates = await LaborRateRepository(self.db).list_rates_for_users(contractor_ids)
        grouped: dict[uuid.UUID, list[LaborRate]] = {}
        for rate in rates:
            grouped.setdefault(rate.user_id, []).append(rate)
        return grouped

    async def _invoiced_anchor_set(
        self, job_ids: Sequence[uuid.UUID], scope_ids: Sequence[uuid.UUID]
    ) -> frozenset[RevenueAnchor]:
        """Every anchor carrying at least one issued invoice — existence IS "issued"."""
        result = await self.db.execute(
            invoice_amounts_query().where(_anchor_in_filter(Invoice, job_ids, scope_ids))
        )
        return frozenset(to_anchored_amounts(row)[0] for row in result.all())

    async def _latest_quote_by_anchor(
        self, job_ids: Sequence[uuid.UUID], scope_ids: Sequence[uuid.UUID]
    ) -> dict[RevenueAnchor, tuple[uuid.UUID, DocumentAmounts]]:
        """Each anchor's latest approved quote (id + amounts), or absent when none.

        The shipped newest-first ordering is preserved, so the FIRST row an
        anchor yields is kept — the same "latest approved" rule every other
        finance caller of this builder relies on.
        """
        result = await self.db.execute(
            approved_quote_amounts_query()
            .add_columns(Quote.id)
            .where(_anchor_in_filter(Quote, job_ids, scope_ids))
        )
        latest: dict[RevenueAnchor, tuple[uuid.UUID, DocumentAmounts]] = {}
        for row in result.all():
            anchor, amounts = to_anchored_amounts(row)
            latest.setdefault(anchor, (row.id, amounts))
        return latest

    async def _comparable_lines(self, quote_ids: Sequence[uuid.UUID]) -> tuple[ComparableLine, ...]:
        """Line items of the comparable anchors' approved quotes, column-only."""
        if not quote_ids:
            return ()
        result = await self.db.execute(
            select(
                QuoteLineItem.item_type,
                QuoteLineItem.description,
                QuoteLineItem.quantity,
                QuoteLineItem.unit,
                QuoteLineItem.unit_price,
            ).where(QuoteLineItem.quote_id.in_(quote_ids), QuoteLineItem.deleted_at.is_(None))
        )
        return tuple(
            ComparableLine(
                item_type=row.item_type,
                unit=row.unit,
                description=row.description,
                quantity=row.quantity,
                unit_price=row.unit_price,
            )
            for row in result.all()
        )


def _anchor_in_filter(document, job_ids: Sequence[uuid.UUID], scope_ids: Sequence[uuid.UUID]):
    """`job_id IN (...) OR trade_scope_id IN (...)`, omitting an empty side entirely
    — an `IN ()` is a wasted trip, not a filter."""
    clauses = []
    if job_ids:
        clauses.append(document.job_id.in_(job_ids))
    if scope_ids:
        clauses.append(document.trade_scope_id.in_(scope_ids))
    return or_(*clauses)


def _all_anchors(
    job_ids: Sequence[uuid.UUID], scope_ids: Sequence[uuid.UUID]
) -> list[RevenueAnchor]:
    """Every fetched anchor of this trade, job and scope alike, before eligibility."""
    return [RevenueAnchor(job_id=job_id) for job_id in job_ids] + [
        RevenueAnchor(trade_scope_id=scope_id) for scope_id in scope_ids
    ]


def _has_cost_data(cost: Decimal) -> bool:
    """PITFALLS #9 guard: composes the shipped zero-cost predicate rather than
    re-deriving `cost <= 0` inline. The sentinel revenue only tests cost's
    sign — invoiced-ness is checked separately, by anchor membership."""
    return not missing_cost_data(cost, _SENTINEL_POSITIVE_REVENUE)


def _labor_totals_by_job(
    sessions: Sequence[WorkSession], rates_by_contractor: dict[uuid.UUID, list[LaborRate]]
) -> dict[uuid.UUID, LaborTotals]:
    """Per-job derived labor, from the SAME sessions and rates the batched read fetched."""
    sessions_by_job: dict[uuid.UUID, list[WorkSession]] = {}
    for session in sessions:
        if session.job_id is not None:
            sessions_by_job.setdefault(session.job_id, []).append(session)
    return {
        job_id: summarize_labor(job_sessions, rates_by_contractor)
        for job_id, job_sessions in sessions_by_job.items()
    }
