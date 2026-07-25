"""Pydantic schemas for the finance domain.

Create schemas validate incoming request data with XOR anchor validators mirroring
QuoteCreate.validate_fields (app/features/quotes/schemas.py). No response schemas or
CRUD layer ship in this phase — see 30-02-PLAN.md.

IMPORTANT ASYMMETRY: CostEntryCreate anchors on job_id/trade_scope_id (D-04);
BudgetCreate anchors on project_id/trade_scope_id (D-09) — do not conflate the two.
"""

import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator

# ---------------------------------------------------------------------------
# Cost entry schemas
# ---------------------------------------------------------------------------


class CostEntryCreate(BaseModel):
    """Schema for creating a cost entry anchored to a job or a trade scope.

    Either job_id or trade_scope_id must be provided (not both None, not both set).
    """

    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    category_id: uuid.UUID
    amount: Decimal = Field(..., gt=0, decimal_places=2)
    incurred_date: date
    vendor: str | None = Field(default=None, max_length=200)
    note: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def validate_fields(self) -> "CostEntryCreate":
        """Validate job/scope anchor linkage."""
        if self.job_id is None and self.trade_scope_id is None:
            raise ValueError("Either job_id or trade_scope_id must be provided")
        if self.job_id is not None and self.trade_scope_id is not None:
            raise ValueError("Provide only one of job_id or trade_scope_id")
        return self


# ---------------------------------------------------------------------------
# Budget schemas
# ---------------------------------------------------------------------------


class BudgetCategoryBreakdownCreate(BaseModel):
    """Schema for a single per-category allocation within a budget."""

    category_id: uuid.UUID
    amount: Decimal = Field(..., ge=0, decimal_places=2)


class BudgetCreate(BaseModel):
    """Schema for creating a budget anchored to a project or a trade scope.

    Either project_id or trade_scope_id must be provided (not both None, not both
    set). category_breakdowns amounts may not sum to more than total.
    """

    project_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    total: Decimal = Field(..., ge=0, decimal_places=2)
    category_breakdowns: list[BudgetCategoryBreakdownCreate] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_fields(self) -> "BudgetCreate":
        """Validate project/scope anchor linkage and breakdown-sum consistency."""
        if self.project_id is None and self.trade_scope_id is None:
            raise ValueError("Either project_id or trade_scope_id must be provided")
        if self.project_id is not None and self.trade_scope_id is not None:
            raise ValueError("Provide only one of project_id or trade_scope_id")
        breakdown_total = sum((b.amount for b in self.category_breakdowns), Decimal("0"))
        if breakdown_total > self.total:
            raise ValueError("Category breakdown amounts cannot exceed the total budget")
        return self
