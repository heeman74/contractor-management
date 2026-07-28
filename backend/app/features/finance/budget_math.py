"""Pure threshold, percent-used, and alert-copy math for budgets (BUDG-03).

This module is deliberately DB-free: no SQLAlchemy, no FastAPI, no I/O — it
mirrors margin_math.py in spirit and layout. Every threshold comparison and
every locked alert string in Phase 34 lives here and nowhere else.

All math is pure Decimal (RESEARCH Pitfall 8). The four alert templates are
copied verbatim from the 34-UI-SPEC Copywriting Contract — em dash, trailing
period, and " scope" after the trade name included — and tests assert them
byte-for-byte.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from enum import StrEnum

from app.features.finance.labor_derivation import CENTS
from app.features.finance.margin_math import PERCENT_MULTIPLIER

WARNING_THRESHOLD_RATIO = Decimal("0.80")
OVERRUN_THRESHOLD_RATIO = Decimal("1.00")
PERCENT_QUANTUM = Decimal("0.1")

BUDGET_WARNING_PUSH_TITLE = "Budget warning"
BUDGET_OVERRUN_PUSH_TITLE = "Budget exceeded"

_WHOLE_DOLLAR_CENTS_SUFFIX = ".00"
_WHOLE_PERCENT_SUFFIX = ".0"

_SCOPE_WARNING_TEMPLATE = (
    "{project} — {trade} scope has spent {spent} of its {budget} budget ({percent}%)."
)
_PROJECT_WARNING_TEMPLATE = "{project} has spent {spent} of its {budget} budget ({percent}%)."
_SCOPE_OVERRUN_TEMPLATE = (
    "{project} — {trade} scope has exceeded its {budget} budget — {spent} spent ({percent}%)."
)
_PROJECT_OVERRUN_TEMPLATE = (
    "{project} has exceeded its {budget} budget — {spent} spent ({percent}%)."
)


class BudgetThreshold(StrEnum):
    """The two budget alert tiers, in firing order."""

    warning = "warning"
    overrun = "overrun"


_THRESHOLD_RATIOS: tuple[tuple[BudgetThreshold, Decimal], ...] = (
    (BudgetThreshold.warning, WARNING_THRESHOLD_RATIO),
    (BudgetThreshold.overrun, OVERRUN_THRESHOLD_RATIO),
)

_PUSH_TITLES: dict[BudgetThreshold, str] = {
    BudgetThreshold.warning: BUDGET_WARNING_PUSH_TITLE,
    BudgetThreshold.overrun: BUDGET_OVERRUN_PUSH_TITLE,
}


@dataclass(frozen=True)
class BudgetFacts:
    """Everything one alert sentence needs. trade_name None = project budget."""

    project_name: str
    trade_name: str | None
    spent: Decimal
    total: Decimal


def percent_used(spent: Decimal, total: Decimal) -> Decimal:
    """Spend as a percent of budget, one decimal place, ROUND_HALF_UP.

    total is guaranteed > 0 by budgets_total_positive_check — no zero branch.
    """
    return (spent / total * PERCENT_MULTIPLIER).quantize(PERCENT_QUANTUM, rounding=ROUND_HALF_UP)


def crossed_thresholds(spent: Decimal, total: Decimal) -> tuple[BudgetThreshold, ...]:
    """Every threshold the spend has reached, in warning-then-overrun order."""
    return tuple(threshold for threshold, ratio in _THRESHOLD_RATIOS if spent >= total * ratio)


def format_alert_money(amount: Decimal) -> str:
    """Thousands-separated dollars with cents, trailing .00 stripped: "$8,200.50", "$10,000"."""
    return f"${amount.quantize(CENTS):,.2f}".removesuffix(_WHOLE_DOLLAR_CENTS_SUFFIX)


def format_alert_percent(percent: Decimal) -> str:
    """A percent_used figure as display text, trailing .0 dropped: "82", "82.5", "112"."""
    return str(percent).removesuffix(_WHOLE_PERCENT_SUFFIX)


def _template_for(facts: BudgetFacts, threshold: BudgetThreshold) -> str:
    """Select the locked UI-SPEC template for this scope/project + tier combination."""
    if threshold is BudgetThreshold.overrun:
        return _PROJECT_OVERRUN_TEMPLATE if facts.trade_name is None else _SCOPE_OVERRUN_TEMPLATE
    return _PROJECT_WARNING_TEMPLATE if facts.trade_name is None else _SCOPE_WARNING_TEMPLATE


def budget_alert_text(facts: BudgetFacts, threshold: BudgetThreshold) -> str:
    """The alert impact_text / FCM push body, byte-identical to the UI-SPEC copy."""
    return _template_for(facts, threshold).format(
        project=facts.project_name,
        trade=facts.trade_name,
        spent=format_alert_money(facts.spent),
        budget=format_alert_money(facts.total),
        percent=format_alert_percent(percent_used(facts.spent, facts.total)),
    )


def push_title_for(threshold: BudgetThreshold) -> str:
    """FCM push title for a threshold tier (locked by the UI-SPEC push contract)."""
    return _PUSH_TITLES[threshold]
