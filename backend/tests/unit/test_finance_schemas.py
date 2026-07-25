"""Phase 30 — Finance schema validation: unit tests for CostEntryCreate/BudgetCreate.

Pure unit tests (no DB). Cover:
- CostEntryCreate: job_id XOR trade_scope_id anchor validation, positive-amount check
- BudgetCreate: project_id XOR trade_scope_id anchor validation, breakdown-sum-vs-total
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.features.finance.schemas import (
    BudgetCategoryBreakdownCreate,
    BudgetCreate,
    CostEntryCreate,
)

# ---------------------------------------------------------------------------
# CostEntryCreate — job_id XOR trade_scope_id
# ---------------------------------------------------------------------------


def test_cost_entry_rejects_both_anchors_none():
    """CostEntryCreate rejects job_id=None and trade_scope_id=None."""
    with pytest.raises(ValidationError) as exc_info:
        CostEntryCreate(
            category_id=uuid4(),
            amount=Decimal("100.00"),
            incurred_date=date.today(),
        )
    assert "Either job_id or trade_scope_id" in str(exc_info.value)


def test_cost_entry_rejects_both_anchors_set():
    """CostEntryCreate rejects job_id and trade_scope_id both set."""
    with pytest.raises(ValidationError) as exc_info:
        CostEntryCreate(
            job_id=uuid4(),
            trade_scope_id=uuid4(),
            category_id=uuid4(),
            amount=Decimal("100.00"),
            incurred_date=date.today(),
        )
    assert "only one of job_id or trade_scope_id" in str(exc_info.value)


def test_cost_entry_accepts_job_only():
    """CostEntryCreate accepts job_id set, trade_scope_id None."""
    entry = CostEntryCreate(
        job_id=uuid4(),
        category_id=uuid4(),
        amount=Decimal("100.00"),
        incurred_date=date.today(),
    )
    assert entry.job_id is not None
    assert entry.trade_scope_id is None


def test_cost_entry_accepts_trade_scope_only():
    """CostEntryCreate accepts trade_scope_id set, job_id None."""
    entry = CostEntryCreate(
        trade_scope_id=uuid4(),
        category_id=uuid4(),
        amount=Decimal("100.00"),
        incurred_date=date.today(),
    )
    assert entry.trade_scope_id is not None
    assert entry.job_id is None


def test_cost_entry_rejects_non_positive_amount():
    """CostEntryCreate rejects amount=0 (must be > 0)."""
    with pytest.raises(ValidationError) as exc_info:
        CostEntryCreate(
            job_id=uuid4(),
            category_id=uuid4(),
            amount=Decimal("0"),
            incurred_date=date.today(),
        )
    errors = exc_info.value.errors()
    assert any("amount" in str(e["loc"]) for e in errors)


# ---------------------------------------------------------------------------
# BudgetCreate — project_id XOR trade_scope_id
# ---------------------------------------------------------------------------


def test_budget_rejects_both_anchors_none():
    """BudgetCreate rejects project_id=None and trade_scope_id=None."""
    with pytest.raises(ValidationError) as exc_info:
        BudgetCreate(total=Decimal("100.00"))
    assert "Either project_id or trade_scope_id" in str(exc_info.value)


def test_budget_rejects_both_anchors_set():
    """BudgetCreate rejects project_id and trade_scope_id both set."""
    with pytest.raises(ValidationError) as exc_info:
        BudgetCreate(
            project_id=uuid4(),
            trade_scope_id=uuid4(),
            total=Decimal("100.00"),
        )
    assert "only one of project_id or trade_scope_id" in str(exc_info.value)


def test_budget_accepts_project_only():
    """BudgetCreate accepts project_id set, trade_scope_id None."""
    budget = BudgetCreate(project_id=uuid4(), total=Decimal("100.00"))
    assert budget.project_id is not None
    assert budget.trade_scope_id is None


def test_budget_accepts_trade_scope_only():
    """BudgetCreate accepts trade_scope_id set, project_id None."""
    budget = BudgetCreate(trade_scope_id=uuid4(), total=Decimal("100.00"))
    assert budget.trade_scope_id is not None
    assert budget.project_id is None


def test_budget_rejects_breakdown_exceeding_total():
    """BudgetCreate rejects category_breakdowns summing to more than total."""
    with pytest.raises(ValidationError) as exc_info:
        BudgetCreate(
            project_id=uuid4(),
            total=Decimal("100.00"),
            category_breakdowns=[
                BudgetCategoryBreakdownCreate(category_id=uuid4(), amount=Decimal("80.00")),
                BudgetCategoryBreakdownCreate(category_id=uuid4(), amount=Decimal("70.00")),
            ],
        )
    assert "cannot exceed" in str(exc_info.value)


def test_budget_accepts_breakdown_within_total():
    """BudgetCreate accepts category_breakdowns summing to less than total."""
    budget = BudgetCreate(
        project_id=uuid4(),
        total=Decimal("100.00"),
        category_breakdowns=[
            BudgetCategoryBreakdownCreate(category_id=uuid4(), amount=Decimal("50.00")),
            BudgetCategoryBreakdownCreate(category_id=uuid4(), amount=Decimal("30.00")),
        ],
    )
    assert len(budget.category_breakdowns) == 2
