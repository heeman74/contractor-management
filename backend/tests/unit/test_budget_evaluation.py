"""Phase 34 — budget math: unit tests for thresholds, percent-used, and alert copy.

Pure unit tests — no DB, no fixtures. All money/percent math is Decimal-only
(RESEARCH Pitfall 8) and the four alert templates are locked verbatim by the
34-UI-SPEC Copywriting Contract.

This file also receives the claim/re-arm and delta unit tests in later
Phase 34 plans.
"""

from __future__ import annotations

from decimal import Decimal

from app.features.finance.budget_math import (
    BUDGET_OVERRUN_PUSH_TITLE,
    BUDGET_WARNING_PUSH_TITLE,
    BudgetFacts,
    BudgetThreshold,
    budget_alert_text,
    crossed_thresholds,
    format_alert_money,
    format_alert_percent,
    percent_used,
    push_title_for,
)

SCOPE_WARNING_FACTS = BudgetFacts(
    project_name="Riverside Remodel",
    trade_name="Plumbing",
    spent=Decimal("8200"),
    total=Decimal("10000"),
)

SCOPE_OVERRUN_FACTS = BudgetFacts(
    project_name="Riverside Remodel",
    trade_name="Plumbing",
    spent=Decimal("11200"),
    total=Decimal("10000"),
)


def _project_facts(facts: BudgetFacts) -> BudgetFacts:
    return BudgetFacts(
        project_name=facts.project_name,
        trade_name=None,
        spent=facts.spent,
        total=facts.total,
    )


# --- threshold math ---


def test_percent_used_is_one_decimal():
    assert percent_used(Decimal("8200"), Decimal("10000")) == Decimal("82.0")


def test_percent_used_keeps_a_real_half_percent():
    assert percent_used(Decimal("8250"), Decimal("10000")) == Decimal("82.5")


def test_percent_used_rounds_half_up_at_one_decimal():
    # 825 of 10000 is exactly 8.25% — the half case rounds up, not to even.
    assert percent_used(Decimal("825"), Decimal("10000")) == Decimal("8.3")


def test_no_threshold_crossed_below_eighty_percent():
    assert crossed_thresholds(Decimal("7999.99"), Decimal("10000")) == ()


def test_warning_crossed_at_exactly_eighty_percent():
    assert crossed_thresholds(Decimal("8000"), Decimal("10000")) == (BudgetThreshold.warning,)


def test_warning_only_inside_the_eighty_to_hundred_band():
    assert crossed_thresholds(Decimal("9999.99"), Decimal("10000")) == (BudgetThreshold.warning,)


def test_both_thresholds_crossed_at_exactly_one_hundred_percent():
    assert crossed_thresholds(Decimal("10000"), Decimal("10000")) == (
        BudgetThreshold.warning,
        BudgetThreshold.overrun,
    )


def test_jump_past_both_thresholds_yields_warning_then_overrun():
    assert crossed_thresholds(Decimal("12000"), Decimal("10000")) == (
        BudgetThreshold.warning,
        BudgetThreshold.overrun,
    )


# --- alert copy ---


def test_money_strips_whole_dollar_cents():
    assert format_alert_money(Decimal("8200.00")) == "$8,200"


def test_money_keeps_nonzero_cents():
    assert format_alert_money(Decimal("8200.50")) == "$8,200.50"


def test_money_uses_thousands_separators():
    assert format_alert_money(Decimal("10000")) == "$10,000"


def test_percent_string_drops_trailing_zero():
    assert format_alert_percent(Decimal("82.0")) == "82"


def test_percent_string_keeps_a_half():
    assert format_alert_percent(Decimal("82.5")) == "82.5"


def test_percent_string_over_one_hundred():
    assert format_alert_percent(Decimal("112.0")) == "112"


def test_scope_warning_text_is_the_locked_template():
    text = budget_alert_text(SCOPE_WARNING_FACTS, BudgetThreshold.warning)

    assert text == (
        "Riverside Remodel — Plumbing scope has spent $8,200 of its $10,000 budget (82%)."
    )


def test_project_warning_text_drops_the_trade_clause():
    text = budget_alert_text(_project_facts(SCOPE_WARNING_FACTS), BudgetThreshold.warning)

    assert text == "Riverside Remodel has spent $8,200 of its $10,000 budget (82%)."


def test_scope_overrun_text_is_the_locked_template():
    text = budget_alert_text(SCOPE_OVERRUN_FACTS, BudgetThreshold.overrun)

    assert text == (
        "Riverside Remodel — Plumbing scope has exceeded its $10,000 budget — $11,200 spent (112%)."
    )


def test_project_overrun_text_drops_the_trade_clause():
    text = budget_alert_text(_project_facts(SCOPE_OVERRUN_FACTS), BudgetThreshold.overrun)

    assert text == "Riverside Remodel has exceeded its $10,000 budget — $11,200 spent (112%)."


def test_push_title_per_threshold():
    assert push_title_for(BudgetThreshold.warning) == BUDGET_WARNING_PUSH_TITLE
    assert push_title_for(BudgetThreshold.overrun) == BUDGET_OVERRUN_PUSH_TITLE
    assert push_title_for(BudgetThreshold.warning) == "Budget warning"
    assert push_title_for(BudgetThreshold.overrun) == "Budget exceeded"
