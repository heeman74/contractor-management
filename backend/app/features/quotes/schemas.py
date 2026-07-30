"""Pydantic schemas for the quotes domain.

Create/Update schemas validate incoming request data.
Response schemas inherit BaseResponseSchema and include computed totals.

Computed fields on QuoteResponse:
- subtotal: sum(quantity * unit_price) across all non-deleted line items
- discount_amount: derived from discount_type + discount_value applied to subtotal
- tax_amount: tax_rate % applied to (subtotal - discount_amount)
- total: subtotal - discount_amount + tax_amount
"""

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.base_schemas import BaseResponseSchema
from app.features.finance.margin_math import (
    DocumentAmounts,
    discount_for,
    document_total,
    tax_for,
)

# ---------------------------------------------------------------------------
# Line item schemas
# ---------------------------------------------------------------------------


class QuoteLineItemCreate(BaseModel):
    """Schema for creating or reconciling a single quote line item.

    `id` is how the reconcile in QuoteService._reconcile_line_items matches this
    entry to a stored row — omit it (or send an id the quote doesn't have) to
    insert a new row. `review_state` is the client's requested state; the server
    derives the actual stored state (see review_state_after in service.py) and
    may override it. Deliberately absent: the AI-provenance flag, `confidence_band`,
    `basis`, `suggested_at` — those are server-owned, so a client can never
    claim AI provenance for a line it submits.
    """

    id: uuid.UUID | None = None
    item_type: Literal["labor", "material"]
    description: str = Field(..., min_length=1, max_length=500)
    quantity: Decimal = Field(..., gt=0, decimal_places=3)
    unit: str = Field(..., min_length=1, max_length=50)
    unit_price: Decimal = Field(..., ge=0, decimal_places=2)
    sort_order: int = Field(default=0, ge=0)
    # Trade/field grouping for project-level quotes (one job per field on approval).
    field: str | None = Field(default=None, max_length=100)
    review_state: Literal["unreviewed", "accepted", "edited"] | None = None


class QuoteLineItemResponse(BaseResponseSchema):
    """Response schema for a single quote line item."""

    quote_id: uuid.UUID
    item_type: str
    description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    sort_order: int
    field: str | None = None
    ai_origin: bool
    review_state: str
    confidence_band: str | None = None
    basis: str | None = None

    @property
    def line_total(self) -> Decimal:
        """Subtotal for this line item."""
        return self.quantity * self.unit_price


# ---------------------------------------------------------------------------
# Quote schemas
# ---------------------------------------------------------------------------


class QuoteCreate(BaseModel):
    """Schema for creating a new quote.

    A quote attaches to exactly one of: a job (job_id), a trade scope
    (trade_scope_id), or — when both are omitted — the project level. A
    project-level quote covers a whole project and, on approval, creates that
    project with one job per line-item `field`. `title` names that project.
    Phase 25: trade_scope_id enables per-trade quoting.
    """

    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    title: str | None = Field(default=None, max_length=200)
    tax_rate: Decimal = Field(default=Decimal("0"), ge=0, le=100, decimal_places=2)
    discount_type: Literal["percent", "fixed"] | None = None
    discount_value: Decimal = Field(default=Decimal("0"), ge=0, decimal_places=2)
    expiry_date: date | None = None
    admin_notes: str | None = Field(default=None, max_length=2000)
    line_items: list[QuoteLineItemCreate] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_fields(self) -> "QuoteCreate":
        """Validate job/scope linkage and discount consistency.

        job_id and trade_scope_id are mutually exclusive; omitting both makes a
        project-level quote.
        """
        if self.job_id is not None and self.trade_scope_id is not None:
            raise ValueError("A quote cannot attach to both a job and a trade scope")
        if self.discount_value > 0 and self.discount_type is None:
            raise ValueError("discount_type is required when discount_value is set")
        if self.discount_type == "percent" and self.discount_value > 100:
            raise ValueError("Percent discount cannot exceed 100")
        return self


class QuoteUpdate(BaseModel):
    """Schema for updating an existing draft quote.

    Line items are reconciled by `id`, not replaced wholesale: a submitted item
    matching a stored row's id updates it in place, an item with no id (or an
    id the quote doesn't carry) is inserted as new, and any stored row whose id
    is absent from the submitted list is deleted.
    """

    tax_rate: Decimal | None = Field(default=None, ge=0, le=100, decimal_places=2)
    discount_type: Literal["percent", "fixed"] | None = None
    discount_value: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    expiry_date: date | None = None
    admin_notes: str | None = Field(default=None, max_length=2000)
    line_items: list[QuoteLineItemCreate] | None = None

    @model_validator(mode="after")
    def validate_discount(self) -> "QuoteUpdate":
        """Validate discount consistency if both fields present."""
        if (
            self.discount_value is not None
            and self.discount_value > 0
            and self.discount_type is None
        ):
            raise ValueError("discount_type is required when discount_value is set")
        if (
            self.discount_type == "percent"
            and self.discount_value is not None
            and self.discount_value > 100
        ):
            raise ValueError("Percent discount cannot exceed 100")
        return self


class DeclineQuoteRequest(BaseModel):
    """Schema for client declining a sent quote."""

    reason: str = Field(..., min_length=1, max_length=200)
    detail: str | None = Field(default=None, max_length=1000)


class QuoteResponse(BaseResponseSchema):
    """Full quote response including all audit fields and computed totals."""

    company_id: uuid.UUID
    job_id: uuid.UUID | None
    trade_scope_id: uuid.UUID | None = None
    title: str | None = None
    project_id: uuid.UUID | None = None
    status: str
    revision_number: int
    tax_rate: Decimal
    discount_type: str | None
    discount_value: Decimal
    expiry_date: date | None
    sent_at: datetime | None
    viewed_at: datetime | None
    approved_at: datetime | None
    declined_at: datetime | None
    decline_reason: str | None
    decline_detail: str | None
    admin_notes: str | None
    line_items: list[QuoteLineItemResponse] = Field(default_factory=list)

    # Computed financial totals
    subtotal: Decimal = Decimal("0")
    discount_amount: Decimal = Decimal("0")
    tax_amount: Decimal = Decimal("0")
    total: Decimal = Decimal("0")

    @field_validator("subtotal", "discount_amount", "tax_amount", "total", mode="before")
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        """Ensure computed totals are Decimal."""
        return Decimal(str(v)) if v is not None else Decimal("0")

    @classmethod
    def from_orm_with_totals(
        cls, quote: object, *, include_finance: bool = True
    ) -> "QuoteResponse":
        """Build response from ORM instance, computing financial totals inline.

        Usage: QuoteResponse.from_orm_with_totals(quote)
        Requires quote.line_items to be eagerly loaded.

        `include_finance=False` (Phase 30 D-06: a caller without finance.view)
        nulls each line item's confidence_band and basis server-side — the
        client must never receive data it is expected to hide.
        """
        obj = cls.model_validate(quote)

        if not include_finance:
            for item in obj.line_items:
                item.confidence_band = None
                item.basis = None

        subtotal = sum(
            (item.quantity * item.unit_price for item in obj.line_items),
            Decimal("0"),
        )
        amounts = DocumentAmounts(
            subtotal=subtotal,
            discount_type=obj.discount_type,
            discount_value=obj.discount_value,
            tax_rate=obj.tax_rate,
        )
        obj.subtotal = subtotal
        obj.discount_amount = discount_for(amounts)
        obj.tax_amount = tax_for(amounts)
        obj.total = document_total(amounts)
        return obj


# ---------------------------------------------------------------------------
# Quote template schemas
# ---------------------------------------------------------------------------


class QuoteTemplateLineItemDef(BaseModel):
    """A line item definition stored inside quote_templates.line_items_json."""

    item_type: Literal["labor", "material"]
    description: str = Field(..., min_length=1, max_length=500)
    quantity: Decimal = Field(..., gt=0, decimal_places=3)
    unit: str = Field(..., min_length=1, max_length=50)
    unit_price: Decimal = Field(..., ge=0, decimal_places=2)
    sort_order: int = Field(default=0, ge=0)


class QuoteTemplateCreate(BaseModel):
    """Schema for creating a new quote template."""

    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=500)
    line_items: list[QuoteTemplateLineItemDef] = Field(default_factory=list)
    tax_rate: Decimal = Field(default=Decimal("0"), ge=0, le=100, decimal_places=2)


class QuoteTemplateResponse(BaseResponseSchema):
    """Response schema for a quote template."""

    company_id: uuid.UUID
    name: str
    description: str | None
    line_items_json: str
    tax_rate: Decimal
