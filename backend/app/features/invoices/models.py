"""SQLAlchemy ORM models for the invoices domain.

Two models correspond to the tables created in migration 0011:
  - Invoice         — billing document with payment tracking
  - InvoiceLineItem — individual labor/material line items for an invoice

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

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.base_models import TenantScopedModel

if TYPE_CHECKING:
    from app.features.jobs.models import Job
    from app.features.quotes.models import Quote


class Invoice(TenantScopedModel):
    """Billing document for a completed or in-progress job.

    invoice_number: human-readable sequential number (e.g. 'INV-0001').
      UNIQUE per company — generated at service layer using companies.invoice_sequence.
    quote_id: optional — invoices may be created directly without a prior quote.
    status: 'unpaid' | 'partially_paid' | 'paid'
    issued_at: when invoice was first issued (required, defaults to now)
    finalized_at: set when payment status reaches 'paid'

    Relationships:
    - job: many-to-one — invoice belongs to one job
    - quote: many-to-one (nullable) — invoice may derive from a quote
    - line_items: one-to-many — items ordered by sort_order
    """

    __tablename__ = "invoices"

    job_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("jobs.id"),
        nullable=False,
    )
    quote_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("quotes.id"),
        nullable=True,
    )
    invoice_number: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="unpaid")
    tax_rate: Mapped[Decimal] = mapped_column(Numeric(5, 2), nullable=False, server_default="0")
    discount_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    discount_value: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), nullable=False, server_default="0"
    )
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "status IN ('unpaid','partially_paid','paid')",
            name="invoices_status_check",
        ),
        CheckConstraint(
            "discount_type IN ('percent','fixed')",
            name="invoices_discount_type_check",
        ),
        UniqueConstraint(
            "company_id", "invoice_number", name="invoices_company_id_invoice_number_key"
        ),
    )

    # Relationships — lazy="raise" to surface accidental lazy loads loudly
    job: Mapped[Job] = relationship(  # type: ignore[name-defined]
        "Job",
        foreign_keys=[job_id],
        lazy="raise",
    )
    quote: Mapped[Quote | None] = relationship(  # type: ignore[name-defined]
        "Quote",
        foreign_keys=[quote_id],
        back_populates="invoices",
        lazy="raise",
    )
    line_items: Mapped[list[InvoiceLineItem]] = relationship(
        "InvoiceLineItem",
        back_populates="invoice",
        order_by="InvoiceLineItem.sort_order",
        lazy="raise",
    )


class InvoiceLineItem(TenantScopedModel):
    """Individual labor or material line item for an invoice.

    item_type: 'labor' (time-based work) or 'material' (parts/supplies)
    quantity: supports decimal values (e.g., 1.5 hours, 2.75 kg)
    sort_order: client-controlled display ordering within an invoice
    """

    __tablename__ = "invoice_line_items"

    invoice_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("invoices.id", ondelete="CASCADE"),
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
            name="invoice_line_items_item_type_check",
        ),
    )

    # Relationships
    invoice: Mapped[Invoice] = relationship(
        "Invoice",
        foreign_keys=[invoice_id],
        back_populates="line_items",
        lazy="raise",
    )
