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

# ---------------------------------------------------------------------------
# Line item schemas
# ---------------------------------------------------------------------------


class QuoteLineItemCreate(BaseModel):
    """Schema for creating a single quote line item."""

    item_type: Literal["labor", "material"]
    description: str = Field(..., min_length=1, max_length=500)
    quantity: Decimal = Field(..., gt=0, decimal_places=3)
    unit: str = Field(..., min_length=1, max_length=50)
    unit_price: Decimal = Field(..., ge=0, decimal_places=2)
    sort_order: int = Field(default=0, ge=0)


class QuoteLineItemResponse(BaseResponseSchema):
    """Response schema for a single quote line item."""

    quote_id: uuid.UUID
    item_type: str
    description: str
    quantity: Decimal
    unit: str
    unit_price: Decimal
    sort_order: int

    @property
    def line_total(self) -> Decimal:
        """Subtotal for this line item."""
        return self.quantity * self.unit_price


# ---------------------------------------------------------------------------
# Quote schemas
# ---------------------------------------------------------------------------


class QuoteCreate(BaseModel):
    """Schema for creating a new quote on a job."""

    job_id: uuid.UUID
    tax_rate: Decimal = Field(default=Decimal("0"), ge=0, le=100, decimal_places=2)
    discount_type: Literal["percent", "fixed"] | None = None
    discount_value: Decimal = Field(default=Decimal("0"), ge=0, decimal_places=2)
    expiry_date: date | None = None
    admin_notes: str | None = Field(default=None, max_length=2000)
    line_items: list[QuoteLineItemCreate] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_discount(self) -> "QuoteCreate":
        """If discount_value > 0, discount_type must be set."""
        if self.discount_value > 0 and self.discount_type is None:
            raise ValueError("discount_type is required when discount_value is set")
        if self.discount_type == "percent" and self.discount_value > 100:
            raise ValueError("Percent discount cannot exceed 100")
        return self


class QuoteUpdate(BaseModel):
    """Schema for updating an existing draft quote.

    Line items are fully replaced on update — pass the complete new list.
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
    job_id: uuid.UUID
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
    def from_orm_with_totals(cls, quote: object) -> "QuoteResponse":
        """Build response from ORM instance, computing financial totals inline.

        Usage: QuoteResponse.from_orm_with_totals(quote)
        Requires quote.line_items to be eagerly loaded.
        """
        obj = cls.model_validate(quote)

        # Subtotal — sum of all line items (soft-deleted items excluded at query layer)
        subtotal = sum(
            (item.quantity * item.unit_price for item in obj.line_items),
            Decimal("0"),
        )

        # Discount
        if obj.discount_type == "percent":
            discount_amount = (subtotal * obj.discount_value / Decimal("100")).quantize(
                Decimal("0.01")
            )
        elif obj.discount_type == "fixed":
            discount_amount = min(obj.discount_value, subtotal)
        else:
            discount_amount = Decimal("0")

        # Tax on discounted subtotal
        taxable = subtotal - discount_amount
        tax_amount = (taxable * obj.tax_rate / Decimal("100")).quantize(Decimal("0.01"))
        total = taxable + tax_amount

        obj.subtotal = subtotal
        obj.discount_amount = discount_amount
        obj.tax_amount = tax_amount
        obj.total = total
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
