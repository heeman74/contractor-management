"""Pydantic schemas for the finance domain.

Create schemas validate incoming request data with XOR anchor validators mirroring
QuoteCreate.validate_fields (app/features/quotes/schemas.py). Response/update schemas
for the cost-entry CRUD layer (Plan 31-01) live here too — no custom Decimal
serializer needed, `amount: Decimal` auto-serializes to a JSON string.

IMPORTANT ASYMMETRY: CostEntryCreate anchors on job_id/trade_scope_id (D-04);
BudgetCreate anchors on project_id/trade_scope_id (D-09) — do not conflate the two.
"""

import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator

from app.core.base_schemas import BaseResponseSchema

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


class CostEntryUpdate(BaseModel):
    """Schema for updating an existing cost entry.

    The job_id/trade_scope_id anchor cannot be changed on update (research
    recommendation — avoids re-deriving XOR consistency and rollup-cache
    invalidation complexity). Only amount/category/date/vendor/note are editable.
    """

    category_id: uuid.UUID | None = None
    amount: Decimal | None = Field(default=None, gt=0, decimal_places=2)
    incurred_date: date | None = None
    vendor: str | None = Field(default=None, max_length=200)
    note: str | None = Field(default=None, max_length=2000)


class CostCategoryResponse(BaseResponseSchema):
    """Response schema for a cost category."""

    name: str
    is_system: bool


class CostReceiptResponse(BaseResponseSchema):
    """Response schema for a cost-entry receipt attachment."""

    cost_entry_id: uuid.UUID
    remote_url: str | None = None
    caption: str | None = None


class CostEntryResponse(BaseResponseSchema):
    """Response schema for a cost entry.

    amount is a plain Decimal field — Pydantic v2 auto-serializes it as a JSON
    string (verified: no custom field_serializer needed, mirrors quotes/invoices).
    category_name is populated by the router/service from the eager-loaded
    CostEntry.category relationship (not stored on the model itself).
    """

    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    category_id: uuid.UUID
    category_name: str | None = None
    amount: Decimal
    incurred_date: date
    vendor: str | None = None
    note: str | None = None


class ProjectCostRollupResponse(BaseModel):
    """Response schema for a project's cost rollup (D-02/D-05).

    total = trade-scope-anchored costs + costs on jobs whose project_id = project.
    """

    project_id: uuid.UUID
    total: Decimal
    entries: list[CostEntryResponse] = Field(default_factory=list)


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
