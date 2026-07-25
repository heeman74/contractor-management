"""Finance-field scrubbing helper for AI tool/prompt context.

Shared plumbing for FINSEC-04: any AI dict-builder that assembles context for
Claude (checklists, dashboard alerts, future profitability/quote features)
should strip finance-only keys when the caller lacks finance.view access.

Not yet wired into any dict-builder — no dict-builder emits finance fields
today (see 30-RESEARCH.md Open Question 3). Phase 34/36 wire this in once
cost/margin data flows into AI context.
"""

from __future__ import annotations

FINANCE_FIELD_NAMES: frozenset[str] = frozenset(
    {
        "cost",
        "actual_cost",
        "margin",
        "margin_pct",
        "budget",
        "budget_status",
        "hourly_cost",
        "hourly_rate",
        "labor_cost",
    }
)


def scrub_finance_fields(context: dict[str, object], has_finance_access: bool) -> dict[str, object]:
    """Strip finance-only keys from a plain dict before it enters an AI prompt or tool result.

    No-op when has_finance_access is True. Shallow — callers with nested dicts/lists
    must recurse or flatten before calling this (documented, not silently handled,
    to keep this function small per CLAUDE.md's clean-code rules).
    """
    if has_finance_access:
        return context
    return {k: v for k, v in context.items() if k not in FINANCE_FIELD_NAMES}
