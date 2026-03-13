"""SQLAlchemy ORM models for the quotes domain.

Three models correspond to the tables created in migration 0011:
  - Quote          — quote lifecycle record with status machine and audit fields
  - QuoteLineItem  — individual labor/material line items for a quote
  - QuoteTemplate  — reusable line item collection for fast quote creation

All CLAUDE.md rules apply:
- Models with FK relationships MUST define relationship() with lazy="raise"
- All models inherit TenantScopedModel (provides id, company_id, version, timestamps)
- Use from __future__ import annotations + TYPE_CHECKING for circular-import safety
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Integer, Numeric, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.invoices.models import Invoice
    from app.features.jobs.models import Job


class Quote(TenantScopedModel):
    """Quote lifecycle record.

    status machine: draft -> sent -> viewed -> approved | declined | expired | revised
    revision_number: increments on re-issue (shown as "Quote v1", "Quote v2", etc.)
    discount_type: 'percent' or 'fixed' (NULL = no discount applied)
    discount_value: amount or percent depending on discount_type

    Relationships:
    - job: many-to-one — each quote belongs to one job
    - line_items: one-to-many — items ordered by sort_order
    - invoices: one-to-many — invoices generated from this quote (may be zero)
    """

    __tablename__ = "quotes"

    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id"),
        nullable=False,
    )
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="draft")
    revision_number: Mapped[int] = mapped_column(Integer, nullable=False, server_default="1")
    tax_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, server_default="0")
    discount_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    discount_value: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), nullable=False, server_default="0"
    )
    expiry_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    viewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    declined_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    decline_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    decline_detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    admin_notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status IN ('draft','sent','viewed','approved','declined','expired','revised')",
            name="quotes_status_check",
        ),
        CheckConstraint(
            "discount_type IN ('percent','fixed')",
            name="quotes_discount_type_check",
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    job: Mapped[Job] = relationship(  # type: ignore[name-defined]
        "Job",
        foreign_keys=[job_id],
        lazy="raise",
    )
    line_items: Mapped[list[QuoteLineItem]] = relationship(
        "QuoteLineItem",
        back_populates="quote",
        order_by="QuoteLineItem.sort_order",
        lazy="raise",
    )
    invoices: Mapped[list[Invoice]] = relationship(  # type: ignore[name-defined]
        "Invoice",
        back_populates="quote",
        foreign_keys="[Invoice.quote_id]",
        lazy="raise",
    )


class QuoteLineItem(TenantScopedModel):
    """Individual labor or material line item for a quote.

    item_type: 'labor' (time-based work) or 'material' (parts/supplies)
    quantity: supports decimal values (e.g., 1.5 hours, 2.75 kg)
    sort_order: client-controlled display ordering within a quote
    """

    __tablename__ = "quote_line_items"

    quote_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("quotes.id", ondelete="CASCADE"),
        nullable=False,
    )
    item_type: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    quantity: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    unit: Mapped[str] = mapped_column(Text, nullable=False)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")

    __table_args__ = (
        CheckConstraint(
            "item_type IN ('labor','material')",
            name="quote_line_items_item_type_check",
        ),
    )

    # Relationships
    quote: Mapped[Quote] = relationship(
        "Quote",
        foreign_keys=[quote_id],
        back_populates="line_items",
        lazy="raise",
    )


class QuoteTemplate(TenantScopedModel):
    """Reusable line item collection for fast quote creation.

    line_items_json: JSON text array of line item definitions.
      Stored as TEXT to avoid a join table — parsed at the service layer.
      Format: [{"description": ..., "item_type": ..., "quantity": ...,
                "unit": ..., "unit_price": ..., "sort_order": ...}, ...]
    tax_rate: default tax rate applied when template is used to create a quote
    """

    __tablename__ = "quote_templates"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    line_items_json: Mapped[str] = mapped_column(Text, nullable=False, server_default="'[]'")
    tax_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, server_default="0")
