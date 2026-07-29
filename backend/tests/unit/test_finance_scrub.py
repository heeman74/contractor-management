"""Unit tests for the finance-scrub helper and the financial-alert-set contract.

Pure unit tests — no DB, no fixtures. Covers FINSEC-04 shared plumbing:
scrub_finance_fields (app.core.finance_scrub) and the budget-alert-type
FINANCIAL_ALERT_TYPES contract (app.features.dashboard.service).
"""

from __future__ import annotations

from app.core.finance_scrub import FINANCE_FIELD_NAMES, scrub_finance_fields
from app.features.dashboard.service import FINANCIAL_ALERT_TYPES


def test_scrub_is_noop_with_access() -> None:
    context = {"cost": 5, "margin": 0.2, "title": "x"}

    result = scrub_finance_fields(context, has_finance_access=True)

    assert result == context


def test_scrub_removes_finance_keys_without_access() -> None:
    context = {"cost": 5, "margin": 0.2, "title": "x"}

    result = scrub_finance_fields(context, has_finance_access=False)

    assert result == {"title": "x"}


def test_scrub_removes_every_declared_finance_field() -> None:
    context = {field: object() for field in FINANCE_FIELD_NAMES}
    context["safe_key"] = "keep me"

    result = scrub_finance_fields(context, has_finance_access=False)

    assert result == {"safe_key": "keep me"}


def test_scrub_does_not_mutate_input() -> None:
    context = {"cost": 5, "title": "x"}
    original = dict(context)

    scrub_finance_fields(context, has_finance_access=False)

    assert context == original


def test_financial_alert_types_are_the_budget_types() -> None:
    # Phase 34 registered the two budget alert types as financial and Phase 36 added
    # ai_profitability — the D-11 permission filter drops all of them for callers
    # without finance.view. Asserted as a subset, not equality: every future financial
    # alert type must be dropped by the same filter, so a new registration should
    # extend this set rather than break this test.
    assert {"budget_warning", "budget_overrun", "ai_profitability"} <= FINANCIAL_ALERT_TYPES
