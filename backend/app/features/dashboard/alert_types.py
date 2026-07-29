"""Every dashboard alert_type value, in one place.

The DB CHECK constraint dashboard_alerts_alert_type_check (migration 0036) and
FINANCIAL_ALERT_TYPES are both expressed here so a new alert type can never be
registered in one and forgotten in the other. DashboardAlert.__table_args__
carries the same value list a third time — see the ORM round-trip test in
tests/test_phase_36_e2e.py, which fails if the three ever drift apart.
"""

SCHEDULE_SLIP_ALERT_TYPE = "schedule_slip"
RESCHEDULING_SUGGESTION_ALERT_TYPE = "rescheduling_suggestion"
DEPENDENCY_RISK_ALERT_TYPE = "dependency_risk"
BUDGET_WARNING_ALERT_TYPE = "budget_warning"
BUDGET_OVERRUN_ALERT_TYPE = "budget_overrun"
AI_PROFITABILITY_ALERT_TYPE = "ai_profitability"

# Alert types visible only to finance.view holders (Phase 30 D-11 filter).
FINANCIAL_ALERT_TYPES: frozenset[str] = frozenset(
    {BUDGET_WARNING_ALERT_TYPE, BUDGET_OVERRUN_ALERT_TYPE, AI_PROFITABILITY_ALERT_TYPE}
)
