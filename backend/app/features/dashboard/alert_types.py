"""Every dashboard alert_type value, in one place.

The DB CHECK constraint dashboard_alerts_alert_type_check (migration 0035) and
FINANCIAL_ALERT_TYPES are both expressed here so a new alert type can never be
registered in one and forgotten in the other.
"""

SCHEDULE_SLIP_ALERT_TYPE = "schedule_slip"
RESCHEDULING_SUGGESTION_ALERT_TYPE = "rescheduling_suggestion"
DEPENDENCY_RISK_ALERT_TYPE = "dependency_risk"
BUDGET_WARNING_ALERT_TYPE = "budget_warning"
BUDGET_OVERRUN_ALERT_TYPE = "budget_overrun"

# Alert types visible only to finance.view holders (Phase 30 D-11 filter).
FINANCIAL_ALERT_TYPES: frozenset[str] = frozenset(
    {BUDGET_WARNING_ALERT_TYPE, BUDGET_OVERRUN_ALERT_TYPE}
)
