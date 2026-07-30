"""QuoteVarianceService — quoted-vs-actual for one quote and for one project (FINAI-05).

Quoted revenue (pre-tax) against actual cost, for one quote or one project. Both
legs come from their shipped owners — margin_math's quoted_revenue for the quote
leg, contributing_anchor_cost (over a FinanceService.anchor_cost_context) for the
cost leg — because a second definition of either is the drift 34-02/35-05/35-06
recorded rules against. Quote line items are revenue-side and are never summed
into a cost (RESEARCH Pitfall 3).

"Comparable" gate (D-02): an anchor contributes an `actual` only when it has at
least one non-deleted invoice — invoice existence IS "issued" (finance/repository.py
docstring). Without an invoice the figures are None, never 0: a missing comparison
is not a variance of nothing.

D-14 (project-level quotes): line items are grouped by normalised `field`
(`strip().casefold()`, empty/NULL dropped) and matched to the job that
`_convert_project_quote` created for that field at approval. Phase 33's D-14
last-resort project-quote rule is deliberately NOT reused here — it governs
revenue *resolution*, a different question, and a blended whole-project number
would defeat the per-trade feedback loop this phase exists to close.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import select

from app.core.base_service import TenantScopedService, entity_or_404
from app.features.finance.labor_derivation import ZERO_MONEY
from app.features.finance.margin_math import DocumentAmounts, RevenueAnchor, quoted_revenue
from app.features.finance.repository import RevenueRepository, invoice_amounts_query
from app.features.finance.service import (
    FinanceService,
    ProjectMarginContext,
    contributing_anchor_cost,
)
from app.features.invoices.models import Invoice
from app.features.jobs.models import Job
from app.features.projects.models import TradeScope
from app.features.quotes.models import Quote, QuoteLineItem
from app.features.quotes.quote_history_math import prorated_pre_tax_totals, variance_for
from app.features.quotes.repository import QuoteRepository

PROJECT_TOTAL_LABEL = "Project total"


@dataclass(frozen=True)
class QuoteVarianceTrade:
    """One field group's (or project anchor's) quoted-vs-actual row."""

    label: str
    quoted: Decimal | None
    actual: Decimal | None
    variance: Decimal | None
    variance_percent: Decimal | None


# Not comparable (D-02): quoted, actual, variance and variance_percent all null —
# a missing comparison is not a variance of nothing.
_NOT_COMPARABLE_FIGURES = (None, None, None, None)


@dataclass(frozen=True)
class QuoteVarianceResult:
    """One quote's quoted-vs-actual — a single figure, or a per-field table (D-14)."""

    quoted: Decimal | None
    actual: Decimal | None
    variance: Decimal | None
    variance_percent: Decimal | None
    labor_included: bool
    scope_anchored: bool
    trades: list[QuoteVarianceTrade]


@dataclass(frozen=True)
class ProjectQuoteVarianceResult:
    """One row per invoiced, approved-quote anchor in a project, plus a summed total."""

    scopes: list[QuoteVarianceTrade]
    total: QuoteVarianceTrade
    labor_included: bool
    has_scope_anchored_rows: bool


def _normalized_field(field: str | None) -> str | None:
    """`strip().casefold()`, with empty/whitespace-only collapsing to None (D-14)."""
    if field is None:
        return None
    normalized = field.strip().casefold()
    return normalized or None


def _group_line_items_by_field(
    line_items: Iterable[QuoteLineItem],
) -> tuple[list[str], dict[str, str], dict[str, Decimal]]:
    """Group line items by normalised field, preserving first-seen order.

    Returns (ordered keys, key -> display label, key -> grouped subtotal). Items
    with no field (or an empty one) contribute to no group — their share of the
    quote's pre-tax total is folded into the other groups by
    `prorated_pre_tax_totals`'s remainder correction, which is why the trades'
    quoted values still sum exactly to the whole quote.
    """
    order: list[str] = []
    labels: dict[str, str] = {}
    subtotals: dict[str, Decimal] = {}
    for item in line_items:
        key = _normalized_field(item.field)
        if key is None:
            continue
        if key not in subtotals:
            order.append(key)
            labels[key] = item.field.strip()  # type: ignore[union-attr]
            subtotals[key] = Decimal("0")
        subtotals[key] += item.quantity * item.unit_price
    return order, labels, subtotals


def _quote_amounts(quote: Quote) -> DocumentAmounts:
    """The whole quote's document amounts — every line item, regardless of field."""
    subtotal = sum((item.quantity * item.unit_price for item in quote.line_items), Decimal("0"))
    return DocumentAmounts(
        subtotal=subtotal,
        discount_type=quote.discount_type,
        discount_value=quote.discount_value,
        tax_rate=quote.tax_rate,
    )


def _labor_included_for_jobs(
    job_ids: Iterable[uuid.UUID], context: ProjectMarginContext | None
) -> bool:
    """True when any of the given jobs' derived labor (already batched in `context`) is non-zero."""
    if context is None:
        return False
    return any(
        (labor := context.labor_by_job.get(job_id)) is not None and labor.total != ZERO_MONEY
        for job_id in job_ids
    )


class QuoteVarianceService(TenantScopedService[Quote]):
    """Quoted-vs-actual for one quote (quote detail) and one project (financials drill-down)."""

    repository_class = QuoteRepository
    repository: QuoteRepository

    async def quote_variance(self, quote_id: uuid.UUID) -> QuoteVarianceResult:
        """One quote's quoted-vs-actual — branches on its anchor (job, scope, or project-level)."""
        quote = entity_or_404(
            await self.repository.get_with_line_items(quote_id), "Quote not found"
        )
        amounts = _quote_amounts(quote)
        quoted_total = quoted_revenue(amounts)

        if quote.job_id is not None:
            return await self._job_anchored_variance(quote.job_id, quoted_total)
        if quote.trade_scope_id is not None:
            return await self._scope_anchored_variance(quote.trade_scope_id, quoted_total)
        return await self._project_level_variance(quote, amounts, quoted_total)

    async def _job_anchored_variance(
        self, job_id: uuid.UUID, quoted_total: Decimal
    ) -> QuoteVarianceResult:
        """A job-anchored quote's variance — actual from the shipped job cost breakdown."""
        anchor = RevenueAnchor(job_id=job_id)
        if not await RevenueRepository(self.db).invoice_amounts_for_anchor(anchor):
            return QuoteVarianceResult(*_NOT_COMPARABLE_FIGURES, False, False, [])

        breakdown = await FinanceService(self.db).job_cost_breakdown(job_id)
        labor_included = breakdown.labor is not None and breakdown.labor.total != ZERO_MONEY
        figures = variance_for(quoted_total, breakdown.grand_total)
        return QuoteVarianceResult(
            quoted=figures.quoted,
            actual=figures.actual,
            variance=figures.variance,
            variance_percent=figures.variance_percent,
            labor_included=labor_included,
            scope_anchored=False,
            trades=[],
        )

    async def _scope_anchored_variance(
        self, trade_scope_id: uuid.UUID, quoted_total: Decimal
    ) -> QuoteVarianceResult:
        """A scope-anchored quote's variance — labor is structurally excluded (Trap 6)."""
        anchor = RevenueAnchor(trade_scope_id=trade_scope_id)
        if not await RevenueRepository(self.db).invoice_amounts_for_anchor(anchor):
            return QuoteVarianceResult(*_NOT_COMPARABLE_FIGURES, False, True, [])

        actual = await FinanceService(self.db).trade_scope_spend(trade_scope_id)
        figures = variance_for(quoted_total, actual)
        return QuoteVarianceResult(
            quoted=figures.quoted,
            actual=figures.actual,
            variance=figures.variance,
            variance_percent=figures.variance_percent,
            labor_included=False,
            scope_anchored=True,
            trades=[],
        )

    async def _project_level_variance(
        self, quote: Quote, amounts: DocumentAmounts, quoted_total: Decimal
    ) -> QuoteVarianceResult:
        """A project-level quote's D-14 per-field breakdown against the jobs approval created."""
        order, labels, subtotals = _group_line_items_by_field(quote.line_items)
        if not order:
            return QuoteVarianceResult(quoted_total, None, None, None, False, False, [])

        shares = prorated_pre_tax_totals([subtotals[key] for key in order], amounts)
        jobs_by_field = await self._jobs_by_normalized_trade(quote.project_id)
        matched_job_ids = [jobs_by_field[key] for key in order if key in jobs_by_field]
        invoiced_job_ids = await self._invoiced_job_ids(matched_job_ids)
        context = (
            await FinanceService(self.db).anchor_cost_context(quote.project_id)
            if matched_job_ids and quote.project_id is not None
            else None
        )

        trades = [
            self._trade_for_field_group(
                labels[key], quoted_share, jobs_by_field.get(key), invoiced_job_ids, context
            )
            for key, quoted_share in zip(order, shares, strict=True)
        ]

        all_comparable = bool(trades) and all(trade.actual is not None for trade in trades)
        total_figures = (
            variance_for(quoted_total, sum((trade.actual for trade in trades), Decimal("0")))
            if all_comparable
            else None
        )
        return QuoteVarianceResult(
            quoted=quoted_total,
            actual=total_figures.actual if total_figures else None,
            variance=total_figures.variance if total_figures else None,
            variance_percent=total_figures.variance_percent if total_figures else None,
            labor_included=_labor_included_for_jobs(matched_job_ids, context),
            scope_anchored=False,
            trades=trades,
        )

    @staticmethod
    def _trade_for_field_group(
        label: str,
        quoted: Decimal,
        job_id: uuid.UUID | None,
        invoiced_job_ids: set[uuid.UUID],
        context: ProjectMarginContext | None,
    ) -> QuoteVarianceTrade:
        """One field group's row — null actual when its matched job has no invoice (D-14)."""
        if job_id is None or job_id not in invoiced_job_ids or context is None:
            return QuoteVarianceTrade(
                label=label, quoted=quoted, actual=None, variance=None, variance_percent=None
            )
        actual = contributing_anchor_cost(RevenueAnchor(job_id=job_id), context)
        figures = variance_for(quoted, actual)
        return QuoteVarianceTrade(
            label=label,
            quoted=figures.quoted,
            actual=figures.actual,
            variance=figures.variance,
            variance_percent=figures.variance_percent,
        )

    async def _jobs_by_normalized_trade(self, project_id: uuid.UUID | None) -> dict[str, uuid.UUID]:
        """This project's jobs keyed by normalised trade_type, in ONE query."""
        if project_id is None:
            return {}
        result = await self.db.execute(
            select(Job.id, Job.trade_type).where(
                Job.project_id == project_id, Job.deleted_at.is_(None)
            )
        )
        jobs: dict[str, uuid.UUID] = {}
        for job_id, trade_type in result.all():
            key = _normalized_field(trade_type)
            if key is not None and key not in jobs:
                jobs[key] = job_id
        return jobs

    async def _invoiced_job_ids(self, job_ids: Sequence[uuid.UUID]) -> set[uuid.UUID]:
        """Which of these jobs have at least one non-deleted invoice, in ONE query (D-02)."""
        if not job_ids:
            return set()
        result = await self.db.execute(invoice_amounts_query().where(Invoice.job_id.in_(job_ids)))
        return {row.job_id for row in result.all()}

    async def project_quote_variance(self, project_id: uuid.UUID) -> ProjectQuoteVarianceResult:
        """One row per invoiced, approved-quote anchor in a project, plus a summed total."""
        quoted_by_anchor = await self._latest_approved_quote_amounts_by_anchor(project_id)
        invoiced_anchors = await self._invoiced_anchors_for_project(project_id)
        comparable_anchors = [anchor for anchor in quoted_by_anchor if anchor in invoiced_anchors]
        if not comparable_anchors:
            empty_total = QuoteVarianceTrade(PROJECT_TOTAL_LABEL, None, None, None, None)
            return ProjectQuoteVarianceResult(
                scopes=[], total=empty_total, labor_included=False, has_scope_anchored_rows=False
            )

        context = await FinanceService(self.db).anchor_cost_context(project_id)
        labels = await self._anchor_labels(comparable_anchors)

        rows = [
            self._trade_for_anchor(anchor, quoted_by_anchor[anchor], context, labels[anchor])
            for anchor in comparable_anchors
        ]
        total_figures = variance_for(
            sum((row.quoted for row in rows), Decimal("0")),
            sum((row.actual for row in rows), Decimal("0")),
        )
        total = QuoteVarianceTrade(
            label=PROJECT_TOTAL_LABEL,
            quoted=total_figures.quoted,
            actual=total_figures.actual,
            variance=total_figures.variance,
            variance_percent=total_figures.variance_percent,
        )
        job_ids_in_play = [
            anchor.job_id for anchor in comparable_anchors if anchor.job_id is not None
        ]
        return ProjectQuoteVarianceResult(
            scopes=rows,
            total=total,
            labor_included=_labor_included_for_jobs(job_ids_in_play, context),
            has_scope_anchored_rows=any(
                anchor.trade_scope_id is not None for anchor in comparable_anchors
            ),
        )

    @staticmethod
    def _trade_for_anchor(
        anchor: RevenueAnchor,
        quoted: Decimal,
        context: ProjectMarginContext,
        label: str,
    ) -> QuoteVarianceTrade:
        """One project anchor's row — always comparable by construction (caller pre-filtered)."""
        actual = contributing_anchor_cost(anchor, context)
        figures = variance_for(quoted, actual)
        return QuoteVarianceTrade(
            label=label,
            quoted=figures.quoted,
            actual=figures.actual,
            variance=figures.variance,
            variance_percent=figures.variance_percent,
        )

    async def _latest_approved_quote_amounts_by_anchor(
        self, project_id: uuid.UUID
    ) -> dict[RevenueAnchor, Decimal]:
        """Each anchor's latest approved-quote pre-tax total, in ONE query (newest-first)."""
        rows = await RevenueRepository(self.db).approved_quote_amounts_by_anchor_for_project(
            project_id
        )
        quoted: dict[RevenueAnchor, Decimal] = {}
        for anchor, document in rows:
            if anchor not in quoted:
                quoted[anchor] = quoted_revenue(document)
        return quoted

    async def _invoiced_anchors_for_project(self, project_id: uuid.UUID) -> set[RevenueAnchor]:
        """Every anchor with at least one non-deleted invoice, in ONE query."""
        rows = await RevenueRepository(self.db).invoice_amounts_by_anchor_for_project(project_id)
        return {anchor for anchor, _ in rows}

    async def _anchor_labels(self, anchors: Sequence[RevenueAnchor]) -> dict[RevenueAnchor, str]:
        """Trade label for each anchor — job.trade_type or scope.trade_name, 2 bounded queries."""
        job_ids = [anchor.job_id for anchor in anchors if anchor.job_id is not None]
        scope_ids = [
            anchor.trade_scope_id for anchor in anchors if anchor.trade_scope_id is not None
        ]
        job_labels = await self._labels_for(Job.id, Job.trade_type, job_ids)
        scope_labels = await self._labels_for(TradeScope.id, TradeScope.trade_name, scope_ids)
        return {
            anchor: job_labels[anchor.job_id]
            if anchor.job_id is not None
            else scope_labels[anchor.trade_scope_id]
            for anchor in anchors
        }

    async def _labels_for(
        self, id_column, label_column, ids: Sequence[uuid.UUID]
    ) -> dict[uuid.UUID, str]:
        """Column-only id -> label lookup for a batch of ids, or {} for an empty batch."""
        if not ids:
            return {}
        result = await self.db.execute(select(id_column, label_column).where(id_column.in_(ids)))
        return dict(result.all())
