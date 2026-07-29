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
from app.features.finance.labor_derivation import ZERO_MONEY
from app.features.finance.margin_math import RevenueAnchor, anchor_revenues
from app.features.finance.portfolio_math import ProjectFinancialFigures
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
from app.features.finance.service import contributing_anchor_cost

logger = get_logger(__name__)

SKIP_LOG_TEMPLATE = "ai_profitability: skipped project=%s reason=%s"
SCAN_SUMMARY_LOG_TEMPLATE = "ai_profitability: company=%s analyzed=%d candidates=%d skipped=%d"

type SkippedProject = tuple[uuid.UUID, SkipReason]


@dataclass(frozen=True)
class ProfitabilityCandidate:
    """One project that reached the AI: its candidate signal and the finding metadata.

    `revenue_basis` and `labor_included` are the two honesty columns every finding
    row carries, so the UI can caption an estimate-backed or wage-only figure
    without re-deriving either from the payload.
    """

    candidate: CandidateSignal
    project_name: str
    revenue_basis: str
    labor_included: bool


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
            SCAN_SUMMARY_LOG_TEMPLATE,
            company_id,
            len(eligible),
            len(candidates),
            len(skipped),
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
            logger.info(SKIP_LOG_TEMPLATE, project_id, reason.value)

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
        return _to_profitability_candidate(figures, candidate, blocks, buckets)

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


def _to_profitability_candidate(
    figures: ProjectFinancialFigures, candidate: CandidateSignal, blocks: ProjectCostBlocks
) -> ProfitabilityCandidate:
    """Wrap one fired candidate with the finding metadata its row will carry."""
    return ProfitabilityCandidate(
        candidate=candidate,
        project_name=figures.name,
        revenue_basis=figures.margin.revenue_basis,
        labor_included=_labor_cost(blocks) > ZERO_MONEY,
    )


def _labor_cost(blocks: ProjectCostBlocks) -> Decimal:
    """The project's derived labor total, legacy labor-category entries folded in."""
    labor = blocks.breakdown.labor
    return ZERO_MONEY if labor is None else labor.total
