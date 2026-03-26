"""Pydantic schemas for the invoices domain.

Create/Update schemas validate incoming request data.
Response schemas inherit BaseResponseSchema and include computed totals.

Computed fields on InvoiceResponse:
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


class InvoiceLineItemCreate(BaseModel):
    """Schema for creating a single invoice line item."""

    item_type: Literal["labor", "material"]
    description: str = Field(..., min_length=1, max_length=500)
    quantity: Decimal = Field(..., gt=0, decimal_places=3)
    unit: str = Field(..., min_length=1, max_length=50)
    unit_price: Decimal = Field(..., ge=0, decimal_places=2)
    sort_order: int = Field(default=0, ge=0)


class InvoiceLineItemResponse(BaseResponseSchema):
    """Response schema for a single invoice line item."""

    invoice_id: uuid.UUID
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
# Invoice schemas
# ---------------------------------------------------------------------------


class InvoiceCreate(BaseModel):
    """Schema for creating a new invoice on a job or trade scope.

    Either job_id or trade_scope_id must be provided (not both None).
    Phase 25: trade_scope_id and milestone_id enable per-trade invoicing.
    """

    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    milestone_id: uuid.UUID | None = None
    quote_id: uuid.UUID | None = None
    tax_rate: Decimal = Field(default=Decimal("0"), ge=0, le=100, decimal_places=2)
    discount_type: Literal["percent", "fixed"] | None = None
    discount_value: Decimal = Field(default=Decimal("0"), ge=0, decimal_places=2)
    due_date: date | None = None
    issued_at: datetime | None = None  # defaults to now() at service layer if omitted
    line_items: list[InvoiceLineItemCreate] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_fields(self) -> "InvoiceCreate":
        """Validate job/scope linkage and discount consistency."""
        if self.job_id is None and self.trade_scope_id is None:
            raise ValueError("Either job_id or trade_scope_id must be provided")
        if self.discount_value > 0 and self.discount_type is None:
            raise ValueError("discount_type is required when discount_value is set")
        if self.discount_type == "percent" and self.discount_value > 100:
            raise ValueError("Percent discount cannot exceed 100")
        return self


class InvoiceUpdate(BaseModel):
    """Schema for updating an existing invoice.

    Line items are fully replaced on update — pass the complete new list.
    """

    tax_rate: Decimal | None = Field(default=None, ge=0, le=100, decimal_places=2)
    discount_type: Literal["percent", "fixed"] | None = None
    discount_value: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    due_date: date | None = None
    line_items: list[InvoiceLineItemCreate] | None = None

    @model_validator(mode="after")
    def validate_discount(self) -> "InvoiceUpdate":
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


class MarkPaidRequest(BaseModel):
    """Schema for marking an invoice as paid."""

    status: Literal["unpaid", "partially_paid", "paid"]
    amount_paid: Decimal | None = None


class InvoiceResponse(BaseResponseSchema):
    """Full invoice response including all audit fields and computed totals."""

    company_id: uuid.UUID
    job_id: uuid.UUID | None
    trade_scope_id: uuid.UUID | None = None
    milestone_id: uuid.UUID | None = None
    quote_id: uuid.UUID | None
    invoice_number: str
    status: str
    tax_rate: Decimal
    discount_type: str | None
    discount_value: Decimal
    due_date: date | None
    issued_at: datetime
    finalized_at: datetime | None
    amount_paid: Decimal = Decimal("0")
    line_items: list[InvoiceLineItemResponse] = Field(default_factory=list)

    # Computed financial totals
    subtotal: Decimal = Decimal("0")
    discount_amount: Decimal = Decimal("0")
    tax_amount: Decimal = Decimal("0")
    total: Decimal = Decimal("0")

    @field_validator(
        "subtotal", "discount_amount", "tax_amount", "total", "amount_paid", mode="before"
    )
    @classmethod
    def coerce_decimal(cls, v: object) -> Decimal:
        """Ensure computed totals are Decimal."""
        return Decimal(str(v)) if v is not None else Decimal("0")

    @classmethod
    def from_orm_with_totals(cls, invoice: object) -> "InvoiceResponse":
        """Build response from ORM instance, computing financial totals inline.

        Usage: InvoiceResponse.from_orm_with_totals(invoice)
        Requires invoice.line_items to be eagerly loaded.
        """
        obj = cls.model_validate(invoice)

        # Subtotal
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
