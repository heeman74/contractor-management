"""Deterministic margin-erosion detection for the AI profitability analysis (FINAI-01).

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no repositories.
It invents no margin arithmetic of its own — every percent comes from the shipped
`margin_math` functions. What is new here is only WHICH projects the AI may look at
(D-01), WHICH of them are candidates (D-03), what severity band a candidate sits in,
and what fingerprint it carries (D-06).

D-02 draws the line: detection is deterministic and unit-testable, and the AI adds
judgment and phrasing on top of it — never the detection itself. So every threshold
and every band boundary below is a named, tunable `Decimal` and lives here alone.
"""

from __future__ import annotations

from collections.abc import Sequence
from decimal import Decimal
from enum import StrEnum

from app.features.finance.labor_derivation import ZERO_MONEY
from app.features.finance.portfolio_math import ProjectFinancialFigures
from app.features.finance.trend_math import TrendBucket

PROFITABILITY_ELIGIBLE_STATUSES: tuple[str, ...] = ("active",)
"""D-01 narrows analysis to genuinely running work.

Deliberately narrower than the shared active-status tuple in `core.ai_utils`, which
also admits "planning": a project that has not started cannot have eroding margin,
and ROADMAP SC1 and D-01 both say active.
"""

MARGIN_DECLINE_POINTS = Decimal("5")
CRITICAL_DECLINE_POINTS = Decimal("10")
QUOTE_IMPLIED_GAP_POINTS = Decimal("5")
CRITICAL_QUOTE_GAP_POINTS = Decimal("10")
TREND_LOOKBACK_BUCKETS = 2

SIGNAL_NEGATIVE_MARGIN = "negative_margin"
SIGNAL_QUOTE_GAP = "quote_gap"
SIGNAL_MARGIN_DECLINE = "margin_decline"
PRIMARY_SIGNAL_ORDER = (SIGNAL_NEGATIVE_MARGIN, SIGNAL_QUOTE_GAP, SIGNAL_MARGIN_DECLINE)
"""One candidate per project, most severe FACT first.

Keeping it to one keeps the fingerprint, the DashboardAlert and the per-company
nightly cap all counting the same thing.
"""

SEVERITY_BAND_WARNING = "warning"
SEVERITY_BAND_CRITICAL = "critical"
FINGERPRINT_TEMPLATE = "{project_id}:{signal}:{band}"


class SkipReason(StrEnum):
    """Why D-01 excludes a project from AI analysis. Logged, never alerted."""

    NOT_ACTIVE = "not_active"
    NO_REVENUE_SOURCE = "no_revenue_source"
    NO_COST_DATA = "no_cost_data"
    INCOMPLETE_DATA = "incomplete_data"


def skip_reason_for(figures: ProjectFinancialFigures) -> SkipReason | None:
    """Why D-01 excludes this project from AI analysis, or None if it qualifies."""
    if figures.status not in PROFITABILITY_ELIGIBLE_STATUSES:
        return SkipReason.NOT_ACTIVE
    if figures.revenue is None:
        return SkipReason.NO_REVENUE_SOURCE
    if figures.cost <= ZERO_MONEY:
        return SkipReason.NO_COST_DATA
    if figures.margin.incomplete:
        return SkipReason.INCOMPLETE_DATA
    return None


def margin_decline_points(buckets: Sequence[TrendBucket]) -> Decimal | None:
    """Cumulative margin-percent points lost between the last two bucket edges.

    Positive means decline. Buckets are CUMULATIVE as-of replays from project
    inception, not per-month slices (`trend_math` module docstring) — a 5-point
    swing in a cumulative percent is a genuinely large event, which is the
    noise-bounded reading D-02 asks for. Callers must pass the UNSLICED bucket
    list: trimming the trend to a chart window is a UI concern, and a UI setting
    must never change detection.

    Returns None when there is nothing to compare, or when either edge has no
    percent at all — coercing an absent percent to zero fabricates a 100-point cliff.
    """
    if len(buckets) < TREND_LOOKBACK_BUCKETS:
        return None
    latest = buckets[-1].margin.margin_percent
    prior = buckets[-TREND_LOOKBACK_BUCKETS].margin.margin_percent
    if latest is None or prior is None:
        return None
    return prior - latest


def negative_margin_dollars(figures: ProjectFinancialFigures) -> Decimal | None:
    """The project's margin when it is below zero, else None.

    Reads `margin`, never `margin_percent`: the percent is None at zero revenue
    while the margin is still a real number, and where revenue > 0 the two agree
    in sign — so the dollar figure is strictly safer.
    """
    margin = figures.margin.margin
    if margin is None or margin >= ZERO_MONEY:
        return None
    return margin
