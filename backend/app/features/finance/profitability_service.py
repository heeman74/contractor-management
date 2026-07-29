"""ProfitabilityService — the read half of the nightly AI profitability analysis (FINAI-01).

This service fetches and gates; it decides nothing about margin. Detection is
deterministic and lives entirely in `profitability_math` (D-02), so no threshold,
band rule or signal comparison is restated here.

Two orderings in `scan_candidates` are load-bearing:

- The D-01 eligibility gate runs BEFORE any trend replay, which is what keeps the
  scan's statement count O(eligible) rather than O(all projects).
- Every figure the payload carries is read from one batched company-wide read
  (`PortfolioService.all_project_figures`), never from a per-project rollup call
  inside the loop (CLAUDE.md's no-query-in-a-loop rule at company scale).

No run-log table exists in this codebase and no success criterion needs one:
structured logging IS the run log, one line per skip plus one summary per company.

No method here commits — on the scheduler path only `_run_for_all_companies` does.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.core.base_service import TenantScopedService
from app.core.logging_config import get_logger
from app.features.finance.budget_math import percent_used
from app.features.finance.labor_derivation import ZERO_MONEY
from app.features.finance.margin_math import RevenueAnchor, anchor_revenues
from app.features.finance.portfolio_math import AnchoredBudget, ProjectFinancialFigures
from app.features.finance.portfolio_service import (
    PortfolioInputs,
    PortfolioService,
    ProjectCostBlocks,
    project_cost_blocks,
)
from app.features.finance.profitability_math import (
    CandidateSignal,
    DetectionInputs,
    QuoteGapInputs,
    SkipReason,
    candidate_for,
    latest_quote_per_anchor,
    skip_reason_for,
)
from app.features.finance.profitability_models import AIProfitabilityFinding
from app.features.finance.profitability_repository import ProfitabilityRepository
from app.features.finance.schemas import CategoryTotal
from app.features.finance.service import contributing_anchor_cost
from app.features.finance.trend_math import TrendBucket

logger = get_logger(__name__)

# Rendered at the call site, not handed to the logger as positional args: this app
# binds structlog to the stdlib bridge, which defers %-formatting to the handler —
# so the values never reach structlog.testing.capture_logs and the run log would be
# unassertable.
SKIP_LOG_TEMPLATE = "ai_profitability: skipped project=%s reason=%s"
SCAN_SUMMARY_LOG_TEMPLATE = "ai_profitability: company=%s analyzed=%d candidates=%d skipped=%d"

LABOR_BASIS_UNBURDENED = "unburdened"
"""D-06: v4.0 labor cost is wage-only, so the basis travels with the payload and
the finding can never present an unburdened figure as a fully loaded one."""

TREND_PAYLOAD_BUCKETS = 2

type SkippedProject = tuple[uuid.UUID, SkipReason]
type PayloadRow = dict[str, object]


@dataclass(frozen=True)
class ProfitabilityCandidate:
    """One project that reached the AI: its candidate signal and the payload the
    finding will be grounded against.

    `revenue_basis` and `labor_included` are the two honesty columns every finding
    row carries, so the UI can caption an estimate-backed or wage-only figure
    without re-deriving either from the payload.
    """

    candidate: CandidateSignal
    project_name: str
    revenue_basis: str
    labor_included: bool
    payload: dict[str, object]


@dataclass(frozen=True)
class PayloadInputs:
    """Everything one project's payload is assembled from — all already fetched."""

    figures: ProjectFinancialFigures
    candidate: CandidateSignal
    blocks: ProjectCostBlocks
    buckets: Sequence[TrendBucket]


class ProfitabilityService(TenantScopedService[AIProfitabilityFinding]):
    """Nightly AI profitability analysis (FINAI-01/02).

    Detection is deterministic and lives in profitability_math; this service only
    fetches, gates, assembles the payload, and (in later plans) calls Claude,
    validates, persists and alerts.
    """

    repository_class = ProfitabilityRepository
    repository: ProfitabilityRepository

    async def scan_candidates(self, company_id: uuid.UUID) -> list[ProfitabilityCandidate]:
        """Every project in this company the AI should write a finding about tonight.

        Deterministic and side-effect free apart from logging: nothing is persisted
        and no Claude call is made here.
        """
        portfolio = PortfolioService(self.db)
        figures, inputs = await portfolio.all_project_figures()
        eligible, skipped = self._partition_by_eligibility(figures)
        self._log_skips(skipped)
        candidates = await self._candidates_for(eligible, inputs, portfolio)
        logger.info(
            SCAN_SUMMARY_LOG_TEMPLATE % (company_id, len(eligible), len(candidates), len(skipped))
        )
        return candidates

    @staticmethod
    def _partition_by_eligibility(
        figures: Sequence[ProjectFinancialFigures],
    ) -> tuple[list[ProjectFinancialFigures], list[SkippedProject]]:
        """Split D-01's verdict: what the AI may analyze, and what it may not, with reasons."""
        eligible: list[ProjectFinancialFigures] = []
        skipped: list[SkippedProject] = []
        for project in figures:
            reason = skip_reason_for(project)
            if reason is None:
                eligible.append(project)
            else:
                skipped.append((project.project_id, reason))
        return eligible, skipped

    @staticmethod
    def _log_skips(skipped: Sequence[SkippedProject]) -> None:
        """Name every excluded project and its reason — a skip is never silent."""
        for project_id, reason in skipped:
            logger.info(SKIP_LOG_TEMPLATE % (project_id, reason.value))

    async def _candidates_for(
        self,
        eligible: Sequence[ProjectFinancialFigures],
        inputs: PortfolioInputs,
        portfolio: PortfolioService,
    ) -> list[ProfitabilityCandidate]:
        """Run detection over the eligible projects only, keeping those that fired."""
        candidates: list[ProfitabilityCandidate] = []
        for figures in eligible:
            candidate = await self._candidate_for_project(figures, inputs, portfolio)
            if candidate is not None:
                candidates.append(candidate)
        return candidates

    async def _candidate_for_project(
        self,
        figures: ProjectFinancialFigures,
        inputs: PortfolioInputs,
        portfolio: PortfolioService,
    ) -> ProfitabilityCandidate | None:
        """One eligible project's candidate, or None when no D-03 signal fired.

        The trend replay is the only per-project read on this path. It is bounded
        (the same profile as the shipped project rollup) and, crucially, it runs
        only for projects the eligibility gate already cleared.
        """
        buckets = await portfolio.unsliced_trend_buckets(figures.project_id)
        blocks = project_cost_blocks(figures.project_id, inputs)
        candidate = candidate_for(
            DetectionInputs(
                figures=figures,
                buckets=buckets,
                quote_gap_inputs=self._quote_gap_inputs(figures, blocks, inputs),
            )
        )
        if candidate is None:
            return None
        return _to_profitability_candidate(
            PayloadInputs(figures=figures, candidate=candidate, blocks=blocks, buckets=buckets)
        )

    @staticmethod
    def _quote_gap_inputs(
        figures: ProjectFinancialFigures, blocks: ProjectCostBlocks, inputs: PortfolioInputs
    ) -> QuoteGapInputs:
        """The three D-03 signal-3 maps, all built from already-fetched rows.

        The anchor-cost map is a dict comprehension over the batched cost rows,
        composing the SHIPPED per-anchor cost predicate — not a query per anchor.
        """
        project_id = figures.project_id
        quote_rows = inputs.quotes.get(project_id, [])
        resolved = anchor_revenues(inputs.invoices.get(project_id, []), quote_rows)
        latest_quotes = latest_quote_per_anchor(quote_rows)
        anchors: set[RevenueAnchor] = resolved.keys() | latest_quotes.keys()
        return QuoteGapInputs(
            resolved=resolved,
            latest_quotes=latest_quotes,
            anchor_costs={
                anchor: contributing_anchor_cost(anchor, blocks.context) for anchor in anchors
            },
        )


def _to_profitability_candidate(inputs: PayloadInputs) -> ProfitabilityCandidate:
    """Wrap one fired candidate with the finding metadata and payload its row carries."""
    labor_cost = _labor_cost(inputs.blocks)
    return ProfitabilityCandidate(
        candidate=inputs.candidate,
        project_name=inputs.figures.name,
        revenue_basis=inputs.figures.margin.revenue_basis,
        labor_included=labor_cost > ZERO_MONEY,
        payload=_build_payload(inputs),
    )


def _build_payload(inputs: PayloadInputs) -> dict[str, object]:
    """The complete, CLOSED value set the finding may cite.

    Aggregates only — never raw cost rows (the PITFALLS performance note). Every
    derived figure the prompt permits is a NAMED field here, because the
    alternative is a validator that searches for derivable arithmetic: unbounded,
    slow, and a hallucination-laundering channel. Decimals stay Decimal so
    collect_allowed_values sees them and payload STRINGS can never become citable
    numbers.

    The honesty counters that ride on the shipped labor and margin blocks — the
    uncosted-time second count and the incomplete-reason list — are deliberately
    left out: D-01 guarantees both are empty for an analyzed project, so either one
    would only ship a citable zero waiting to be fabricated against.
    """
    return {
        **_cost_block(inputs.figures, _labor_cost(inputs.blocks)),
        **_context_block(inputs.figures, inputs.blocks, inputs.buckets),
        **_signal_block(inputs.candidate),
    }


def _cost_block(figures: ProjectFinancialFigures, labor_cost: Decimal) -> dict[str, object]:
    """The headline money block, copied verbatim off the shipped figures."""
    margin = figures.margin
    return {
        "project_name": figures.name,
        "project_status": figures.status,
        "cost": figures.cost,
        "revenue": margin.revenue,
        "revenue_basis": margin.revenue_basis,
        "quoted_revenue_share": figures.quoted_revenue,
        "margin": margin.margin,
        "margin_percent": margin.margin_percent,
        "labor_basis": LABOR_BASIS_UNBURDENED,
        "labor_cost": labor_cost,
    }


def _context_block(
    figures: ProjectFinancialFigures,
    blocks: ProjectCostBlocks,
    buckets: Sequence[TrendBucket],
) -> dict[str, object]:
    """Where the money went, what was budgeted for it, and where the margin is heading."""
    return {
        "categories": _category_rows(blocks.breakdown.categories),
        "budgets": _budget_rows(figures.budgets),
        "trend": _trend_rows(buckets),
    }


def _signal_block(candidate: CandidateSignal) -> dict[str, object]:
    """One named field per citable delta; an absent signal carries None, never a 0."""
    gap = candidate.quote_gap
    return {
        "signal": candidate.signal,
        "severity_band": candidate.band,
        "negative_margin_dollars": candidate.negative_margin_dollars,
        "margin_decline_points": candidate.margin_decline_points,
        "quote_gap_points": None if gap is None else gap.points,
        "billed_margin_percent": None if gap is None else gap.billed_margin_percent,
        "quote_implied_margin_percent": None if gap is None else gap.quote_implied_margin_percent,
        "over_quote_dollars": None if gap is None else gap.over_quote_dollars,
    }


def _category_rows(categories: Sequence[CategoryTotal]) -> list[PayloadRow]:
    """One aggregate per cost category — never the entries behind it."""
    return [{"name": category.category_name, "cost": category.total} for category in categories]


def _budget_rows(budgets: Sequence[AnchoredBudget]) -> list[PayloadRow]:
    """Each budget anchor with its usage precomputed, so the AI derives no percent."""
    return [
        {
            "label": budget.label,
            "spent": budget.spent,
            "total": budget.total,
            "percent_used": percent_used(budget.spent, budget.total),
            "remaining": budget.total - budget.spent,
        }
        for budget in budgets
    ]


def _trend_rows(buckets: Sequence[TrendBucket]) -> list[PayloadRow]:
    """The last cumulative months, the same unsliced buckets detection compared."""
    return [
        {
            "month": bucket.month,
            "cost": bucket.cost,
            "margin_percent": bucket.margin.margin_percent,
        }
        for bucket in buckets[-TREND_PAYLOAD_BUCKETS:]
    ]


def _labor_cost(blocks: ProjectCostBlocks) -> Decimal:
    """The project's derived labor total, legacy labor-category entries folded in."""
    labor = blocks.breakdown.labor
    return ZERO_MONEY if labor is None else labor.total
