"""Unit tests for the finance-scrub helper and the empty-alert-set contract.

Pure unit tests — no DB, no fixtures. Covers FINSEC-04 shared plumbing:
scrub_finance_fields (app.core.finance_scrub) and the currently-empty
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


def test_financial_alert_types_currently_empty() -> None:
    # Documents the "inert today" contract; Phase 36 updates this test when it
    # populates FINANCIAL_ALERT_TYPES with real financial alert types.
    assert frozenset() == FINANCIAL_ALERT_TYPES
