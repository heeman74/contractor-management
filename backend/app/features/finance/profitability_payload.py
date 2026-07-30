"""The CLOSED value set an AI profitability finding may cite (FINAI-01, D-05).

Pure assembly: no DB, no Claude, no service. Everything here runs on rows the
caller already fetched, which is what lets the payload shape be unit-tested
without a session and reused by a second AI feature without dragging the nightly
run in behind it.

The closure property is the whole point. `collect_allowed_values` in
`core.ai_grounding` walks whatever this module returns and every Decimal it finds
becomes citable — so a figure that is NOT a named field here is a figure the model
cannot use, and validation stays pure set membership instead of a search for
derivable arithmetic.

Decision IDs (D-nn), success criteria (SCn) and requirement tags (FINAI-nn) used
below resolve in .planning/phases/36-ai-profitability-analysis/36-CONTEXT.md.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.features.finance.budget_math import percent_used
from app.features.finance.labor_derivation import ZERO_MONEY
from app.features.finance.portfolio_math import AnchoredBudget, ProjectFinancialFigures
from app.features.finance.portfolio_service import ProjectCostBlocks
from app.features.finance.profitability_math import CandidateSignal
from app.features.finance.schemas import CategoryTotal
from app.features.finance.trend_math import TrendBucket

LABOR_BASIS_UNBURDENED = "unburdened"
"""D-06: v4.0 labor cost is wage-only, so the basis travels with the payload and
the finding can never present an unburdened figure as a fully loaded one."""

TREND_PAYLOAD_BUCKETS = 2

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

    @property
    def project_id(self) -> uuid.UUID:
        """The project this candidate speaks for — the detection signal owns the id."""
        return self.candidate.project_id


@dataclass(frozen=True)
class PayloadInputs:
    """Everything one project's payload is assembled from — all already fetched."""

    figures: ProjectFinancialFigures
    candidate: CandidateSignal
    blocks: ProjectCostBlocks
    buckets: Sequence[TrendBucket]


def build_candidate(inputs: PayloadInputs) -> ProfitabilityCandidate:
    """Wrap one fired candidate with the finding metadata and payload its row carries."""
    labor_cost = _labor_cost(inputs.blocks)
    return ProfitabilityCandidate(
        candidate=inputs.candidate,
        project_name=inputs.figures.name,
        revenue_basis=inputs.figures.margin.revenue_basis,
        labor_included=labor_cost > ZERO_MONEY,
        payload=_build_payload(inputs),
    )


def payload_turn(payload: Mapping[str, object]) -> dict[str, str]:
    """The candidate's payload as the opening user turn.

    default=str renders Decimals as exact strings for the model to read; the
    validator still compares against the original Decimal objects, so no figure
    changes representation on the way to the API.
    """
    return {"role": "user", "content": json.dumps(payload, default=str)}


def jsonb_payload(payload: Mapping[str, object]) -> dict:
    """The payload as JSONB-safe data, Decimals rendered as exact strings.

    The SC3 audit trail must stay re-readable, so every figure the finding was
    validated against is stored verbatim rather than as a lossy float.
    """
    return json.loads(json.dumps(payload, default=str))


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
