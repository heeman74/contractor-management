"""Pydantic schemas for the finance domain.

Create schemas validate incoming request data with XOR anchor validators mirroring
QuoteCreate.validate_fields (app/features/quotes/schemas.py). Response/update schemas
for the cost-entry CRUD layer (Plan 31-01) live here too — no custom Decimal
serializer needed, `amount: Decimal` auto-serializes to a JSON string.

IMPORTANT ASYMMETRY: CostEntryCreate anchors on job_id/trade_scope_id (D-04);
BudgetCreate anchors on project_id/trade_scope_id (D-09) — do not conflate the two.
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel, Field, model_validator

from app.core.base_schemas import BaseResponseSchema
from app.features.finance.margin_math import MarginFigures

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
    def validate_fields(self) -> CostEntryCreate:
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


# ---------------------------------------------------------------------------
# Cost breakdown schemas (COST-06)
# ---------------------------------------------------------------------------


class CategoryTotal(BaseModel):
    """One cost category's summed amount within a breakdown."""

    category_id: uuid.UUID
    category_name: str
    total: Decimal


class LaborCostSummary(BaseModel):
    """Derived labor cost plus the honest accounting of time that could not be costed.

    unrated_seconds is the D-05 contract: hours with no rate effective on the work
    day are reported, never silently valued at $0. Phase 33 consumes this field as
    its incomplete-data signal (MARG-03), so it stays machine-readable (seconds, int).
    basis marks the v4.0 wage-only scope for downstream consumers (D-06).
    """

    total: Decimal
    rated_seconds: int
    unrated_seconds: int
    basis: str = "unburdened"


class MarginSummary(BaseModel):
    """Revenue minus actual cost for one job, trade scope, or project (MARG-01/02/03).

    None expresses honest absence, never zero: `revenue` is None when no invoice and no
    approved quote exists (D-07), and `margin_percent` is None when revenue is absent or
    zero. `revenue_basis` is machine-readable for the UI caption and for Phase 36 AI:
    "invoiced" | "quoted" | "mixed" (project only) | "none". `incomplete_reasons` holds
    "unrated_labor" and/or "no_cost_data" (D-05); the figure is still reported alongside
    the flag, never suppressed (D-06). Decimals auto-serialize as JSON strings.
    """

    revenue: Decimal | None = None
    revenue_basis: str
    margin: Decimal | None = None
    margin_percent: Decimal | None = None
    incomplete: bool = False
    incomplete_reasons: list[str] = Field(default_factory=list)


def to_margin_summary(figures: MarginFigures) -> MarginSummary:
    """Map pure math output onto the wire schema."""
    return MarginSummary(
        revenue=figures.revenue,
        revenue_basis=figures.revenue_basis,
        margin=figures.margin,
        margin_percent=figures.margin_percent,
        incomplete=figures.incomplete,
        incomplete_reasons=list(figures.incomplete_reasons),
    )


class CostBreakdownResponse(BaseModel):
    """Itemized category totals plus derived labor for one job or trade scope.

    labor is None on trade-scope breakdowns, where labor_tracked_at_job_level is
    True instead (D-07/D-08: time tracking is job-anchored in v4.0, so a trade
    scope has no labor figure — an honest note, never a $0 row).

    margin was added in Phase 33 — additive only: mobile parses total/entries/
    categories/grand_total/labor/labor_tracked_at_job_level strictly, so the
    existing fields never change shape.
    """

    categories: list[CategoryTotal] = Field(default_factory=list)
    labor: LaborCostSummary | None = None
    labor_tracked_at_job_level: bool = False
    grand_total: Decimal
    margin: MarginSummary | None = None
    # Added in Phase 34 — additive only: mobile parses it tolerantly while the
    # existing keys stay strict. None means "no active budget at this anchor".
    budget: BudgetVsActual | None = None


class ProjectCostRollupResponse(BaseModel):
    """Response schema for a project's cost rollup (D-02/D-05).

    total = trade-scope-anchored costs + costs on jobs whose project_id = project.

    margin was added in Phase 33 — additive only: mobile parses total/entries/
    categories/grand_total/labor strictly, so the existing fields never change shape.
    """

    project_id: uuid.UUID
    total: Decimal
    entries: list[CostEntryResponse] = Field(default_factory=list)
    # Added in Phase 32 — additive only: mobile's fetchProjectRollup parses
    # total/entries strictly and throws FormatException on shape changes.
    categories: list[CategoryTotal] = Field(default_factory=list)
    labor: LaborCostSummary | None = None
    grand_total: Decimal | None = None
    margin: MarginSummary | None = None
    # Added in Phase 34 — additive only: mobile parses it tolerantly while the
    # existing keys stay strict. None means "no active budget for this project".
    budget: BudgetVsActual | None = None


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
    set). category_breakdowns amounts may not sum to more than total. total must
    be strictly positive (D-10), mirroring the budgets_total_positive_check DB
    constraint from migration 0035.
    """

    project_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    total: Decimal = Field(..., gt=0, decimal_places=2)
    category_breakdowns: list[BudgetCategoryBreakdownCreate] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_fields(self) -> BudgetCreate:
        """Validate project/scope anchor linkage and breakdown-sum consistency."""
        if self.project_id is None and self.trade_scope_id is None:
            raise ValueError("Either project_id or trade_scope_id must be provided")
        if self.project_id is not None and self.trade_scope_id is not None:
            raise ValueError("Provide only one of project_id or trade_scope_id")
        breakdown_total = sum((b.amount for b in self.category_breakdowns), Decimal("0"))
        if breakdown_total > self.total:
            raise ValueError("Category breakdown amounts cannot exceed the total budget")
        return self


class BudgetUpdate(BaseModel):
    """Edit a budget's total. Any positive amount is allowed — including below
    current spend (D-10, no floor); the next evaluation fires the crossed
    thresholds, which is honest. Raising the total re-arms both thresholds (D-03).
    The per-category breakdown stays dormant in v4.0 (D-11), so total is the
    only editable field."""

    total: Decimal = Field(..., gt=0, decimal_places=2)


class BudgetResponse(BaseResponseSchema):
    """One budget row. Exactly one of project_id / trade_scope_id is set."""

    project_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    total: Decimal


class BudgetVsActual(BaseModel):
    """Budgeted vs spent vs remaining for one project or trade-scope budget.

    Embedded additively on the trade-scope cost breakdown and the project cost
    rollup (never on a job breakdown — budgets anchor project/scope only).
    `spent` is the same figure as that response's grand_total by construction.
    `remaining` goes negative when over budget (honest, D-10). `percent_used`
    is supplied by the backend at one decimal so no client ever re-derives a
    percent from a float division."""

    budget_id: uuid.UUID
    total: Decimal
    spent: Decimal
    remaining: Decimal
    percent_used: Decimal


# ---------------------------------------------------------------------------
# Labor rate schemas
# ---------------------------------------------------------------------------


class LaborRateCreate(BaseModel):
    """Schema for appending an effective-dated hourly cost rate for a worker.

    Append-only (D-01/D-02): there is no update or delete schema. Corrections are
    made by adding a new row — backdate effective_from to fill in past work days,
    or re-enter the same effective_from with the right amount (latest created_at wins).
    Past, today, and future effective_from values are all valid.
    """

    user_id: uuid.UUID
    hourly_cost: Decimal = Field(..., gt=0, decimal_places=2, lt=Decimal("100000"))
    effective_from: date


class LaborRateResponse(BaseResponseSchema):
    """Response schema for one labor-rate row. hourly_cost auto-serializes as a string."""

    user_id: uuid.UUID
    hourly_cost: Decimal
    effective_from: date
